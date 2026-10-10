import { ConflictException, ForbiddenException, GoneException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { Prisma } from '@prisma/client';
import type { ApiEnvironment } from '../config/environment.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';

const FARM_DIRECTORY_CURSOR_KIND = 'farm-directory.v1';
const FARM_DIRECTORY_CURSOR_MAX_LENGTH = 2048;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_POSTGRES_BIGINT = 9_223_372_036_854_775_807n;

interface FarmDirectoryCursor {
  readonly kind: typeof FARM_DIRECTORY_CURSOR_KIND;
  readonly organizationId: string;
  readonly actorBinding: string;
  readonly scopePolicyVersion: string;
  readonly continuityEpoch: string;
  readonly lastFarmId: string;
  readonly pageSize: number;
}

function isPositiveBigintString(value: unknown): value is string {
  if (typeof value !== 'string' || !/^[1-9][0-9]{0,18}$/.test(value)) return false;
  return BigInt(value) <= MAX_POSTGRES_BIGINT;
}

function signFarmDirectoryCursor(cursor: FarmDirectoryCursor, key: string): string {
  const payload = Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
  const signature = createHmac('sha256', key).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

function farmDirectoryActorBinding(actorId: string, key: string): string {
  return createHmac('sha256', key).update(`farm-directory-actor:${actorId}`).digest('base64url');
}

function readFarmDirectoryCursor(token: string, key: string): FarmDirectoryCursor | null {
  if (token.length < 1 || token.length > FARM_DIRECTORY_CURSOR_MAX_LENGTH) return null;
  const separator = token.indexOf('.');
  if (separator < 1 || separator !== token.lastIndexOf('.')) return null;
  const encodedPayload = token.slice(0, separator);
  const encodedSignature = token.slice(separator + 1);
  if (!/^[A-Za-z0-9_-]+$/.test(encodedPayload) || !/^[A-Za-z0-9_-]+$/.test(encodedSignature)) return null;

  const payload = Buffer.from(encodedPayload, 'base64url');
  const signature = Buffer.from(encodedSignature, 'base64url');
  if (payload.toString('base64url') !== encodedPayload || signature.toString('base64url') !== encodedSignature) return null;
  const expectedSignature = createHmac('sha256', key).update(encodedPayload).digest();
  if (signature.length !== expectedSignature.length || !timingSafeEqual(signature, expectedSignature)) return null;

  try {
    const value: unknown = JSON.parse(payload.toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const cursor = value as Record<string, unknown>;
    const fields = Object.keys(cursor).sort().join(',');
    if (fields !== 'actorBinding,continuityEpoch,kind,lastFarmId,organizationId,pageSize,scopePolicyVersion') return null;
    if (cursor.kind !== FARM_DIRECTORY_CURSOR_KIND
      || typeof cursor.organizationId !== 'string' || !UUID_PATTERN.test(cursor.organizationId)
      || typeof cursor.actorBinding !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(cursor.actorBinding)
      || !isPositiveBigintString(cursor.scopePolicyVersion)
      || !isPositiveBigintString(cursor.continuityEpoch)
      || typeof cursor.lastFarmId !== 'string' || !UUID_PATTERN.test(cursor.lastFarmId)
      || !Number.isInteger(cursor.pageSize) || (cursor.pageSize as number) < 1 || (cursor.pageSize as number) > 100) {
      return null;
    }
    return cursor as unknown as FarmDirectoryCursor;
  } catch {
    return null;
  }
}

interface OrganizationIndexRow {
  readonly organization_id: string;
  readonly organization_name: string;
  readonly organization_status: string;
  readonly policy_version: bigint;
  readonly membership_role: string;
  readonly membership_version: number;
}

interface OrganizationCreatedRow {
  readonly organization_id: string;
  readonly membership_id: string;
  readonly policy_version: bigint;
}

interface FarmDirectoryScopeRow {
  readonly scope_policy_version: string;
  readonly continuity_epoch: string;
}

interface FarmDirectoryFarmRow {
  readonly farm_id: string;
  readonly farm_name: string;
  readonly farm_status: 'active' | 'archived';
  readonly grant_role: 'owner' | 'admin' | 'manager' | 'worker' | 'viewer';
}

function sqlState(error: unknown): string | null {
  if (!error || typeof error !== 'object') return null;
  const value = error as { code?: unknown; meta?: { code?: unknown } };
  if (typeof value.code === 'string') return value.code;
  return typeof value.meta?.code === 'string' ? value.meta.code : null;
}

@Injectable()
export class OrganizationsService {
  private readonly cursorSigningKey: string;

  constructor(
    private readonly tenantDatabase: TenantDatabaseService,
    config: ConfigService,
  ) {
    const environment = config.get<ApiEnvironment>('farmlyEnvironment');
    if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
    this.cursorSigningKey = environment.cursorSigningKey;
  }

  async listFor(principal: VerifiedPrincipal, limit: number, afterId: string | null) {
    const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      return transaction.$queryRaw<OrganizationIndexRow[]>`
        SELECT * FROM public.list_my_organizations(
          ${principal.actorId}, ${limit}, ${afterId}::uuid
        )
      `;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      data: {
        organizations: page.map((row) => ({
          id: row.organization_id,
          name: row.organization_name,
          status: row.organization_status,
          policyVersion: row.policy_version.toString(),
          membership: { role: row.membership_role, version: row.membership_version },
        })),
      },
      page: hasMore ? { nextCursor: page.at(-1)?.organization_id, hasMore } : { hasMore },
      meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
    };
  }

  async farmDirectoryFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    requestedLimit: number | null,
    cursorToken: string | null,
  ) {
    const normalizedOrganizationId = organizationId.toLowerCase();
    const cursor = cursorToken === null ? null : readFarmDirectoryCursor(cursorToken, this.cursorSigningKey);
    if (cursorToken !== null && (!cursor
      || cursor.organizationId !== normalizedOrganizationId
      || cursor.actorBinding !== farmDirectoryActorBinding(principal.actorId, this.cursorSigningKey)
      || (requestedLimit !== null && cursor.pageSize !== requestedLimit))) {
      throw new GoneException({ code: 'CURSOR_EXPIRED' });
    }
    const pageSize = cursor?.pageSize ?? requestedLimit ?? 25;
    const afterFarmId = cursor?.lastFarmId ?? null;

    const directory = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const scopes = await transaction.$queryRaw<FarmDirectoryScopeRow[]>`
        SELECT policy_version::TEXT AS scope_policy_version,
               continuity_epoch::TEXT AS continuity_epoch
        FROM public.organizations
        WHERE id = ${organizationId}::uuid
      `;
      const scope = scopes[0];
      if (!scope) return null;

      if (cursor && (cursor.scopePolicyVersion !== scope.scope_policy_version
        || cursor.continuityEpoch !== scope.continuity_epoch)) {
        throw new GoneException({ code: 'CURSOR_EXPIRED' });
      }

      const farms = await transaction.$queryRaw<FarmDirectoryFarmRow[]>`
        SELECT farm.id::TEXT AS farm_id,
               farm.name::TEXT AS farm_name,
               farm.status::TEXT AS farm_status,
               CASE
                 WHEN membership.role = 'owner' THEN 'owner'
                 WHEN membership.role = 'admin' THEN 'admin'
                 ELSE grant_row.role::TEXT
               END AS grant_role
        FROM public.farms AS farm
        JOIN public.organization_memberships AS membership
          ON membership.organization_id = farm.organization_id
         AND membership.user_id = ${principal.actorId}
         AND membership.status = 'active'
        LEFT JOIN public.farm_grants AS grant_row
          ON grant_row.organization_id = farm.organization_id
         AND grant_row.membership_id = membership.id
         AND grant_row.farm_id = farm.id
        WHERE farm.organization_id = ${organizationId}::uuid
          AND (membership.role IN ('owner', 'admin') OR grant_row.id IS NOT NULL)
          AND (${afterFarmId}::uuid IS NULL OR farm.id > ${afterFarmId}::uuid)
        ORDER BY farm.id
        LIMIT ${pageSize + 1}
      `;
      return { scope, farms };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });

    if (!directory) throw new ForbiddenException({ code: 'ACCESS_REVOKED' });
    const hasMore = directory.farms.length > pageSize;
    const farms = directory.farms.slice(0, pageSize);
    const lastFarmId = farms.at(-1)?.farm_id;
    const nextCursor = hasMore && lastFarmId
      ? signFarmDirectoryCursor({
        kind: FARM_DIRECTORY_CURSOR_KIND,
        organizationId: normalizedOrganizationId,
        actorBinding: farmDirectoryActorBinding(principal.actorId, this.cursorSigningKey),
        scopePolicyVersion: directory.scope.scope_policy_version,
        continuityEpoch: directory.scope.continuity_epoch,
        lastFarmId,
        pageSize,
      }, this.cursorSigningKey)
      : undefined;
    return {
      schemaVersion: 'farm-directory.v1',
      scopePolicyVersion: directory.scope.scope_policy_version,
      continuityEpoch: directory.scope.continuity_epoch,
      farms: farms.map((farm) => ({
        farmId: farm.farm_id,
        farmName: farm.farm_name,
        status: farm.farm_status,
        grantRole: farm.grant_role,
      })),
      ...(nextCursor ? { nextCursor } : {}),
    };
  }

  async createFor(principal: VerifiedPrincipal, requestId: string, name: string) {
    try {
      const created = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        const rows = await transaction.$queryRaw<OrganizationCreatedRow[]>`
          SELECT * FROM public.create_organization_for_verified_principal(
            ${principal.actorId}, ${requestId}::uuid, ${name}
          )
        `;
        return rows[0];
      }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

      if (!created) throw new Error('FARMLY_ORGANIZATION_FACTORY_EMPTY');
      return {
        data: {
          id: created.organization_id,
          name,
          status: 'active',
          policyVersion: created.policy_version.toString(),
          membership: { id: created.membership_id, role: 'owner', status: 'active', version: 1 },
        },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      if (sqlState(error) === '23505') throw new ConflictException({ code: 'OPERATION_ID_REUSED' });
      throw error;
    }
  }
}
