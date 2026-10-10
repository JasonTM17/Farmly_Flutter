import { BadRequestException, Body, Controller, Get, Header, Headers, Param, Post, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { OrganizationInvitationsService } from './organization-invitations.service.js';
import type { FarmGrantRole, OrganizationRole } from './organization-authorization.js';

const UUID = z.string().uuid();
const OrganizationRoleSchema = z.enum(['admin', 'member', 'viewer']);
const FarmGrantRoleSchema = z.enum(['manager', 'worker', 'viewer']);
const CreateInvitationSchema = z.object({
  operationId: UUID,
  payload: z.object({
    email: z.string().trim().email().max(320),
    role: OrganizationRoleSchema,
    farmGrants: z.array(z.object({ farmId: UUID, role: FarmGrantRoleSchema }).strict()).max(100).default([]),
  }).strict(),
}).strict().superRefine((request, context) => {
  const farmIds = request.payload.farmGrants.map((grant) => grant.farmId);
  if (new Set(farmIds).size !== farmIds.length) {
    context.addIssue({ code: 'custom', path: ['payload', 'farmGrants'], message: 'Farm grants must be unique.' });
  }
  if (request.payload.role === 'admin' && farmIds.length > 0) {
    context.addIssue({ code: 'custom', path: ['payload', 'farmGrants'], message: 'Organization admins do not receive farm grants.' });
  }
  if (request.payload.role === 'viewer' && request.payload.farmGrants.some((grant) => grant.role !== 'viewer')) {
    context.addIssue({ code: 'custom', path: ['payload', 'farmGrants'], message: 'Viewer grants must remain read only.' });
  }
});
const AcceptInvitationSchema = z.object({
  operationId: UUID,
  payload: z.object({ token: z.string().regex(/^[a-f0-9]{64}$/) }).strict(),
}).strict();
const RevokeInvitationSchema = z.object({ operationId: UUID }).strict();

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
export class OrganizationInvitationsController {
  constructor(private readonly invitations: OrganizationInvitationsService) {}

  @Get(':organizationId/invitations')
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
    return this.invitations.listFor(principal, organizationId.data, page.limit, page.cursor);
  }

  @Post(':organizationId/invitations')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  create(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    if (!organizationId.success) throw new BadRequestException('Invalid organization ID');
    const parsed = CreateInvitationSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid invitation request');
    requireIdempotencyKey(idempotencyKey, parsed.data.operationId);
    return this.invitations.createFor(principal, organizationId.data, {
      operationId: parsed.data.operationId,
      email: parsed.data.payload.email,
      role: parsed.data.payload.role as Exclude<OrganizationRole, 'owner'>,
      farmGrants: parsed.data.payload.farmGrants.map((grant) => ({
        farmId: grant.farmId,
        role: grant.role as FarmGrantRole,
      })),
    });
  }

  @Post(':organizationId/invitations/:invitationId/revoke')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  revoke(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Param('invitationId') invitationIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    const invitationId = UUID.safeParse(invitationIdInput);
    if (!organizationId.success || !invitationId.success) throw new BadRequestException('Invalid invitation path');
    const parsed = RevokeInvitationSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid invitation revocation request');
    requireIdempotencyKey(idempotencyKey, parsed.data.operationId);
    return this.invitations.revokeFor(
      principal,
      organizationId.data,
      invitationId.data,
      parsed.data.operationId,
    );
  }

  @Post(':organizationId/invitations/:invitationId/accept')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  accept(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('organizationId') organizationIdInput: string,
    @Param('invitationId') invitationIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = UUID.safeParse(organizationIdInput);
    const invitationId = UUID.safeParse(invitationIdInput);
    if (!organizationId.success || !invitationId.success) throw new BadRequestException('Invalid invitation path');
    const parsed = AcceptInvitationSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid invitation acceptance request');
    requireIdempotencyKey(idempotencyKey, parsed.data.operationId);
    return this.invitations.acceptFor(
      principal,
      organizationId.data,
      invitationId.data,
      parsed.data.operationId,
      parsed.data.payload.token,
    );
  }
}
