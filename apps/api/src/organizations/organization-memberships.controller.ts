import { BadRequestException, Body, Controller, Delete, Get, Header, Headers, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { OrganizationMembershipsService } from './organization-memberships.service.js';
import type { FarmGrantRole, OrganizationRole } from './organization-authorization.js';

const UUID = z.string().uuid();
const FarmGrantRoleSchema = z.enum(['manager', 'worker', 'viewer']);
const UpdateMembershipSchema = z.object({
  operationId: UUID,
  payload: z.object({
    role: z.enum(['admin', 'member', 'viewer']),
    farmGrants: z.array(z.object({ farmId: UUID, role: FarmGrantRoleSchema }).strict()).max(100),
  }).strict().superRefine((payload, context) => {
    const farmIds = payload.farmGrants.map((grant) => grant.farmId);
    if (new Set(farmIds).size !== farmIds.length) {
      context.addIssue({ code: 'custom', path: ['farmGrants'], message: 'Farm grants must be unique.' });
    }
    if (payload.role === 'admin' && farmIds.length > 0) {
      context.addIssue({ code: 'custom', path: ['farmGrants'], message: 'Organization admins do not receive farm grants.' });
    }
    if (payload.role === 'viewer' && payload.farmGrants.some((grant) => grant.role !== 'viewer')) {
      context.addIssue({ code: 'custom', path: ['farmGrants'], message: 'Viewer grants must remain read only.' });
    }
  }),
}).strict();
const TransferOwnershipSchema = z.object({
  operationId: UUID,
  payload: z.object({
    targetMembershipId: UUID,
    removeFormerOwner: z.boolean().default(false),
  }).strict(),
}).strict();

function parsePage(limitInput: string | undefined, cursor: string | undefined): { limit: number; cursor: string | null } {
  const limit = limitInput === undefined ? 25 : Number(limitInput);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new BadRequestException('Invalid page size');
  if (cursor !== undefined && !UUID.safeParse(cursor).success) throw new BadRequestException('Invalid cursor');
  return { limit, cursor: cursor ?? null };
}

function requireIdempotencyKey(value: string | string[] | undefined, operationId: string): void {
  if (typeof value !== 'string' || !UUID.safeParse(value).success || value !== operationId) {
    throw new BadRequestException('Idempotency-Key must match operationId');
  }
}

@Controller('v1/organizations')
@UseGuards(VerifiedSessionGuard)
export class OrganizationMembershipsController {
  constructor(private readonly memberships: OrganizationMembershipsService) {}

  @Get(':organizationId/memberships')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  list(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Query('limit') limitInput?: string,
    @Query('cursor') cursor?: string,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    if (!organizationId.success) throw new BadRequestException('Invalid organization ID');
    const page = parsePage(limitInput, cursor);
    return this.memberships.listFor(principal, organizationId.data, page.limit, page.cursor);
  }

  @Patch(':organizationId/memberships/:membershipId')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  update(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Param('membershipId') membershipIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    const membershipId = UUID.safeParse(membershipIdInput);
    if (!organizationId.success || !membershipId.success) throw new BadRequestException('Invalid membership path');
    const parsed = UpdateMembershipSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid membership update request');
    requireIdempotencyKey(idempotencyKey, parsed.data.operationId);
    return this.memberships.updateFor(principal, organizationId.data, membershipId.data, parsed.data.operationId, {
      role: parsed.data.payload.role as Exclude<OrganizationRole, 'owner'>,
      farmGrants: parsed.data.payload.farmGrants.map((grant) => ({
        farmId: grant.farmId,
        role: grant.role as FarmGrantRole,
      })),
    });
  }

  @Delete(':organizationId/memberships/:membershipId')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  remove(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Param('membershipId') membershipIdInput: string,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    const membershipId = UUID.safeParse(membershipIdInput);
    if (!organizationId.success || !membershipId.success) throw new BadRequestException('Invalid membership path');
    return this.memberships.removeFor(principal, organizationId.data, membershipId.data);
  }

  @Post(':organizationId/ownership-transfers')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  transfer(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    if (!organizationId.success) throw new BadRequestException('Invalid organization ID');
    const parsed = TransferOwnershipSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid ownership transfer request');
    requireIdempotencyKey(idempotencyKey, parsed.data.operationId);
    return this.memberships.transferFor(
      principal,
      organizationId.data,
      parsed.data.operationId,
      parsed.data.payload.targetMembershipId,
      parsed.data.payload.removeFormerOwner,
    );
  }
}
