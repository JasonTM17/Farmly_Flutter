import { BadRequestException, Body, Controller, Get, GoneException, Header, Headers, Param, Post, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { OrganizationsService } from './organizations.service.js';

const CreateOrganizationSchema = z.object({
  operationId: z.string().uuid(),
  name: z.string().trim().min(1).max(120),
}).strict();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parsePage(limitInput: string | undefined, cursor: string | undefined): { limit: number; cursor: string | null } {
  const limit = limitInput === undefined ? 25 : Number(limitInput);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new BadRequestException('Invalid page size');
  if (cursor !== undefined && !UUID.test(cursor)) throw new BadRequestException('Invalid cursor');
  return { limit, cursor: cursor ?? null };
}

function parseFarmDirectoryPage(limitInput: unknown, cursor: unknown): { limit: number | null; cursor: string | null } {
  let limit: number | null = null;
  if (limitInput !== undefined) {
    if (typeof limitInput !== 'string') throw new BadRequestException('Invalid page size');
    if (!/^(?:[1-9][0-9]{0,2})$/.test(limitInput)) throw new BadRequestException('Invalid page size');
    limit = Number(limitInput);
    if (limit > 100) throw new BadRequestException('Invalid page size');
  }
  if (cursor !== undefined && (typeof cursor !== 'string' || cursor.length === 0 || cursor.length > 2048)) {
    throw new GoneException({ code: 'CURSOR_EXPIRED' });
  }
  return { limit, cursor: typeof cursor === 'string' ? cursor : null };
}

@Controller('v1/organizations')
@UseGuards(VerifiedSessionGuard)
export class OrganizationsController {
  constructor(private readonly organizations: OrganizationsService) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  list(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Query('limit') limitInput?: string,
    @Query('cursor') cursor?: string,
  ) {
    const page = parsePage(limitInput, cursor);
    return this.organizations.listFor(principal, page.limit, page.cursor);
  }

  @Get(':orgId/farm-directory')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  farmDirectory(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationId: string,
    @Query('limit') limitInput?: string,
    @Query('cursor') cursor?: string,
  ) {
    if (!UUID.test(organizationId)) throw new BadRequestException('Invalid organization ID');
    const page = parseFarmDirectoryPage(limitInput, cursor);
    return this.organizations.farmDirectoryFor(principal, organizationId, page.limit, page.cursor);
  }

  @Post()
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  create(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    if (typeof idempotencyKey !== 'string' || !UUID.test(idempotencyKey)) {
      throw new BadRequestException('A UUID Idempotency-Key is required');
    }
    const parsed = CreateOrganizationSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid organization request');
    if (parsed.data.operationId !== idempotencyKey) throw new BadRequestException('Idempotency-Key must match operationId');
    return this.organizations.createFor(principal, parsed.data.operationId, parsed.data.name);
  }
}
