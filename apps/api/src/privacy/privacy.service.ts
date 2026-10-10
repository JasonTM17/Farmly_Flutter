import {
  ConflictException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import { actorPseudonym } from '../common/mutations/mutation-kernel.service.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';

type PrismaTx = Prisma.TransactionClient;

@Injectable()
export class FarmlyPrivacyService {
  constructor(private readonly tenantDatabase: TenantDatabaseService) {}

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

  /** Register/revoke an installation binding — push token is forwarded to
   * the definer and never read back or logged by this layer. */
  async mutateDeviceRegistration(
    principal: VerifiedPrincipal,
    input: {
      operationId: string;
      action: 'register' | 'revoke';
      deviceId: string;
      pushToken?: string;
    },
  ): Promise<Record<string, unknown>> {
    return this.withActor(principal, async (tx, pseudonym) => {
      try {
        const rows = await tx.$queryRaw<Record<string, unknown>[]>`
          SELECT (public.farmly_mutate_device_registration(
            ${principal.actorId}, ${pseudonym}::CHAR(64),
            ${input.operationId}::uuid, ${input.action},
            ${input.deviceId}, ${input.pushToken ?? null})).*
        `;
        const row = rows[0];
        if (!row?.['id']) throw new InternalServerErrorException();
        return {
          deviceId: row['device_id'],
          status: row['status'],
          registeredAt: row['registered_at'],
          revokedAt: row['revoked_at'],
        };
      } catch (error) {
        this.rethrowKnown(error);
      }
    });
  }

  /** Audited privacy request — the definer executes export/delete-history/
   * withdraw-ai-consent atomically and idempotently on operationId. */
  async createPrivacyRequest(
    principal: VerifiedPrincipal,
    input: { operationId: string; action: string; confirmation?: string },
  ): Promise<Record<string, unknown>> {
    return this.withActor(principal, async (tx, pseudonym) => {
      try {
        const rows = await tx.$queryRaw<Record<string, unknown>[]>`
          SELECT (public.farmly_create_privacy_request(
            ${principal.actorId}, ${pseudonym}::CHAR(64),
            ${input.operationId}::uuid,
            ${input.action}::public.privacy_request_action,
            ${input.confirmation ?? null})).*
        `;
        const row = rows[0];
        if (!row?.['id']) throw new InternalServerErrorException();
        return {
          requestId: row['id'],
          action: row['action'],
          status: row['status'],
          requestedAt: row['requested_at'],
          completedAt: row['completed_at'],
          payload: row['payload'] ?? null,
        };
      } catch (error) {
        this.rethrowKnown(error);
      }
    });
  }

  private rethrowKnown(error: unknown): never {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes('FARMLY_OPERATION_ID_REUSED')) {
      throw new ConflictException({ code: 'OPERATION_ID_REUSED' });
    }
    if (message.includes('FARMLY_PRIVACY_ACTION_INVALID')) {
      throw new ConflictException({ code: 'VALIDATION_FAILED' });
    }
    throw error;
  }
}
