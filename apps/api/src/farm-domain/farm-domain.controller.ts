import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import {
  MutationBatch,
  MutationIntent,
  parseUuid,
  UUID_PATTERN,
} from '../common/mutations/mutation-kernel.controller.js';
import { MutationKernelService } from '../common/mutations/mutation-kernel.service.js';
import { DOMAIN_COLLECTIONS, DomainCollection, FarmDomainService } from './farm-domain.service.js';

interface CollectionWriteSpec {
  readonly create?: string;
  readonly update?: string;
  readonly archive?: string;
  readonly hasArchiveRoute?: boolean;
}

const CIVIL_DATE = /^\d{4}-\d{2}-\d{2}$/;

const TaskTransitionRequest = z.object({
  operationId: z.string().regex(UUID_PATTERN),
  expectedVersion: z.number().int().min(1),
  transition: z.enum(['complete', 'skip', 'reopen', 'cancel']),
  reason: z.string().max(500).optional(),
}).strict();

// Contract DomainCommandRequest: {operationId, payload} — the bootstrap
// snapshot id is the client-chosen operationId (idempotent on retry).
const DomainCommandRequestSchema = z.object({
  operationId: z.string().regex(UUID_PATTERN),
  payload: z.record(z.string(), z.unknown()),
}).strict();

const RESOURCE_TYPES: Readonly<Record<string, CollectionWriteSpec>> = {
  zones: { create: 'zone.create', update: 'zone.update', archive: 'zone.archive', hasArchiveRoute: true },
  'crop-species': { create: 'cropSpecies.create', update: 'cropSpecies.update', archive: 'cropSpecies.archive', hasArchiveRoute: true },
  plantings: { create: 'planting.create', update: 'planting.update', archive: 'planting.archive', hasArchiveRoute: true },
  herds: { create: 'herd.create', update: 'herd.update', archive: 'herd.archive', hasArchiveRoute: true },
  animals: { create: 'animal.create', update: 'animal.update', archive: 'animal.archive', hasArchiveRoute: true },
  // waterTank.archive is kernel-registry-only per the approved P05 decision:
  // it is admitted through POST F/sync/mutations, not a dedicated archive route.
  'water-tanks': { create: 'waterTank.create', update: 'waterTank.update', archive: 'waterTank.archive', hasArchiveRoute: false },
  // P06 append-only facts: no update/archive; also readable via sync feed.
  'planting-events': { create: 'plantingEvent.create' },
  'livestock-movements': { create: 'livestockMovement.create' },
  observations: { create: 'animalObservation.create' },
  'production-records': { create: 'productionRecord.create' },
  // Template archive is taskTemplate.update {status:'archived'} per spec04 5.2.
  'task-templates': { create: 'taskTemplate.create', update: 'taskTemplate.update' },
  harvests: { create: 'harvest.create' },
  'moisture-readings': { create: 'moistureReading.create' },
  'water-readings': { create: 'waterReading.create' },
  'water-usages': { create: 'waterUsage.create' },
};

@Controller('v1/organizations/:orgId/farms/:farmId')
@UseGuards(VerifiedSessionGuard)
export class FarmDomainController {
  constructor(
    private readonly mutations: MutationKernelService,
    private readonly domain: FarmDomainService,
  ) {}

  @Patch()
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  updateFarm(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const farmId = parseUuid(farmIdInput, 'Invalid farm ID');
    const intent = parseScopedIntent(body, 'farm.update', farmId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Post('archive')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  archiveFarm(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const farmId = parseUuid(farmIdInput, 'Invalid farm ID');
    const intent = parseScopedIntent(body, 'farm.archive', farmId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Post('sync/mutations')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  submitFarmMutations(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const farmId = parseUuid(farmIdInput, 'Invalid farm ID');
    const parsed = MutationBatch.safeParse(body);
    if (!parsed.success || parsed.data.operations.some((intent) => intent.continuityEpoch !== parsed.data.continuityEpoch)) {
      throw new BadRequestException('Invalid mutation batch');
    }
    const operationIds = parsed.data.operations.map((intent) => intent.operationId);
    if (new Set(operationIds).size !== operationIds.length) {
      throw new BadRequestException('A batch cannot repeat an operation ID');
    }
    return this.mutations.applyBatch(principal, organizationId, parsed.data.operations, farmId);
  }

  // ---- P08: bootstrap snapshot + change feed -------------------------------

  @Post('sync/bootstrap')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  createBootstrapSnapshot(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const parsed = DomainCommandRequestSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid bootstrap request');
    return this.domain.createBootstrap(principal, organizationId, farmId, parsed.data.operationId);
  }

  @Get('sync/bootstrap/:snapshotId')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getBootstrapChunk(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('snapshotId') snapshotIdInput: string,
    @Query('pageCursor') pageCursor: string | undefined,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const snapshotId = parseUuid(snapshotIdInput, 'Invalid snapshot ID');
    return this.domain.getBootstrapPage(principal, organizationId, farmId, snapshotId, pageCursor);
  }

  @Get('sync/changes')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getChangeSets(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Query('cursor') cursor: string | undefined,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    if (typeof cursor !== 'string' || cursor.length === 0) {
      throw new BadRequestException({ code: 'CURSOR_REQUIRED' });
    }
    return this.domain.getChanges(principal, organizationId, farmId, cursor);
  }

  // ---- P06: task occurrence transitions -------------------------------------

  @Post('task-occurrences/:occurrenceId/transitions')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  transitionTaskOccurrence(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('occurrenceId') occurrenceIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    return this.transitionOccurrence(
      principal, organizationIdInput, farmIdInput, occurrenceIdInput,
      'taskOccurrence.transition', idempotencyKey, body,
    );
  }

  @Post('irrigation-tasks/:taskId/transitions')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  transitionIrrigationTask(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('taskId') taskIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    return this.transitionOccurrence(
      principal, organizationIdInput, farmIdInput, taskIdInput,
      'irrigationTask.transition', idempotencyKey, body,
    );
  }

  // ---- P06: harvest lifecycle -----------------------------------------------

  @Post('harvests/:harvestId/correction-proposals')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  proposeHarvestCorrection(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('harvestId') harvestIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const harvestId = parseUuid(harvestIdInput, 'Invalid harvest ID');
    const intent = parseScopedIntent(body, 'harvest.correction.propose', harvestId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Post('harvests/:harvestId/corrections')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  applyHarvestCorrection(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('harvestId') harvestIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const harvestId = parseUuid(harvestIdInput, 'Invalid harvest ID');
    const intent = parseScopedIntent(body, 'harvest.correction.apply', harvestId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Post('harvests/:harvestId/void')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  voidHarvest(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('harvestId') harvestIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const harvestId = parseUuid(harvestIdInput, 'Invalid harvest ID');
    const intent = parseScopedIntent(body, 'harvest.void', harvestId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  // ---- fixed read routes (must precede :collection so Nest binds the static
  // segment before the parameter capture) -------------------------------------

  @Get('summary')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getSummary(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    return this.domain.summary(principal, organizationId, farmId);
  }

  @Get('analytics')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getAnalytics(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Query('days') daysInput: string | undefined,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    let days = 30;
    if (daysInput !== undefined) {
      if (!/^[0-9]{1,3}$/.test(daysInput)) {
        throw new BadRequestException('Invalid days parameter');
      }
      days = Number.parseInt(daysInput, 10);
      if (days < 1 || days > 92) {
        throw new BadRequestException('Invalid days parameter');
      }
    }
    return this.domain.analytics(principal, organizationId, farmId, days);
  }

  @Get('weather')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getWeather(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    return this.domain.weather(principal, organizationId, farmId);
  }

  // ---- generic collection routes --------------------------------------------

  @Post(':collection')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  createResource(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('collection') collectionInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const spec = RESOURCE_TYPES[collectionInput];
    if (!spec?.create) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const intent = parseScopedIntent(body, spec.create, null, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Get(':collection')
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  listResources(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('collection') collectionInput: string,
    @Query('from') from: string | undefined,
    @Query('to') to: string | undefined,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    if (!(collectionInput in DOMAIN_COLLECTIONS)) {
      throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    }
    let range: { from?: string; to?: string } | undefined;
    if (collectionInput === 'task-occurrences') {
      if ((from !== undefined && !CIVIL_DATE.test(from)) || (to !== undefined && !CIVIL_DATE.test(to))) {
        throw new BadRequestException('Invalid occurrence date range');
      }
      range = { from, to };
    }
    return this.domain.list(principal, organizationId, farmId, collectionInput as DomainCollection, range);
  }

  @Patch(':collection/:resourceId')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  updateResource(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('collection') collectionInput: string,
    @Param('resourceId') resourceIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const spec = RESOURCE_TYPES[collectionInput];
    if (!spec?.update) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const resourceId = parseUuid(resourceIdInput, 'Invalid resource ID');
    const intent = parseScopedIntent(body, spec.update, resourceId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  @Post(':collection/:resourceId/archive')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  archiveResource(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('collection') collectionInput: string,
    @Param('resourceId') resourceIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const spec = RESOURCE_TYPES[collectionInput];
    if (!spec?.archive || !spec.hasArchiveRoute) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const resourceId = parseUuid(resourceIdInput, 'Invalid resource ID');
    const intent = parseScopedIntent(body, spec.archive, resourceId, idempotencyKey);
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  private async transitionOccurrence(
    principal: VerifiedPrincipal,
    organizationIdInput: string,
    farmIdInput: string,
    occurrenceIdInput: string,
    type: 'taskOccurrence.transition' | 'irrigationTask.transition',
    idempotencyKey: string | string[] | undefined,
    body: unknown,
  ) {
    const { organizationId, farmId } = this.parseIds(organizationIdInput, farmIdInput);
    const occurrenceId = parseUuid(occurrenceIdInput, 'Invalid occurrence ID');
    const parsed = TaskTransitionRequest.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid transition request');
    if (typeof idempotencyKey !== 'string' || !UUID_PATTERN.test(idempotencyKey)
      || parsed.data.operationId !== idempotencyKey.toLowerCase()) {
      throw new BadRequestException('Idempotency-Key must match operationId');
    }
    // The deterministic id only commits the payload identity when the kernel
    // recomputes it — the server composes the payload from the stored row so a
    // caller cannot smuggle mismatched (templateId,date,slot) into a known id.
    const occurrence = await this.domain.readOccurrenceForTransition(
      principal, organizationId, farmId, occurrenceId,
    );
    if (!occurrence) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const intent = {
      schemaVersion: 'farm-mutation.v1' as const,
      continuityEpoch: occurrence.continuityEpoch,
      operationId: parsed.data.operationId,
      type,
      resourceId: occurrenceId,
      baseVersion: parsed.data.expectedVersion,
      dependsOn: [],
      payload: {
        templateId: occurrence.templateId,
        occurrenceDate: occurrence.occurrenceDate,
        slot: occurrence.slot,
        transition: parsed.data.transition,
        ...(parsed.data.reason !== undefined ? { reason: parsed.data.reason } : {}),
      },
    };
    return this.mutations.applyOne(principal, organizationId, intent, farmId);
  }

  private parseIds(organizationIdInput: string, farmIdInput: string) {
    return {
      organizationId: parseUuid(organizationIdInput, 'Invalid organization ID'),
      farmId: parseUuid(farmIdInput, 'Invalid farm ID'),
    };
  }
}

function parseScopedIntent(
  body: unknown,
  expectedType: string,
  expectedResourceId: string | null,
  idempotencyKey: string | string[] | undefined,
) {
  const parsed = MutationIntent.safeParse(body);
  if (!parsed.success) throw new BadRequestException('Invalid mutation request');
  if (parsed.data.type !== expectedType) {
    throw new BadRequestException('Mutation type does not match this route');
  }
  if (expectedResourceId !== null && parsed.data.resourceId !== expectedResourceId) {
    throw new BadRequestException('Mutation resourceId does not match this route');
  }
  if (typeof idempotencyKey !== 'string' || !UUID_PATTERN.test(idempotencyKey)
    || parsed.data.operationId !== idempotencyKey.toLowerCase()) {
    throw new BadRequestException('Idempotency-Key must match operationId');
  }
  return parsed.data;
}
