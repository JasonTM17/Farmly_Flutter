import { Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import { actorPseudonym } from '../common/mutations/mutation-kernel.service.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';

type PrismaTx = Prisma.TransactionClient;

@Injectable()
export class FarmlyNotificationsService {
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

  /** Owner-scoped feed — RLS already hides foreign rows; the pseudonym
   * predicate in the query keeps the index honest and self-documents scope. */
  async listNotifications(
    principal: VerifiedPrincipal,
    options: { limit: number; cursor?: string },
  ): Promise<Record<string, unknown>> {
    return this.withActor(principal, async (tx, pseudonym) => {
      // Lazy reminder sweep — dedup_key makes this idempotent; runs inside
      // the caller's tx so it never produces duplicate rows under races.
      await tx.$queryRaw`SELECT public.farmly_generate_task_reminders(INTERVAL '24 hours')`;
      const limit = Math.min(Math.max(options.limit || 25, 1), 100);
      const separator = options.cursor?.indexOf('|') ?? -1;
      const cursorTs = separator > 0 ? options.cursor!.slice(0, separator) : null;
      const cursorId = separator > 0 ? options.cursor!.slice(separator + 1) : null;
      const rows = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT n.id::TEXT AS "id", n.kind::TEXT AS "kind", n.title, n.body,
               n.source_ref AS "sourceRef", n.read_at AS "readAt", n.created_at AS "createdAt",
               n.organization_id::TEXT AS "organizationId", n.farm_id::TEXT AS "farmId"
          FROM public.notifications AS n
         WHERE n.actor_pseudonym = ${pseudonym}
           AND (${cursorTs}::TIMESTAMPTZ IS NULL
                OR n.created_at < ${cursorTs}
                OR (n.created_at = ${cursorTs} AND n.id::TEXT < ${cursorId}))
         ORDER BY n.created_at DESC, n.id DESC
         LIMIT ${limit + 1}
      `;
      const hasMore = rows.length > limit;
      const items = rows.slice(0, limit);
      const last = items[items.length - 1];
      return {
        items,
        page: {
          nextCursor: hasMore && last
            ? `${last['createdAt']}|${last['id']}`
            : null,
        },
      };
    });
  }

  async markRead(
    principal: VerifiedPrincipal,
    notificationId: string,
  ): Promise<Record<string, unknown>> {
    return this.withActor(principal, async (tx, pseudonym) => {
      const rows = await tx.$queryRaw<Record<string, unknown>[]>`
        SELECT (public.farmly_mark_notification_read(
          ${notificationId}::uuid, ${pseudonym}::CHAR(64))).*
      `;
      const row = rows[0];
      if (!row || !row['id']) throw new NotFoundException({ code: 'NOT_FOUND' });
      return {
        id: row['id'],
        readAt: row['read_at'],
      };
    });
  }
}

