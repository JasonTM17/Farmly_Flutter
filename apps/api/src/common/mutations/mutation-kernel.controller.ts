import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../../auth/verified-session.guard.js';
import { MutationKernelService } from './mutation-kernel.service.js';

export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_POSTGRES_BIGINT = 9_223_372_036_854_775_807n;

const PositiveBigintString = z.string().regex(/^[1-9][0-9]{0,18}$/).refine((value) => {
  if (!/^[1-9][0-9]{0,18}$/.test(value)) return false;
  return BigInt(value) <= MAX_POSTGRES_BIGINT;
});
const Uuid = z.string().regex(UUID_PATTERN).transform((value) => value.toLowerCase());
export const MutationIntent = z.object({
  schemaVersion: z.literal('farm-mutation.v1'),
  continuityEpoch: PositiveBigintString,
  operationId: Uuid,
  type: z.string().regex(/^[a-z][A-Za-z0-9_.]{0,79}$/),
  resourceId: Uuid,
  baseVersion: z.number().int().positive().nullable().optional(),
  dependsOn: z.array(Uuid).max(50),
  payload: z.record(z.string(), z.unknown()),
}).strict();
export const MutationBatch = z.object({
  schemaVersion: z.literal('farm-mutation-batch.v1'),
  continuityEpoch: PositiveBigintString,
  operations: z.array(MutationIntent).min(1).max(50),
}).strict();

@Controller('v1')
@UseGuards(VerifiedSessionGuard)
export class MutationKernelController {
  constructor(private readonly mutations: MutationKernelService) {}

  @Post('organizations/:orgId/farms')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  createFarm(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const parsed = MutationIntent.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid mutation request');
    if (typeof idempotencyKey !== 'string' || !UUID_PATTERN.test(idempotencyKey)
      || parsed.data.operationId !== idempotencyKey.toLowerCase()) {
      throw new BadRequestException('Idempotency-Key must match operationId');
    }
    return this.mutations.applyOne(principal, organizationId, parsed.data);
  }

  @Post('organizations/:orgId/sync/mutations')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  submitOrganizationMutations(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const parsed = MutationBatch.safeParse(body);
    if (!parsed.success || parsed.data.operations.some((intent) => intent.continuityEpoch !== parsed.data.continuityEpoch)) {
      throw new BadRequestException('Invalid mutation batch');
    }
    const operationIds = parsed.data.operations.map((intent) => intent.operationId);
    if (new Set(operationIds).size !== operationIds.length) {
      throw new BadRequestException('A batch cannot repeat an operation ID');
    }
    return this.mutations.applyBatch(principal, organizationId, parsed.data.operations);
  }

  @Get('me/operation-status')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getOwnOperationStatus(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Query('operationIds') operationIdsInput: unknown,
  ) {
    if (typeof operationIdsInput !== 'string') throw new BadRequestException('Invalid operation IDs');
    const values = operationIdsInput.split(',');
    if (values.length < 1 || values.length > 50 || values.some((value) => !UUID_PATTERN.test(value))) {
      throw new BadRequestException('Invalid operation IDs');
    }
    const operationIds = values.map((value) => value.toLowerCase());
    if (new Set(operationIds).size !== operationIds.length) {
      throw new BadRequestException('Operation IDs must be unique');
    }
    return this.mutations.getOwnOperationStatus(principal, operationIds);
  }
}

export function parseUuid(value: string, message: string): string {
  if (!UUID_PATTERN.test(value)) throw new BadRequestException(message);
  return value.toLowerCase();
}
