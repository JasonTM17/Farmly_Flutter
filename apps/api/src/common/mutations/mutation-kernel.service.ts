import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import type { VerifiedPrincipal } from '../../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../../db/tenant-database.service.js';

export interface FarmMutationIntent {
  readonly schemaVersion: 'farm-mutation.v1';
  readonly continuityEpoch: string;
  readonly operationId: string;
  readonly type: string;
  readonly resourceId: string;
  readonly baseVersion?: number | null;
  readonly dependsOn: readonly string[];
  readonly payload: Readonly<Record<string, unknown>>;
}

interface MutationFunctionRow {
  readonly outcome: 'applied' | 'rejected' | 'conflict';
  readonly code: string | null;
  readonly response_data: Record<string, unknown>;
  readonly scope_policy_version: string;
  readonly continuity_epoch: string;
  readonly replayed: boolean;
}

interface OperationStatusRow {
  readonly operation_id: string;
  readonly outcome: 'applied' | 'rejected' | 'unknown';
}

interface SafeDatabaseFailure {
  readonly code: string | null;
  readonly message: string;
}

const OPERATION_ACTOR_DOMAIN = 'farmly-operation-actor:v1:';
const MAX_STATUS_IDS = 50;

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize((value as Record<string, unknown>)[key])]));
}

function stableJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

export function actorPseudonym(actorId: string): string {
  return createHash('sha256').update(OPERATION_ACTOR_DOMAIN).update(actorId, 'utf8').digest('hex');
}

function databaseFailure(error: unknown): SafeDatabaseFailure {
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
      .filter((part): part is string => typeof part === 'string').join(' '),
  };
}

@Injectable()
export class MutationKernelService {
  constructor(private readonly tenantDatabase: TenantDatabaseService) {}

  async applyOne(principal: VerifiedPrincipal, organizationId: string, intent: FarmMutationIntent, farmId?: string) {
    const result = await this.applyWithinTransaction(principal, organizationId, intent, farmId);
    if (result.outcome === 'conflict') this.throwConflict(result.code);
    return this.toSingleResponse(result);
  }

  async applyBatch(principal: VerifiedPrincipal, organizationId: string, intents: readonly FarmMutationIntent[], farmId?: string) {
    const outcomes: Array<{ operationId: string; outcome: string; code?: string }> = [];
    let scopePolicyVersion: string | undefined;
    for (const intent of intents) {
      const result = await this.applyWithinTransaction(principal, organizationId, intent, farmId);
      scopePolicyVersion = result.scope_policy_version;
      outcomes.push({
        operationId: intent.operationId,
        outcome: result.outcome,
        ...(result.code ? { code: result.code } : {}),
      });
    }
    return {
      data: { schemaVersion: 'farm-mutation-batch-result.v1', outcomes },
      meta: {
        schemaVersion: 'farmly.v1',
        asOf: new Date().toISOString(),
        ...(scopePolicyVersion ? { scopePolicyVersion } : {}),
      },
    };
  }

  async getOwnOperationStatus(principal: VerifiedPrincipal, operationIds: readonly string[]) {
    if (operationIds.length < 1 || operationIds.length > MAX_STATUS_IDS) {
      throw new BadRequestException('Invalid operation status request');
    }
    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<OperationStatusRow[]>`
          SELECT * FROM public.get_my_operation_status(
            ${principal.actorId}, ${actorPseudonym(principal.actorId)}, ${operationIds}::uuid[]
          )
        `;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });
      return {
        data: { operations: rows.map((row) => ({ operationId: row.operation_id, outcome: row.outcome })) },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  private async applyWithinTransaction(
    principal: VerifiedPrincipal,
    organizationId: string,
    intent: FarmMutationIntent,
    farmId?: string,
  ): Promise<MutationFunctionRow> {
    const pseudonym = actorPseudonym(principal.actorId);
    const requestHash = createHash('sha256')
      .update(stableJson({
        schemaVersion: intent.schemaVersion,
        organizationId,
        farmId: farmId ?? null,
        actorPseudonym: pseudonym,
        intent,
      }))
      .digest('hex');
    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<MutationFunctionRow[]>`
          SELECT outcome, code, response_data,
                 scope_policy_version::TEXT AS scope_policy_version,
                 continuity_epoch::TEXT AS continuity_epoch,
                 replayed
          FROM public.apply_farm_mutation(
            ${organizationId}::uuid,
            ${principal.actorId},
            ${pseudonym},
            ${intent.operationId}::uuid,
            ${requestHash},
            ${intent.continuityEpoch}::bigint,
            ${JSON.stringify(intent)}::jsonb,
            NULL::text,
            ${farmId ?? null}::uuid
          )
        `;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });
      const result = rows[0];
      if (!result || !/^[1-9][0-9]*$/.test(result.scope_policy_version)) {
        throw new Error('FARMLY_MUTATION_KERNEL_RESULT_INVALID');
      }
      return result;
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  private toSingleResponse(result: MutationFunctionRow) {
    return {
      data: result.response_data,
      meta: {
        schemaVersion: 'farmly.v1',
        asOf: new Date().toISOString(),
        scopePolicyVersion: result.scope_policy_version,
      },
    };
  }

  private throwConflict(code: string | null): never {
    if (code === 'OPERATION_ID_REUSED') throw new ConflictException({ code });
    throw new ConflictException({ code: code === 'RECONCILIATION_REQUIRED' ? code : 'VERSION_CONFLICT' });
  }

  private rethrowDatabaseFailure(error: unknown): never {
    const failure = databaseFailure(error);
    if (failure.code === '42501') {
      if (failure.message.includes('FARMLY_SCOPE_UNKNOWN')) {
        throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
      }
      if (failure.message.includes('FARMLY_PERMISSION_DENIED')) {
        throw new ForbiddenException({ code: 'PERMISSION_DENIED' });
      }
      throw new ForbiddenException({ code: 'ACCESS_REVOKED' });
    }
    if (failure.code === '22023') throw new BadRequestException('Invalid mutation request');
    if (failure.code === '23505') throw new ConflictException({ code: 'VERSION_CONFLICT' });
    throw new ServiceUnavailableException('The mutation could not be completed.');
  }
}
