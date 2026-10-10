import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import type { Prisma } from '@prisma/client';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import { actorPseudonym } from '../common/mutations/mutation-kernel.service.js';
import type { ApiEnvironment } from '../config/environment.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';

// Canonical request hash: same clientRequestId + byte-identical payload
// replays; any field change under the same key is a 409 (spec05 §3).
export interface AiCreateInput {
  readonly clientRequestId: string;
  readonly conversationId: string | null;
  readonly prompt: string;
  readonly consentRevision: number;
  readonly contextMode: 'authorized-summary' | 'none';
}

type PrismaTx = Prisma.TransactionClient;

interface DbFailure {
  readonly code: string | null;
  readonly message: string;
}

function databaseFailure(error: unknown): DbFailure {
  if (!error || typeof error !== 'object') return { code: null, message: '' };
  const value = error as {
    readonly code?: unknown;
    readonly message?: unknown;
    readonly meta?: {
      readonly code?: unknown;
      readonly message?: unknown;
      readonly driverAdapterError?: { readonly cause?: { readonly code?: unknown; readonly originalCode?: unknown; readonly message?: unknown } };
    };
  };
  const cause = value.meta?.driverAdapterError?.cause;
  return {
    code: [cause?.code, cause?.originalCode, value.meta?.code, value.code]
      .find((candidate): candidate is string => typeof candidate === 'string') ?? null,
    message: [cause?.message, value.meta?.message, value.message]
      .find((candidate): candidate is string => typeof candidate === 'string') ?? '',
  };
}

// Integer micro-currency conversion — decimal strings only, never float math
// (spec05 §6).
export function decimalToMicros(decimal: string): bigint {
  const match = /^(\d+)(?:\.(\d{1,6}))?$/.exec(decimal.trim());
  if (!match) throw new Error('INVALID_COST_CAP');
  const whole = BigInt(match[1]);
  const fraction = (match[2] ?? '').padEnd(6, '0');
  return whole * 1_000_000n + BigInt(fraction || '0');
}

export function aiRequestHash(input: AiCreateInput): string {
  return createHash('sha256')
    .update(JSON.stringify({
      schemaVersion: 'farmly-ai-request.v1',
      clientRequestId: input.clientRequestId,
      conversationId: input.conversationId,
      prompt: input.prompt,
      consentRevision: input.consentRevision,
      contextMode: input.contextMode,
    }))
    .digest('hex');
}

@Injectable()
export class FarmlyAiService {
  private readonly environment: ApiEnvironment | undefined;

  constructor(
    private readonly tenantDatabase: TenantDatabaseService,
    config: ConfigService,
  ) {
    this.environment = config.get<ApiEnvironment>('farmlyEnvironment');
  }

  get aiEnabled(): boolean {
    return this.environment?.aiEnabled ?? false;
  }

  private requireEnabled(): ApiEnvironment {
    const environment = this.environment;
    if (!environment?.aiEnabled) {
      throw new ServiceUnavailableException({ code: 'AI_UNAVAILABLE' });
    }
    return environment;
  }

  private async withActor<T>(
    principal: VerifiedPrincipal,
    run: (transaction: PrismaTx, pseudonym: string) => Promise<T>,
  ): Promise<T> {
    const pseudonym = actorPseudonym(principal.actorId);
    return this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      await transaction.$queryRaw`SELECT set_config('app.actor_pseudonym', ${pseudonym}, TRUE)`;
      return run(transaction as PrismaTx, pseudonym);
    });
  }

  // ------------------------------------------------------------------ create

  /**
   * Reserve quota + create the durable request (spec05 §§3,6). The definer
   * function owns consent recheck, rate gate and atomic counter reservation;
   * this layer computes the conservative cost bound from the operator price
   * snapshot and fails closed when pricing is absent.
   */
  async createRequest(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    input: AiCreateInput,
  ): Promise<Record<string, unknown>> {
    const environment = this.requireEnabled();
    const snapshotId = environment.aiPriceSnapshotId;
    if (!snapshotId) throw new ServiceUnavailableException({ code: 'AI_UNAVAILABLE' });

    const requestHash = aiRequestHash(input);
    try {
      return await this.withActor(principal, async (transaction, pseudonym) => {
        const tx = transaction;

        // Lazy crash recovery for this owner's stale in-flight rows: a dead
        // executor's attempt is interrupted + usage unknown before any new
        // reservation is admitted (spec05 §4.4).
        const staleSeconds = Math.max(2, Math.ceil((environment.aiRequestTimeoutMs * 2) / 1000));
        await tx.$queryRaw`
          SELECT public.farmly_ai_recover_interrupted(
            ${principal.actorId}, ${pseudonym}, ${staleSeconds})
        `;

        const priceRows = await tx.$queryRaw<
          { model: string; input_micros_per_mtok: bigint; output_micros_per_mtok: bigint }[]
        >`
          SELECT * FROM public.farmly_ai_price_snapshot(${snapshotId})
        `;
        const price = priceRows[0];
        if (!price) throw new ServiceUnavailableException({ code: 'AI_UNAVAILABLE' });

        // Conservative input bound: the dispatcher serializes at most
        // AI_MAX_INPUT_BYTES, and no BPE tokenizer emits more tokens than
        // bytes — so bytes are a provable upper bound for the reservation.
        const reservedInputBytes = BigInt(environment.aiMaxInputBytes);
        const reservedOutputTokens = environment.aiMaxOutputTokens;
        const inputTokenBound = reservedInputBytes;
        const micros =
          ((inputTokenBound * price.input_micros_per_mtok) +
            (BigInt(reservedOutputTokens) * price.output_micros_per_mtok) +
            999_999n) / 1_000_000n;
        const projectCap = environment.aiProjectCostCap
          ? decimalToMicros(environment.aiProjectCostCap)
          : null;

        const created = await tx.$queryRaw<{ result: Record<string, unknown> }[]>`
          SELECT public.farmly_ai_create_request(
            ${principal.actorId},
            ${pseudonym},
            ${organizationId}::uuid,
            ${farmId}::uuid,
            ${input.conversationId}::uuid,
            ${input.clientRequestId}::uuid,
            ${requestHash},
            ${input.prompt},
            ${input.contextMode}::public.ai_context_mode,
            ${input.consentRevision}::integer,
            ${reservedOutputTokens}::integer,
            ${reservedInputBytes}::bigint,
            ${micros}::bigint,
            ${environment.aiUserRateLimit ?? null}::integer,
            ${environment.aiOrgTokenCap ?? null}::bigint,
            ${projectCap}::bigint
          ) AS result
        `;
        return created[0]?.result ?? {};
      });
    } catch (error) {
      this.rethrowAiFailure(error);
    }
  }

  // ------------------------------------------------------------------ status

  /** Owner-private request state (spec05 §3) for post-cursor-expiry reconnect. */
  async getRequest(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    requestId: string,
  ): Promise<Record<string, unknown>> {
    this.requireEnabled();
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const rows = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT request.id::TEXT AS "requestId",
               request.conversation_id::TEXT AS "conversationId",
               request.status::TEXT AS "status",
               request.usage_state::TEXT AS "usageState",
               request.finish_reason AS "finishReason",
               request.truncated,
               request.error_code AS "errorCode",
               request.input_tokens AS "inputTokens",
               request.output_tokens AS "outputTokens",
               request.total_tokens AS "totalTokens",
               request.reported_cost_micros::TEXT AS "reportedCostMicros",
               request.latest_seq::TEXT AS "latestSeq",
               request.terminal_at AS "terminalAt",
               request.created_at AS "createdAt",
               (request.content_purged_at IS NOT NULL
                 OR (request.terminal_at IS NOT NULL AND request.content_expires_at IS NOT NULL
                      AND request.content_expires_at <= CURRENT_TIMESTAMP)) AS "contentExpired",
               message.id::TEXT AS "finalMessageId",
               message.body AS "finalBody"
          FROM public.ai_requests AS request
          LEFT JOIN public.ai_messages AS message
            ON message.id = request.final_message_id
         WHERE request.id = ${requestId}::uuid
           AND request.organization_id = ${organizationId}::uuid
           AND request.farm_id = ${farmId}::uuid
      `;
      const row = rows[0];
      if (!row) throw new NotFoundException({ code: 'NOT_FOUND' });
      return row;
    });
  }

  // ------------------------------------------------------------------ cancel

  async cancelRequest(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    requestId: string,
  ): Promise<Record<string, unknown>> {
    this.requireEnabled();
    try {
      return await this.withActor(principal, async (transaction, pseudonym) => {
        const tx = transaction;
        const rows = await tx.$queryRaw<{ result: Record<string, unknown> }[]>`
          SELECT public.farmly_ai_cancel_request(
            ${principal.actorId}, ${pseudonym}, ${requestId}::uuid) AS result
        `;
        const result = rows[0]?.result;
        if (!result) throw new NotFoundException({ code: 'NOT_FOUND' });
        // Prove scope: the request must belong to this org+farm — the definer
        // is owner-bound but the route is farm-scoped for honest 404s.
        const scope = await tx.$queryRaw<{ ok: boolean }[]>`
          SELECT EXISTS(
            SELECT 1 FROM public.ai_requests
             WHERE id = ${requestId}::uuid
               AND organization_id = ${organizationId}::uuid
               AND farm_id = ${farmId}::uuid) AS ok
        `;
        if (!scope[0]?.ok) throw new NotFoundException({ code: 'NOT_FOUND' });
        return result;
      });
    } catch (error) {
      this.rethrowAiFailure(error);
    }
  }

  // ------------------------------------------------------------------ events

  /**
   * Persisted-event page for the SSE stream (spec05 §5): events are read
   * after persistence so replay and live tail share one truthful log.
   * Returns rows plus the request's terminal flag so the stream knows when
   * the tail is complete.
   */
  async readEventPage(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    requestId: string,
    afterSeq: number,
    limit = 100,
  ): Promise<{ events: Record<string, unknown>[]; terminal: boolean }> {
    this.requireEnabled();
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const request = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT request.terminal_at IS NOT NULL AS "terminal"
          FROM public.ai_requests AS request
         WHERE request.id = ${requestId}::uuid
           AND request.organization_id = ${organizationId}::uuid
           AND request.farm_id = ${farmId}::uuid
      `;
      if (!request[0]) throw new NotFoundException({ code: 'NOT_FOUND' });
      const events = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT event.event_id AS "id",
               event.request_id::TEXT AS "requestId",
               event.seq::TEXT AS "seq",
               event.type::TEXT AS "type",
               event.data
          FROM public.ai_events AS event
         WHERE event.request_id = ${requestId}::uuid
           AND event.seq > ${afterSeq}
         ORDER BY event.seq
         LIMIT ${Math.min(Math.max(limit, 1), 500)}
      `;
      return { events, terminal: Boolean(request[0]['terminal']) };
    });
  }

  async requestExistsForOwner(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    requestId: string,
  ): Promise<boolean> {
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const rows = await tx.$queryRaw<{ ok: boolean }[]>`
        SELECT EXISTS(
          SELECT 1 FROM public.ai_requests
           WHERE id = ${requestId}::uuid
             AND organization_id = ${organizationId}::uuid
             AND farm_id = ${farmId}::uuid) AS ok
      `;
      return Boolean(rows[0]?.ok);
    });
  }

  /** Live farm-grant recheck for SSE emission batches (spec05 §5). */
  async canStillReadFarm(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
  ): Promise<boolean> {
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const rows = await tx.$queryRaw<{ can_read: boolean }[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      return Boolean(rows[0]?.can_read);
    });
  }

  /**
   * Grant or update the caller's private AI context consent (contract
   * `setAiConsent`). Consent is a per-(user, org) singleton: an unchanged
   * decision returns the current revision without calling the definer — a
   * redundant re-grant must not bump the revision and invalidate in-flight
   * requests bound to it. Any real change goes through `farmly_ai_set_consent`,
   * which owns revision++ and the queued-not-dispatched cancellation wave.
   */
  async setConsent(
    principal: VerifiedPrincipal,
    organizationId: string,
    input: { granted: boolean; aiSafeSummaryOptedIn: boolean },
  ): Promise<Record<string, unknown>> {
    return this.withActor(principal, async (transaction, pseudonym) => {
      const tx = transaction;
      const access = await tx.$queryRaw<{ ok: boolean }[]>`
        SELECT public.farmly_actor_has_organization_access(${organizationId}::uuid) AS ok
      `;
      if (!access[0]?.ok) throw new NotFoundException({ code: 'NOT_FOUND' });
      const current = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT consent.granted, consent.revision,
               consent.ai_safe_summary_opted_in AS "summaryOptedIn"
          FROM public.ai_consents AS consent
         WHERE consent.organization_id = ${organizationId}::uuid
      `;
      const row = current[0];
      if (
        row
        && Boolean(row['granted']) === input.granted
        && Boolean(row['summaryOptedIn']) === input.aiSafeSummaryOptedIn
      ) {
        return {
          granted: input.granted,
          revision: toInt(row['revision']),
          summaryOptedIn: input.aiSafeSummaryOptedIn,
          unchanged: true,
        };
      }
      const updated = await tx.$queryRaw<{ revision: number }[]>`
        SELECT public.farmly_ai_set_consent(
          ${principal.actorId}, ${pseudonym}::CHAR(64),
          ${organizationId}::uuid,
          ${input.granted}::boolean,
          ${input.aiSafeSummaryOptedIn}::boolean) AS revision
      `;
      return {
        granted: input.granted,
        revision: toInt(updated[0]?.['revision']),
        summaryOptedIn: input.aiSafeSummaryOptedIn,
      };
    });
  }

  // ------------------------------------------------------------ conversations

  async listConversations(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
  ): Promise<Record<string, unknown>> {
    this.requireEnabled();
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const conversations = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT conversation.id::TEXT AS "conversationId",
               conversation.title,
               conversation.status::TEXT AS "status",
               conversation.created_at AS "createdAt",
               conversation.latest_completed_at AS "latestCompletedAt"
          FROM public.ai_conversations AS conversation
         WHERE conversation.organization_id = ${organizationId}::uuid
           AND conversation.farm_id = ${farmId}::uuid
         ORDER BY conversation.created_at DESC, conversation.id
         LIMIT 100
      `;
      const consent = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT consent.revision, consent.granted, consent.ai_safe_summary_opted_in AS "summaryOptedIn"
          FROM public.ai_consents AS consent
         WHERE consent.organization_id = ${organizationId}::uuid
      `;
      return {
        conversations,
        consent: consent[0]
          ? {
              revision: toInt(consent[0]['revision']),
              granted: Boolean(consent[0]['granted']),
              summaryOptedIn: Boolean(consent[0]['summaryOptedIn']),
            }
          : null,
      };
    });
  }

  async listMessages(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    conversationId: string,
    before?: string,
    limit = 50,
  ): Promise<Record<string, unknown>> {
    this.requireEnabled();
    return this.withActor(principal, async (transaction) => {
      const tx = transaction;
      const conversation = await tx.$queryRaw<{ ok: boolean }[]>`
        SELECT EXISTS(
          SELECT 1 FROM public.ai_conversations
           WHERE id = ${conversationId}::uuid
             AND organization_id = ${organizationId}::uuid
             AND farm_id = ${farmId}::uuid) AS ok
      `;
      if (!conversation[0]?.ok) throw new NotFoundException({ code: 'NOT_FOUND' });
      const rows = before
        ? await tx.$queryRaw<Record<string, unknown>[]>`
            SELECT message.id::TEXT AS "messageId", message.role::TEXT AS "role",
                   message.body, message.request_id::TEXT AS "requestId",
                   message.created_at AS "createdAt"
              FROM public.ai_messages AS message
             WHERE message.conversation_id = ${conversationId}::uuid
               AND message.created_at < ${new Date(before)}
             ORDER BY message.created_at DESC, message.id DESC
             LIMIT ${Math.min(Math.max(limit, 1), 200)}
          `
        : await tx.$queryRaw<Record<string, unknown>[]>`
            SELECT message.id::TEXT AS "messageId", message.role::TEXT AS "role",
                   message.body, message.request_id::TEXT AS "requestId",
                   message.created_at AS "createdAt"
              FROM public.ai_messages AS message
             WHERE message.conversation_id = ${conversationId}::uuid
             ORDER BY message.created_at DESC, message.id DESC
             LIMIT ${Math.min(Math.max(limit, 1), 200)}
          `;
      return { messages: rows };
    });
  }

  // ------------------------------------------------------------------ errors

  private rethrowAiFailure(error: unknown): never {
    const failure = databaseFailure(error);
    const message = failure.message;
    if (message.includes('FARMLY_AI_REQUEST_MISMATCH')) {
      throw new ConflictException({ code: 'AI_REQUEST_MISMATCH' });
    }
    if (message.includes('FARMLY_AI_CONSENT_REQUIRED')) {
      throw new ForbiddenException({ code: 'AI_CONSENT_REQUIRED' });
    }
    if (message.includes('FARMLY_AI_RATE_LIMITED')) {
      // Contract: 429 for "rate or AI quota limit reached before dispatch".
      throw new HttpException({ code: 'RATE_LIMITED' }, HttpStatus.TOO_MANY_REQUESTS);
    }
    if (message.includes('FARMLY_AI_ORG_CAP') || message.includes('FARMLY_AI_PROJECT_CAP')) {
      throw new HttpException({ code: 'AI_QUOTA_EXCEEDED' }, HttpStatus.TOO_MANY_REQUESTS);
    }
    if (message.includes('FARMLY_AI_CONVERSATION_UNKNOWN')
      || message.includes('FARMLY_AI_REQUEST_UNKNOWN')) {
      throw new NotFoundException({ code: 'NOT_FOUND' });
    }
    if (message.includes('FARMLY_ACCESS_REVOKED')) {
      throw new ForbiddenException({ code: 'ACCESS_REVOKED' });
    }
    if (error instanceof NotFoundException
      || error instanceof ForbiddenException
      || error instanceof ConflictException
      || error instanceof BadRequestException
      || error instanceof ServiceUnavailableException) {
      throw error;
    }
    throw new ServiceUnavailableException('The AI request could not be completed.');
  }
}

function toInt(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number.parseInt(String(value ?? '0'), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}
