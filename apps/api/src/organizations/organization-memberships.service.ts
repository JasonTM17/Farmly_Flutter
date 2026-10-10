import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import type { FarmGrantRole, OrganizationRole } from './organization-authorization.js';

export interface MembershipFarmGrantInput {
  readonly farmId: string;
  readonly role: FarmGrantRole;
}

export interface UpdateMembershipInput {
  readonly role: Exclude<OrganizationRole, 'owner'>;
  readonly farmGrants: readonly MembershipFarmGrantInput[];
}

interface MembershipIndexRow {
  readonly membership_id: string;
  readonly user_id: string;
  readonly organization_role: OrganizationRole;
  readonly membership_status: 'active' | 'suspended' | 'removed';
  readonly membership_version: number;
  readonly farm_grants: readonly { readonly farmId: string; readonly role: FarmGrantRole; readonly version: number }[];
}

interface OrganizationPolicyVersionRow {
  readonly scope_policy_version: string;
}

interface FunctionResultRow<T extends { readonly replayed: boolean }> {
  readonly result: T;
  readonly replayed?: boolean;
  readonly changed?: boolean;
}

export interface MembershipView {
  readonly id: string;
  readonly userId: string;
  readonly role: OrganizationRole;
  readonly status: 'active' | 'suspended' | 'removed';
  readonly version: number;
  readonly farmGrants: readonly { readonly farmId: string; readonly role: FarmGrantRole; readonly version: number }[];
}

export interface MembershipMutationResult {
  readonly membership: MembershipView;
  readonly policyVersion: string;
  readonly changed: boolean;
  readonly replayed: boolean;
}

export interface OwnershipTransferResult {
  readonly targetMembershipId: string;
  readonly formerOwnerMembershipId: string;
  readonly formerOwnerRole: 'admin' | 'owner';
  readonly formerOwnerStatus: 'active' | 'removed';
  readonly policyVersion: string;
  readonly replayed: boolean;
}

function databaseFailure(error: unknown): { readonly code: string | null; readonly message: string } {
  if (!error || typeof error !== 'object') return { code: null, message: '' };
  const value = error as {
    readonly code?: unknown;
    readonly message?: unknown;
    readonly meta?: {
      readonly code?: unknown;
      readonly message?: unknown;
      readonly driverAdapterError?: { readonly cause?: { readonly code?: unknown; readonly originalCode?: unknown } };
    };
  };
  return {
    code: [
      value.meta?.driverAdapterError?.cause?.code,
      value.meta?.driverAdapterError?.cause?.originalCode,
      value.meta?.code,
      value.code,
    ]
      .find((candidate): candidate is string => typeof candidate === 'string') ?? null,
    message: [value.meta?.message, value.message].filter((part): part is string => typeof part === 'string').join(' '),
  };
}

function requestHash(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function membershipView(row: MembershipIndexRow): MembershipView {
  return {
    id: row.membership_id,
    userId: row.user_id,
    role: row.organization_role,
    status: row.membership_status,
    version: row.membership_version,
    farmGrants: row.farm_grants,
  };
}

@Injectable()
export class OrganizationMembershipsService {
  constructor(private readonly tenantDatabase: TenantDatabaseService) {}

  async listFor(principal: VerifiedPrincipal, organizationId: string, limit: number, afterId: string | null) {
    try {
      const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        const rows = await transaction.$queryRaw<MembershipIndexRow[]>`
          SELECT * FROM public.list_organization_memberships(
            ${organizationId}::uuid, ${limit}, ${afterId}::uuid
          )
        `;
        const policyRows = await transaction.$queryRaw<OrganizationPolicyVersionRow[]>`
          SELECT policy_version::TEXT AS scope_policy_version
          FROM public.organizations
          WHERE id = ${organizationId}::uuid
        `;
        return { rows, scopePolicyVersion: policyRows[0]?.scope_policy_version };
      }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
      if (result.scopePolicyVersion === undefined) throw new Error('FARMLY_SCOPE_POLICY_VERSION_UNAVAILABLE');
      const { rows } = result;
      const hasMore = rows.length > limit;
      const page = rows.slice(0, limit);
      return {
        data: { memberships: page.map(membershipView) },
        page: hasMore ? { nextCursor: page.at(-1)?.membership_id, hasMore } : { hasMore },
        meta: {
          schemaVersion: 'farmly.v1',
          asOf: new Date().toISOString(),
          scopePolicyVersion: result.scopePolicyVersion,
        },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  async updateFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    membershipId: string,
    operationId: string,
    input: UpdateMembershipInput,
  ) {
    const grants = [...input.farmGrants]
      .map(({ farmId, role }) => ({ farmId, role }))
      .sort((left, right) => left.farmId.localeCompare(right.farmId));
    const hash = requestHash({ organizationId, membershipId, role: input.role, farmGrants: grants });
    return this.runMembershipMutation<MembershipMutationResult>(principal, async (transaction) => {
      const rows = await transaction.$queryRaw<FunctionResultRow<MembershipMutationResult>[]>`
        SELECT * FROM public.update_organization_membership(
          ${organizationId}::uuid,
          ${membershipId}::uuid,
          ${operationId}::uuid,
          ${hash},
          ${input.role}::public.organization_role,
          ${JSON.stringify(grants)}::jsonb
        )
      `;
      return rows[0];
    });
  }

  async removeFor(principal: VerifiedPrincipal, organizationId: string, membershipId: string) {
    return this.runMembershipMutation<MembershipMutationResult>(principal, async (transaction) => {
      const rows = await transaction.$queryRaw<FunctionResultRow<MembershipMutationResult>[]>`
        SELECT * FROM public.remove_organization_membership(
          ${organizationId}::uuid,
          ${membershipId}::uuid
        )
      `;
      return rows[0];
    });
  }

  async transferFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    operationId: string,
    targetMembershipId: string,
    removeFormerOwner: boolean,
  ) {
    const hash = requestHash({ organizationId, targetMembershipId, removeFormerOwner });
    return this.runMembershipMutation<OwnershipTransferResult>(principal, async (transaction) => {
      const rows = await transaction.$queryRaw<FunctionResultRow<OwnershipTransferResult>[]>`
        SELECT * FROM public.transfer_organization_ownership(
          ${organizationId}::uuid,
          ${operationId}::uuid,
          ${hash},
          ${targetMembershipId}::uuid,
          ${removeFormerOwner}
        )
      `;
      return rows[0];
    });
  }

  private async runMembershipMutation<T extends { readonly replayed: boolean }>(
    principal: VerifiedPrincipal,
    operation: (transaction: Prisma.TransactionClient) => Promise<FunctionResultRow<T> | undefined>,
  ) {
    try {
      const row = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return operation(transaction);
      }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });
      if (!row) throw new Error('FARMLY_ORGANIZATION_MEMBERSHIP_RESULT_EMPTY');
      return {
        data: { ...row.result, replayed: row.replayed ?? row.result.replayed },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  private rethrowDatabaseFailure(error: unknown): never {
    const failure = databaseFailure(error);
    if (failure.code === '23505') throw new ConflictException({ code: 'OPERATION_ID_REUSED' });
    if (failure.code === '42501') throw new ForbiddenException({ code: 'PERMISSION_DENIED' });
    if (failure.code === 'P0001' || failure.message.includes('FARMLY_LAST_OWNER_CONFLICT')) {
      throw new ConflictException({ code: 'VERSION_CONFLICT' });
    }
    if (failure.code === 'P0002' || failure.message.includes('FARMLY_MEMBERSHIP_NOT_AVAILABLE')) {
      throw new NotFoundException({ code: 'NOT_FOUND' });
    }
    if (failure.code === '22023' || failure.code === '22P02') {
      throw new BadRequestException({ code: 'MEMBERSHIP_REQUEST_INVALID' });
    }
    throw error;
  }
}
