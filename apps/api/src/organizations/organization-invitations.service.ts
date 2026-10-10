import { BadRequestException, ConflictException, ForbiddenException, GoneException, Injectable, NotFoundException } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import type { FarmGrantRole, OrganizationRole } from './organization-authorization.js';

export interface InvitationFarmGrantInput {
  readonly farmId: string;
  readonly role: FarmGrantRole;
}

export interface CreateInvitationInput {
  readonly operationId: string;
  readonly email: string;
  readonly role: Exclude<OrganizationRole, 'owner'>;
  readonly farmGrants: readonly InvitationFarmGrantInput[];
}

interface CreatedInvitationRow {
  readonly invitation_id: string;
  readonly created_at: Date;
  readonly expires_at: Date;
}

interface InvitationIndexRow {
  readonly invitation_id: string;
  readonly organization_role: Exclude<OrganizationRole, 'owner'>;
  readonly invitation_status: 'pending' | 'accepted' | 'expired' | 'revoked';
  readonly created_at: Date;
  readonly expires_at: Date;
  readonly accepted_at: Date | null;
  readonly revoked_at: Date | null;
}

interface AcceptedInvitationRow {
  readonly organization_id: string;
  readonly membership_id: string;
  readonly organization_role: Exclude<OrganizationRole, 'owner'>;
  readonly membership_version: number;
  readonly policy_version: bigint;
  readonly replayed: boolean;
}

interface RevokedInvitationRow {
  readonly invitation_id: string;
  readonly revoked_at: Date;
  readonly policy_version: bigint;
  readonly replayed: boolean;
}

function digest(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function databaseFailure(error: unknown): { readonly code: string | null; readonly message: string } {
  if (!error || typeof error !== 'object') return { code: null, message: '' };
  const value = error as {
    readonly code?: unknown;
    readonly message?: unknown;
    readonly meta?: {
      readonly code?: unknown;
      readonly message?: unknown;
      readonly driverAdapterError?: {
        readonly cause?: { readonly code?: unknown };
      };
    };
  };
  const code = [value.meta?.code, value.meta?.driverAdapterError?.cause?.code, value.code]
    .find((candidate): candidate is string => typeof candidate === 'string') ?? null;
  const message = [
    value.meta?.message,
    value.message,
  ]
    .filter((part): part is string => typeof part === 'string')
    .join(' ');
  return { code, message };
}

@Injectable()
export class OrganizationInvitationsService {
  constructor(private readonly tenantDatabase: TenantDatabaseService) {}

  async listFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    limit: number,
    afterId: string | null,
  ) {
    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<InvitationIndexRow[]>`
          SELECT * FROM public.list_organization_invitations(
            ${organizationId}::uuid, ${limit}, ${afterId}::uuid
          )
        `;
      });

      const hasMore = rows.length > limit;
      const page = rows.slice(0, limit);
      return {
        data: {
          invitations: page.map((row) => ({
            id: row.invitation_id,
            role: row.organization_role,
            status: row.invitation_status,
            createdAt: row.created_at.toISOString(),
            expiresAt: row.expires_at.toISOString(),
            acceptedAt: row.accepted_at?.toISOString() ?? null,
            revokedAt: row.revoked_at?.toISOString() ?? null,
          })),
        },
        page: hasMore ? { nextCursor: page.at(-1)?.invitation_id, hasMore } : { hasMore },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  async createFor(principal: VerifiedPrincipal, organizationId: string, input: CreateInvitationInput) {
    const normalizedEmail = input.email.trim().normalize('NFKC').toLowerCase();
    const acceptanceToken = randomBytes(32).toString('hex');
    const grants = input.farmGrants.map(({ farmId, role }) => ({ farmId, role }));

    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<CreatedInvitationRow[]>`
          SELECT * FROM public.create_organization_invitation(
            ${organizationId}::uuid,
            ${input.operationId}::uuid,
            ${digest(normalizedEmail)},
            ${input.role}::public.organization_role,
            ${digest(acceptanceToken)},
            ${JSON.stringify(grants)}::jsonb
          )
        `;
      });

      const created = rows[0];
      if (!created) throw new Error('FARMLY_INVITATION_CREATION_EMPTY');
      return {
        data: {
          invitation: {
            id: created.invitation_id,
            role: input.role,
            status: 'pending',
            createdAt: created.created_at.toISOString(),
            expiresAt: created.expires_at.toISOString(),
          },
          acceptanceToken,
        },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  async acceptFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    invitationId: string,
    operationId: string,
    acceptanceToken: string,
  ) {
    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<AcceptedInvitationRow[]>`
          SELECT * FROM public.accept_organization_invitation(
            ${organizationId}::uuid,
            ${invitationId}::uuid,
            ${digest(principal.email.trim().normalize('NFKC').toLowerCase())},
            ${digest(acceptanceToken)},
            ${operationId}::uuid
          )
        `;
      });

      const accepted = rows[0];
      if (!accepted) throw new Error('FARMLY_INVITATION_ACCEPTANCE_EMPTY');
      return {
        data: {
          organizationId: accepted.organization_id,
          membership: {
            id: accepted.membership_id,
            role: accepted.organization_role,
            status: 'active',
            version: accepted.membership_version,
          },
          policyVersion: accepted.policy_version.toString(),
          replayed: accepted.replayed,
        },
        meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      this.rethrowDatabaseFailure(error);
    }
  }

  async revokeFor(
    principal: VerifiedPrincipal,
    organizationId: string,
    invitationId: string,
    operationId: string,
  ) {
    try {
      const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        return transaction.$queryRaw<RevokedInvitationRow[]>`
          SELECT * FROM public.revoke_organization_invitation(
            ${organizationId}::uuid,
            ${invitationId}::uuid,
            ${operationId}::uuid
          )
        `;
      });

      const revoked = rows[0];
      if (!revoked) throw new Error('FARMLY_INVITATION_REVOCATION_EMPTY');
      return {
        data: {
          invitation: {
            id: revoked.invitation_id,
            status: 'revoked',
            revokedAt: revoked.revoked_at.toISOString(),
          },
          policyVersion: revoked.policy_version.toString(),
          replayed: revoked.replayed,
        },
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
    if (failure.code === '22023' || failure.code === '22P02') throw new BadRequestException({ code: 'INVITATION_REQUEST_INVALID' });
    if (failure.message.includes('FARMLY_INVITATION_UNAVAILABLE')) {
      throw new NotFoundException({ code: 'INVITATION_NOT_AVAILABLE' });
    }
    if (failure.message.includes('FARMLY_INVITATION_EMAIL_MISMATCH')) {
      throw new ForbiddenException({ code: 'INVITATION_EMAIL_MISMATCH' });
    }
    if (failure.message.includes('FARMLY_INVITATION_EXPIRED')) {
      throw new GoneException({ code: 'INVITATION_EXPIRED' });
    }
    if (failure.message.includes('FARMLY_INVITATION_REVOKED')) {
      throw new GoneException({ code: 'INVITATION_REVOKED' });
    }
    if (failure.message.includes('FARMLY_INVITATION_ALREADY_ACCEPTED')) {
      throw new ConflictException({ code: 'INVITATION_ALREADY_ACCEPTED' });
    }
    if (failure.message.includes('FARMLY_MEMBERSHIP_ALREADY_EXISTS')) {
      throw new ConflictException({ code: 'MEMBERSHIP_ALREADY_EXISTS' });
    }
    throw error;
  }
}
