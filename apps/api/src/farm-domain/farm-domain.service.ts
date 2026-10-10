import {
  BadRequestException,
  ConflictException,
  GoneException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { Prisma } from '@prisma/client';
import type { VerifiedPrincipal } from '../auth/verified-session.guard.js';
import type { ApiEnvironment } from '../config/environment.js';
import { actorPseudonym } from '../common/mutations/mutation-kernel.service.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';

export type DomainCollection =
  | 'zones'
  | 'crop-species'
  | 'plantings'
  | 'herds'
  | 'animals'
  | 'water-tanks'
  | 'task-templates'
  | 'task-occurrences'
  | 'harvests'
  | 'moisture-readings';

interface CollectionSpec {
  readonly pluralKey: string;
  readonly table: string;
}

export const DOMAIN_COLLECTIONS: Readonly<Record<DomainCollection, CollectionSpec>> = {
  zones: { pluralKey: 'zones', table: 'zones' },
  'crop-species': { pluralKey: 'cropSpecies', table: 'crop_species' },
  plantings: { pluralKey: 'plantings', table: 'plantings' },
  herds: { pluralKey: 'herds', table: 'herds' },
  animals: { pluralKey: 'animals', table: 'animals' },
  'water-tanks': { pluralKey: 'waterTanks', table: 'water_tanks' },
  'task-templates': { pluralKey: 'taskTemplates', table: 'task_templates' },
  'task-occurrences': { pluralKey: 'taskOccurrences', table: 'task_occurrences' },
  harvests: { pluralKey: 'harvests', table: 'harvest_heads' },
  'moisture-readings': { pluralKey: 'moistureReadings', table: 'moisture_readings' },
};

interface AccessRow {
  readonly can_read: boolean;
}

export interface OccurrenceTransitionContext {
  readonly templateId: string;
  readonly occurrenceDate: string;
  readonly slot: string;
  readonly version: number;
  readonly continuityEpoch: string;
}

function textOrNull(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function isoDate(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function isoInstant(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

// ---- P08 sync surface -----------------------------------------------------
// Product/operator-ratified limits (execution-ledger "P08 bootstrap cap
// ratification", 2026-10-11); measured fixture is 7,543 rows / ~1.94 MiB.
export const BOOTSTRAP_MAX_ROWS = 25_000;
export const BOOTSTRAP_MAX_BYTES = 8_388_608; // 8 MiB
export const BOOTSTRAP_TTL_SECONDS = 900;
const BOOTSTRAP_PAGE_ROWS = 100;
const CHANGES_PAGE_SIZE = 100;
const CHANGES_CURSOR_KIND = 'farm-changes.v1';
const CHANGES_CURSOR_MAX_LENGTH = 4096;

interface FarmChangesCursor {
  readonly kind: string;
  readonly organizationId: string;
  readonly farmId: string;
  readonly actorBinding: string;
  readonly scopePolicyVersion: string;
  readonly continuityEpoch: string;
  readonly revision: string;
  readonly pageSize: number;
}

function signChangesCursor(cursor: FarmChangesCursor, key: string): string {
  const payload = Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
  const signature = createHmac('sha256', key).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

function changesActorBinding(actorId: string, key: string): string {
  return createHmac('sha256', key).update(`farm-changes-actor:${actorId}`).digest('base64url');
}

function readChangesCursor(token: string, key: string): FarmChangesCursor | null {
  if (token.length < 1 || token.length > CHANGES_CURSOR_MAX_LENGTH) return null;
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
    if (fields !== 'actorBinding,continuityEpoch,farmId,kind,organizationId,pageSize,revision,scopePolicyVersion') return null;
    const bigintString = (v: unknown) =>
      typeof v === 'string' && /^[0-9]{1,19}$/.test(v) && BigInt(v) <= 9_223_372_036_854_775_807n;
    if (cursor.kind !== CHANGES_CURSOR_KIND
      || typeof cursor.organizationId !== 'string'
      || typeof cursor.farmId !== 'string'
      || typeof cursor.actorBinding !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(cursor.actorBinding)
      || !bigintString(cursor.scopePolicyVersion)
      || !bigintString(cursor.continuityEpoch) || BigInt(cursor.continuityEpoch as string) < 1n
      || !bigintString(cursor.revision)
      || !Number.isInteger(cursor.pageSize)
      || (cursor.pageSize as number) < 1 || (cursor.pageSize as number) > CHANGES_PAGE_SIZE) {
      return null;
    }
    return cursor as unknown as FarmChangesCursor;
  } catch {
    return null;
  }
}

@Injectable()
export class FarmDomainService {
  private readonly environment: ApiEnvironment | undefined;

  constructor(
    private readonly tenantDatabase: TenantDatabaseService,
    config: ConfigService,
  ) {
    this.environment = config.get<ApiEnvironment>('farmlyEnvironment');
  }

  // The weather kill switch is read per request so disabling takes effect
  // without a restart (spec03: kill switch isolates external failures).
  private get weatherEnabled(): boolean {
    return this.environment?.weatherEnabled ?? false;
  }

  private get weatherFreshTtlSeconds(): number {
    return this.environment?.weatherFreshTtlSeconds ?? 3600;
  }

  async list(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    collection: DomainCollection,
    range?: { from?: string; to?: string },
  ) {
    const spec = DOMAIN_COLLECTIONS[collection];
    const items = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;
      switch (collection) {
        case 'zones':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT zone.id::TEXT AS "id", zone.version, zone.type, zone.name, zone.geometry,
                   zone.area_m2::TEXT AS "areaM2", zone.status
              FROM public.zones AS zone
             WHERE zone.organization_id = ${organizationId}::uuid AND zone.farm_id = ${farmId}::uuid
             ORDER BY zone.id
          `;
        case 'crop-species':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT species.id::TEXT AS "id", species.version, species.name,
                   species.harvest_unit AS "harvestUnit", species.status
              FROM public.crop_species AS species
             WHERE species.organization_id = ${organizationId}::uuid AND species.farm_id = ${farmId}::uuid
             ORDER BY species.id
          `;
        case 'plantings':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT planting.id::TEXT AS "id", planting.version,
                   planting.crop_species_id::TEXT AS "cropSpeciesId",
                   planting.plot_id::TEXT AS "plotId", planting.status,
                   planting.sowing_date::TEXT AS "sowingDate",
                   planting.expected_harvest_date::TEXT AS "expectedHarvestDate",
                   planting.area_m2::TEXT AS "areaM2"
              FROM public.plantings AS planting
             WHERE planting.organization_id = ${organizationId}::uuid AND planting.farm_id = ${farmId}::uuid
             ORDER BY planting.id
          `;
        case 'herds':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT herd.id::TEXT AS "id", herd.version, herd.mode, herd.species, herd.status,
                   CASE WHEN herd.mode = 'tracked' THEN (
                       SELECT count(*)::INTEGER
                         FROM public.animals AS animal
                        WHERE animal.organization_id = herd.organization_id
                          AND animal.farm_id = herd.farm_id
                          AND animal.herd_id = herd.id
                          AND animal.status = 'alive' AND NOT animal.archived
                   ) ELSE COALESCE((
                       SELECT sum(movement.delta)
                         FROM public.livestock_movements AS movement
                        WHERE movement.organization_id = herd.organization_id
                          AND movement.farm_id = herd.farm_id
                          AND movement.herd_id = herd.id
                   ), 0)::INTEGER END AS "headcount"
              FROM public.herds AS herd
             WHERE herd.organization_id = ${organizationId}::uuid AND herd.farm_id = ${farmId}::uuid
             ORDER BY herd.id
          `;
        case 'animals':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT animal.id::TEXT AS "id", animal.version, animal.herd_id::TEXT AS "herdId",
                   animal.tag, animal.name, animal.birth_date::TEXT AS "birthDate",
                   animal.status, animal.archived
              FROM public.animals AS animal
             WHERE animal.organization_id = ${organizationId}::uuid AND animal.farm_id = ${farmId}::uuid
             ORDER BY animal.id
          `;
        case 'water-tanks':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT tank.id::TEXT AS "id", tank.version, tank.name, tank.zone_id::TEXT AS "zoneId",
                   tank.capacity_litres::TEXT AS "capacityLitres",
                   tank.stored_litres::TEXT AS "storedLitres", tank.status
              FROM public.water_tanks AS tank
             WHERE tank.organization_id = ${organizationId}::uuid AND tank.farm_id = ${farmId}::uuid
             ORDER BY tank.id
          `;
        case 'task-templates':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT template.id::TEXT AS "id", template.version, template.title, template.kind,
                   template.zone_id::TEXT AS "zoneId", template.recurrence,
                   template.assignee_membership_id::TEXT AS "assigneeMembershipId",
                   template.starts_on::TEXT AS "startsOn", template.ends_on::TEXT AS "endsOn",
                   template.status
              FROM public.task_templates AS template
             WHERE template.organization_id = ${organizationId}::uuid AND template.farm_id = ${farmId}::uuid
             ORDER BY template.id
          `;
        case 'task-occurrences':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT occurrence.id::TEXT AS "id", occurrence.version,
                   occurrence.template_id::TEXT AS "templateId",
                   occurrence.occurrence_date::TEXT AS "occurrenceDate",
                   occurrence.slot, occurrence.status,
                   occurrence.due_at AS "dueAt", occurrence.completed_by AS "completedBy"
              FROM public.task_occurrences AS occurrence
             WHERE occurrence.organization_id = ${organizationId}::uuid
               AND occurrence.farm_id = ${farmId}::uuid
               AND (${range?.from ?? null}::date IS NULL OR occurrence.occurrence_date >= ${range?.from ?? null}::date)
               AND (${range?.to ?? null}::date IS NULL OR occurrence.occurrence_date <= ${range?.to ?? null}::date)
             ORDER BY occurrence.occurrence_date, occurrence.id
          `;
        case 'harvests':
          // Effective-head join: confirmed totals exclude voided heads and
          // superseded records by construction (spec04 section 5.2).
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT head.harvest_id::TEXT AS "id", head.version,
                   head.planting_id::TEXT AS "plantingId",
                   record.quantity_kg::TEXT AS "quantityKg",
                   record.harvest_date::TEXT AS "harvestDate",
                   head.status,
                   (SELECT count(*)::INTEGER
                      FROM public.correction_proposals AS proposal
                     WHERE proposal.organization_id = head.organization_id
                       AND proposal.farm_id = head.farm_id
                       AND proposal.harvest_id = head.harvest_id
                       AND proposal.status = 'pending') AS "pendingProposals"
              FROM public.harvest_heads AS head
              JOIN public.harvest_records AS record
                ON record.organization_id = head.organization_id
               AND record.farm_id = head.farm_id
               AND record.id = head.effective_record_id
             WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
             ORDER BY head.harvest_id
          `;
        case 'moisture-readings':
          return transaction.$queryRaw<Record<string, unknown>[]>`
            SELECT reading.id::TEXT AS "id", 1 AS version,
                   reading.zone_id::TEXT AS "zoneId",
                   reading.value::TEXT AS "value", reading.method, reading.source,
                   reading.measured_at AS "measuredAt"
              FROM public.moisture_readings AS reading
             WHERE reading.organization_id = ${organizationId}::uuid AND reading.farm_id = ${farmId}::uuid
             ORDER BY reading.measured_at DESC, reading.id
          `;
      }
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (items === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    return {
      data: {
        [spec.pluralKey]: items.map((row) => stripNulls({
          ...row,
          areaM2: textOrNull(row.areaM2) ?? undefined,
          capacityLitres: textOrNull(row.capacityLitres) ?? undefined,
          storedLitres: textOrNull(row.storedLitres) ?? undefined,
          sowingDate: isoDate(row.sowingDate) ?? undefined,
          expectedHarvestDate: isoDate(row.expectedHarvestDate) ?? undefined,
          birthDate: isoDate(row.birthDate) ?? undefined,
          startsOn: isoDate(row.startsOn) ?? undefined,
          endsOn: isoDate(row.endsOn) ?? undefined,
          occurrenceDate: isoDate(row.occurrenceDate) ?? undefined,
          harvestDate: isoDate(row.harvestDate) ?? undefined,
          dueAt: isoInstant(row.dueAt) ?? undefined,
          measuredAt: isoInstant(row.measuredAt) ?? undefined,
          completedBy: textOrNull(row.completedBy) ?? undefined,
        })),
      },
      meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
    };
  }

  /**
   * Resolve the stored occurrence row for a transition route so the kernel's
   * deterministic-id check binds a payload the client could not tamper with.
   * Also returns the org's current continuity epoch for the composed intent.
   */
  async readOccurrenceForTransition(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    occurrenceId: string,
  ): Promise<OccurrenceTransitionContext | null> {
    const rows = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;
      return transaction.$queryRaw<{
        template_id: string;
        occurrence_date: string;
        slot: string;
        version: number;
        continuity_epoch: string;
      }[]>`
        SELECT occurrence.template_id::TEXT, occurrence.occurrence_date::TEXT,
               occurrence.slot, occurrence.version,
               organization.continuity_epoch::TEXT AS continuity_epoch
          FROM public.task_occurrences AS occurrence
          JOIN public.organizations AS organization
            ON organization.id = occurrence.organization_id
         WHERE occurrence.organization_id = ${organizationId}::uuid
           AND occurrence.farm_id = ${farmId}::uuid
           AND occurrence.id = ${occurrenceId}::uuid
      `;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    const row = rows?.[0];
    if (!row) return null;
    return {
      templateId: row.template_id,
      occurrenceDate: String(row.occurrence_date).slice(0, 10),
      slot: row.slot,
      version: row.version,
      continuityEpoch: row.continuity_epoch,
    };
  }

  /**
   * P07 farm summary — real scoped aggregates only (R-12/R-13). Every section
   * carries its own coverage/asOf so a missing or partial source degrades that
   * metric, never silently the whole dashboard.
   * operations-health.v1: eligible = occurrences in done|skipped (cancelled and
   * still-open excluded); ratio = done/eligible; fewer than 5 eligible →
   * 'unknown' (D-14, mirrors the mobile demo formula).
   */
  async summary(principal: VerifiedPrincipal, organizationId: string, farmId: string) {
    const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;

      const farmRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT farm.id::TEXT AS "farmId", farm.name, farm.timezone, farm.status,
               farm.version, farm.location
          FROM public.farms AS farm
         WHERE farm.organization_id = ${organizationId}::uuid AND farm.id = ${farmId}::uuid
      `;
      const farm = farmRows[0];
      if (!farm) return null;
      const timezone = String(farm.timezone);

      const zoneRows = await transaction.$queryRaw<{ type: string; count: number }[]>`
        SELECT zone.type, count(*)::INTEGER AS count
          FROM public.zones AS zone
         WHERE zone.organization_id = ${organizationId}::uuid AND zone.farm_id = ${farmId}::uuid
           AND zone.status = 'active'
         GROUP BY zone.type
      `;

      const cropRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT
          (SELECT count(*)::INTEGER FROM public.crop_species AS species
            WHERE species.organization_id = ${organizationId}::uuid
              AND species.farm_id = ${farmId}::uuid AND species.status = 'active') AS "species",
          (SELECT count(*)::INTEGER FROM public.plantings AS planting
            WHERE planting.organization_id = ${organizationId}::uuid
              AND planting.farm_id = ${farmId}::uuid AND planting.status <> 'archived') AS "plantings",
          (SELECT count(*)::INTEGER FROM public.plantings AS planting
            WHERE planting.organization_id = ${organizationId}::uuid
              AND planting.farm_id = ${farmId}::uuid AND planting.status = 'active') AS "plantingsActive"
      `;

      const livestockRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT count(*)::INTEGER AS "herds",
               COALESCE(sum(CASE WHEN herd.mode = 'tracked' THEN (
                   SELECT count(*) FROM public.animals AS animal
                    WHERE animal.organization_id = herd.organization_id
                      AND animal.farm_id = herd.farm_id AND animal.herd_id = herd.id
                      AND animal.status = 'alive' AND NOT animal.archived
                 ) ELSE COALESCE((
                   SELECT sum(movement.delta) FROM public.livestock_movements AS movement
                    WHERE movement.organization_id = herd.organization_id
                      AND movement.farm_id = herd.farm_id AND movement.herd_id = herd.id
                 ), 0) END), 0)::INTEGER AS "headcount",
               COALESCE(sum(CASE WHEN herd.mode = 'tracked' THEN (
                   SELECT count(*) FROM public.animals AS animal
                    WHERE animal.organization_id = herd.organization_id
                      AND animal.farm_id = herd.farm_id AND animal.herd_id = herd.id
                      AND animal.status = 'alive' AND NOT animal.archived
                 ) ELSE 0 END), 0)::INTEGER AS "trackedAnimals"
          FROM public.herds AS herd
         WHERE herd.organization_id = ${organizationId}::uuid AND herd.farm_id = ${farmId}::uuid
           AND herd.status = 'active'
      `;

      const taskRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT
          count(*) FILTER (WHERE occurrence.occurrence_date = (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
            AND occurrence.status IN ('open', 'in_progress'))::INTEGER AS "openToday",
          count(*) FILTER (WHERE occurrence.occurrence_date = (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
            AND occurrence.status = 'done')::INTEGER AS "doneToday",
          count(*) FILTER (WHERE occurrence.occurrence_date = (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
            AND occurrence.status = 'skipped')::INTEGER AS "skippedToday",
          count(*) FILTER (WHERE occurrence.status = 'open' AND occurrence.due_at IS NOT NULL
            AND occurrence.due_at < CURRENT_TIMESTAMP)::INTEGER AS "overdue",
          count(*) FILTER (WHERE occurrence.status IN ('done', 'skipped'))::INTEGER AS "eligible",
          count(*) FILTER (WHERE occurrence.status = 'done')::INTEGER AS "done"
        FROM public.task_occurrences AS occurrence
        WHERE occurrence.organization_id = ${organizationId}::uuid AND occurrence.farm_id = ${farmId}::uuid
      `;

      const harvestRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT count(*)::INTEGER AS "heads",
               count(*) FILTER (WHERE head.status = 'voided')::INTEGER AS "voided",
               COALESCE(sum(record.quantity_kg) FILTER (WHERE head.status = 'active'), 0)::TEXT AS "totalKg"
          FROM public.harvest_heads AS head
          JOIN public.harvest_records AS record
            ON record.organization_id = head.organization_id
           AND record.farm_id = head.farm_id
           AND record.id = head.effective_record_id
         WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
      `;

      const waterRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT
          (SELECT count(*)::INTEGER FROM public.water_tanks AS tank
            WHERE tank.organization_id = ${organizationId}::uuid
              AND tank.farm_id = ${farmId}::uuid AND tank.status = 'active') AS "tanks",
          (SELECT COALESCE(sum(tank.capacity_litres), 0)::TEXT FROM public.water_tanks AS tank
            WHERE tank.organization_id = ${organizationId}::uuid
              AND tank.farm_id = ${farmId}::uuid AND tank.status = 'active') AS "capacityLitres",
          (SELECT COALESCE(sum(tank.stored_litres), 0)::TEXT FROM public.water_tanks AS tank
            WHERE tank.organization_id = ${organizationId}::uuid
              AND tank.farm_id = ${farmId}::uuid AND tank.status = 'active') AS "storedLitres",
          (SELECT COALESCE(sum(usage.usage_litres), 0)::TEXT FROM public.water_usages AS usage
            WHERE usage.organization_id = ${organizationId}::uuid
              AND usage.farm_id = ${farmId}::uuid
              AND usage.usage_date = (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE) AS "usedTodayLitres",
          (SELECT max(reading.measured_at) FROM public.water_readings AS reading
            WHERE reading.organization_id = ${organizationId}::uuid
              AND reading.farm_id = ${farmId}::uuid) AS "levelAsOf"
      `;

      const moistureRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT count(DISTINCT reading.zone_id)::INTEGER AS "zonesWithReading",
               max(reading.measured_at) AS "latestMeasuredAt"
          FROM public.moisture_readings AS reading
         WHERE reading.organization_id = ${organizationId}::uuid AND reading.farm_id = ${farmId}::uuid
      `;

      return { farm, zoneRows, cropRows, livestockRows, taskRows, harvestRows, waterRows, moistureRows };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (result === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const { farm, zoneRows, cropRows, livestockRows, taskRows, harvestRows, waterRows, moistureRows } = result;
    const tasks = taskRows[0] ?? {};
    const eligible = Number(tasks.eligible ?? 0);
    const done = Number(tasks.done ?? 0);
    const zonesByType: Record<string, number> = {};
    for (const row of zoneRows) zonesByType[row.type] = row.count;
    return {
      data: {
        farm: stripNulls({ ...farm }),
        zones: { total: zoneRows.reduce((sum, row) => sum + row.count, 0), byType: zonesByType },
        crops: cropRows[0] ?? {},
        livestock: livestockRows[0] ?? {},
        tasks: {
          openToday: tasks.openToday ?? 0,
          doneToday: tasks.doneToday ?? 0,
          skippedToday: tasks.skippedToday ?? 0,
          overdue: tasks.overdue ?? 0,
          health: {
            formula: 'operations-health.v1',
            minEligible: 5,
            status: eligible >= 5 ? 'ok' : 'unknown',
            eligible,
            done,
            ratio: eligible >= 5 ? (done / eligible).toFixed(4) : null,
          },
        },
        harvests: harvestRows[0] ?? {},
        water: stripNulls({ ...(waterRows[0] ?? {}), levelAsOf: isoInstant((waterRows[0] ?? {}).levelAsOf) ?? undefined }),
        moisture: stripNulls({
          ...(moistureRows[0] ?? {}),
          latestMeasuredAt: isoInstant((moistureRows[0] ?? {}).latestMeasuredAt) ?? undefined,
        }),
      },
      meta: { schemaVersion: 'farm-summary.v1', asOf: new Date().toISOString() },
    };
  }

  /**
   * P07 analytics — farm-local civil-date series, per-unit separation (D-16).
   * Harvest quantities come from effective heads only: voided heads are
   * excluded by construction and counted separately.
   */
  async analytics(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    days: number,
  ) {
    const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;
      const farmRows = await transaction.$queryRaw<{ timezone: string }[]>`
        SELECT farm.timezone FROM public.farms AS farm
         WHERE farm.organization_id = ${organizationId}::uuid AND farm.id = ${farmId}::uuid
      `;
      const timezone = farmRows[0]?.timezone;
      if (!timezone) return null;

      const harvestSeries = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT to_char(record.harvest_date, 'YYYY-MM-DD') AS "date",
               sum(record.quantity_kg)::TEXT AS "quantityKg",
               count(*)::INTEGER AS "records"
          FROM public.harvest_heads AS head
          JOIN public.harvest_records AS record
            ON record.organization_id = head.organization_id
           AND record.farm_id = head.farm_id
           AND record.id = head.effective_record_id
         WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
           AND head.status = 'active'
           AND record.harvest_date BETWEEN
               ((CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE - (${days} - 1))
               AND (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
         GROUP BY record.harvest_date
         ORDER BY record.harvest_date
      `;

      const voidedRows = await transaction.$queryRaw<{ voided: number }[]>`
        SELECT count(*)::INTEGER AS voided
          FROM public.harvest_heads AS head
          JOIN public.harvest_records AS record
            ON record.organization_id = head.organization_id
           AND record.farm_id = head.farm_id
           AND record.id = head.effective_record_id
         WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
           AND head.status = 'voided'
           AND record.harvest_date BETWEEN
               ((CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE - (${days} - 1))
               AND (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
      `;

      const productionSeries = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT to_char(record.recorded_on, 'YYYY-MM-DD') AS "date",
               record.product, record.unit,
               sum(record.quantity)::TEXT AS "quantity",
               count(*)::INTEGER AS "records"
          FROM public.production_records AS record
         WHERE record.organization_id = ${organizationId}::uuid AND record.farm_id = ${farmId}::uuid
           AND record.recorded_on BETWEEN
               ((CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE - (${days} - 1))
               AND (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
         GROUP BY record.recorded_on, record.product, record.unit
         ORDER BY record.recorded_on, record.product
      `;

      const waterSeries = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT to_char(usage.usage_date, 'YYYY-MM-DD') AS "date",
               sum(usage.usage_litres)::TEXT AS "litres"
          FROM public.water_usages AS usage
         WHERE usage.organization_id = ${organizationId}::uuid AND usage.farm_id = ${farmId}::uuid
           AND usage.usage_date BETWEEN
               ((CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE - (${days} - 1))
               AND (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
         GROUP BY usage.usage_date
         ORDER BY usage.usage_date
      `;

      const taskSeries = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT to_char(occurrence.occurrence_date, 'YYYY-MM-DD') AS "date",
               count(*) FILTER (WHERE occurrence.status = 'done')::INTEGER AS "done",
               count(*) FILTER (WHERE occurrence.status = 'skipped')::INTEGER AS "skipped",
               count(*) FILTER (WHERE occurrence.status = 'cancelled')::INTEGER AS "cancelled",
               count(*) FILTER (WHERE occurrence.status IN ('open', 'in_progress'))::INTEGER AS "open"
          FROM public.task_occurrences AS occurrence
         WHERE occurrence.organization_id = ${organizationId}::uuid AND occurrence.farm_id = ${farmId}::uuid
           AND occurrence.occurrence_date BETWEEN
               ((CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE - (${days} - 1))
               AND (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
         GROUP BY occurrence.occurrence_date
         ORDER BY occurrence.occurrence_date
      `;

      return { timezone, harvestSeries, voidedRows, productionSeries, waterSeries, taskSeries };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (result === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const { timezone, harvestSeries, voidedRows, productionSeries, waterSeries, taskSeries } = result;
    return {
      data: {
        range: { days, timezone },
        harvests: {
          series: harvestSeries,
          voidedExcluded: voidedRows[0]?.voided ?? 0,
          unit: 'kg',
        },
        production: { series: productionSeries },
        waterUsage: { series: waterSeries, unit: 'litre' },
        tasks: { series: taskSeries },
      },
      meta: { schemaVersion: 'farm-analytics.v1', asOf: new Date().toISOString() },
    };
  }

  /**
   * P07 weather — read-only cache surface (spec04: snapshots are fetched
   * separately and excluded from the domain changefeed). Never fabricates a
   * condition: disabled feature or missing location → 'unavailable', expired
   * cache → 'stale' with the last-known snapshot attached.
   */
  async weather(principal: VerifiedPrincipal, organizationId: string, farmId: string) {
    const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;

      const farmRows = await transaction.$queryRaw<{ location: string | null }[]>`
        SELECT farm.location FROM public.farms AS farm
         WHERE farm.organization_id = ${organizationId}::uuid AND farm.id = ${farmId}::uuid
      `;
      if (!farmRows[0]) return null;
      const location = farmRows[0].location;

      const snapshots = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT snapshot.provider, snapshot.grid_ref AS "gridRef",
               snapshot.valid_at AS "validAt", snapshot.fetched_at AS "fetchedAt",
               snapshot.payload
          FROM public.weather_snapshots AS snapshot
         WHERE snapshot.organization_id = ${organizationId}::uuid
           AND snapshot.farm_id = ${farmId}::uuid
           AND snapshot.kind = 'current'
         ORDER BY snapshot.fetched_at DESC
         LIMIT 1
      `;
      return { location, snapshot: snapshots[0] ?? null };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (result === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    const { location, snapshot } = result;

    const envelope = (status: string, reason: string | null, body: Record<string, unknown> | null) => ({
      data: stripNulls({
        status,
        reason: reason ?? undefined,
        provider: body?.provider,
        gridRef: body?.gridRef,
        fetchedAt: body ? isoInstant(body.fetchedAt) ?? undefined : undefined,
        validAt: body ? isoInstant(body.validAt) ?? undefined : undefined,
        current: body?.payload,
        staleAfterSeconds: this.weatherFreshTtlSeconds,
      }),
      meta: { schemaVersion: 'farm-weather.v1', asOf: new Date().toISOString() },
    });

    // Withdrawal semantics: a disabled feature or cleared location returns
    // unavailable without the cached payload — no egress happened, and no data
    // is served for a scope the owner withdrew.
    if (!this.weatherEnabled) return envelope('unavailable', 'disabled', null);
    if (location === null) return envelope('unavailable', 'no_location', null);
    if (!snapshot) return envelope('unavailable', 'no_snapshot', null);

    const fetchedAt = new Date(String(snapshot.fetchedAt));
    const validAt = new Date(String(snapshot.validAt));
    const now = Date.now();
    const fresh = now - fetchedAt.getTime() <= this.weatherFreshTtlSeconds * 1000 && validAt.getTime() >= now;
    return envelope(fresh ? 'fresh' : 'stale', fresh ? null : 'expired', {
      provider: snapshot.provider,
      gridRef: snapshot.gridRef,
      fetchedAt: snapshot.fetchedAt,
      validAt: snapshot.validAt,
      payload: snapshot.payload,
    });
  }

  // ---- P08 sync surface ---------------------------------------------------

  private get cursorSigningKey(): string {
    const key = this.environment?.cursorSigningKey;
    if (!key) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    return key;
  }

  /**
   * Materialize a private bootstrap snapshot: every wire-shape domain row for
   * the farm read inside one REPEATABLE READ transaction, chunked and written
   * via the migration-role definer (cap enforcement + TTL land atomically with
   * the domain reads). Emits a signed changes cursor anchored at the captured
   * high watermark so the client can pull deltas immediately (spec04 §7).
   */
  async createBootstrap(principal: VerifiedPrincipal, organizationId: string, farmId: string, snapshotId: string) {
    const pseudonym = actorPseudonym(principal.actorId);
    try {
      const manifest = await this.tenantDatabase.client.$transaction(async (transaction) => {
        await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
        const access = await transaction.$queryRaw<AccessRow[]>`
          SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
        `;
        if (!access[0]?.can_read) return null;

        const scopeRows = await transaction.$queryRaw<Record<string, unknown>[]>`
          SELECT clock.revision::TEXT AS "highWatermark",
                 clock.continuity_epoch::TEXT AS "continuityEpoch",
                 clock.pruned_through_revision::TEXT AS "prunedThroughRevision",
                 org.policy_version::TEXT AS "scopePolicyVersion"
            FROM public.farm_clocks AS clock
            JOIN public.organizations AS org ON org.id = clock.organization_id
           WHERE clock.organization_id = ${organizationId}::uuid AND clock.farm_id = ${farmId}::uuid
        `;
        const scope = scopeRows[0];
        if (!scope) return null;

        const entities = await this.bootstrapEntityRows(transaction, organizationId, farmId);
        const chunks: { pageIndex: number; rowCount: number; payload: unknown[] }[] = [];
        let page: unknown[] = [];
        let pageRows = 0;
        const flush = () => {
          if (pageRows === 0) return;
          chunks.push({ pageIndex: chunks.length + 1, rowCount: pageRows, payload: page });
          page = [];
          pageRows = 0;
        };
        for (const { entity, records } of entities) {
          let offset = 0;
          while (offset < records.length) {
            if (pageRows === BOOTSTRAP_PAGE_ROWS) flush();
            const take = Math.min(BOOTSTRAP_PAGE_ROWS - pageRows, records.length - offset);
            page.push({ entity, records: records.slice(offset, offset + take) });
            pageRows += take;
            offset += take;
          }
        }
        flush();
        // The 'farm' entity always contributes its own row, so chunks can
        // never be empty here — the writer function still asserts >=1 chunk.
        if (chunks.length === 0) throw new Error('BOOTSTRAP_NO_CHUNKS');

        const written = await transaction.$queryRaw<{ manifest: Record<string, unknown> }[]>`
          SELECT public.farmly_write_bootstrap_snapshot(
            ${organizationId}::uuid, ${farmId}::uuid, ${snapshotId}::uuid, ${pseudonym},
            ${BigInt(scope.scopePolicyVersion as string)}::bigint,
            ${BigInt(scope.continuityEpoch as string)}::bigint,
            ${BigInt(scope.highWatermark as string)}::bigint,
            ${BigInt(scope.prunedThroughRevision as string)}::bigint,
            ${JSON.stringify(chunks)}::jsonb,
            ${BOOTSTRAP_TTL_SECONDS}, ${BOOTSTRAP_MAX_ROWS}, ${BOOTSTRAP_MAX_BYTES}
          ) AS manifest
        `;
        return { scope, manifest: written[0]?.manifest };
      }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });

      if (manifest === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
      const { scope, manifest: written } = manifest;
      const changesCursor = signChangesCursor({
        kind: CHANGES_CURSOR_KIND,
        organizationId,
        farmId,
        actorBinding: changesActorBinding(principal.actorId, this.cursorSigningKey),
        scopePolicyVersion: String(scope.scopePolicyVersion),
        continuityEpoch: String(scope.continuityEpoch),
        revision: String(scope.highWatermark),
        pageSize: CHANGES_PAGE_SIZE,
      }, this.cursorSigningKey);
      return {
        data: stripNulls({
          snapshotId,
          expiresAt: isoInstant(written?.expiresAt),
          continuityEpoch: String(scope.continuityEpoch),
          scopePolicyVersion: String(scope.scopePolicyVersion),
          highWatermark: String(scope.highWatermark),
          prunedThroughRevision: String(scope.prunedThroughRevision),
          totalRows: Number(written?.rowCount ?? 0),
          byteCount: Number(written?.byteCount ?? 0),
          chunkCount: Number(written?.chunkCount ?? 0),
          maxRows: BOOTSTRAP_MAX_ROWS,
          maxBytes: BOOTSTRAP_MAX_BYTES,
          changesCursor,
        }),
        meta: { schemaVersion: 'farm-bootstrap.v1', asOf: new Date().toISOString() },
      };
    } catch (error) {
      if (isBootstrapTooLarge(error)) {
        throw new ConflictException({ code: 'BOOTSTRAP_TOO_LARGE', retryable: false });
      }
      // A foreign actor cannot enumerate private snapshot ids, but a random or
      // deliberately reused client UUID can still hit the snapshot PK — report
      // a domain conflict rather than a bare 500.
      if (typeof error === 'object' && error !== null
        && 'code' in error && (error as { code: unknown }).code === '23505') {
        throw new ConflictException({ code: 'BOOTSTRAP_SNAPSHOT_CONFLICT', retryable: false });
      }
      throw error;
    }
  }

  /**
   * Wire-shape rows for every entity in the domain change-feed registry
   * (spec04 §198): identical column aliases to the kernel view builders so a
   * client applies snapshot records and feed records uniformly.
   */
  private async bootstrapEntityRows(
    transaction: Prisma.TransactionClient,
    organizationId: string,
    farmId: string,
  ): Promise<{ entity: string; records: Record<string, unknown>[] }[]> {
    const run = (entity: string, query: Prisma.Sql) =>
      transaction.$queryRaw<Record<string, unknown>[]>(query)
        .then((records) => ({ entity, records }));
    return [
      await run('farm', Prisma.sql`
        SELECT farm.id::TEXT AS "farmId", farm.name, farm.area_m2::TEXT AS "areaM2",
               farm.timezone, farm.location, farm.status, farm.version
          FROM public.farms AS farm
         WHERE farm.organization_id = ${organizationId}::uuid AND farm.id = ${farmId}::uuid`),
      await run('zone', Prisma.sql`
        SELECT zone.id::TEXT AS "id", zone.version, zone.type, zone.name, zone.geometry,
               zone.area_m2::TEXT AS "areaM2", zone.status
          FROM public.zones AS zone
         WHERE zone.organization_id = ${organizationId}::uuid AND zone.farm_id = ${farmId}::uuid
         ORDER BY zone.id`),
      await run('cropSpecies', Prisma.sql`
        SELECT species.id::TEXT AS "id", species.version, species.name,
               species.harvest_unit AS "harvestUnit", species.status
          FROM public.crop_species AS species
         WHERE species.organization_id = ${organizationId}::uuid AND species.farm_id = ${farmId}::uuid
         ORDER BY species.id`),
      await run('planting', Prisma.sql`
        SELECT planting.id::TEXT AS "id", planting.version,
               planting.crop_species_id::TEXT AS "cropSpeciesId", planting.plot_id::TEXT AS "plotId",
               planting.status, planting.sowing_date::TEXT AS "sowingDate",
               planting.expected_harvest_date::TEXT AS "expectedHarvestDate",
               planting.area_m2::TEXT AS "areaM2"
          FROM public.plantings AS planting
         WHERE planting.organization_id = ${organizationId}::uuid AND planting.farm_id = ${farmId}::uuid
         ORDER BY planting.id`),
      await run('plantingEvent', Prisma.sql`
        SELECT event.id::TEXT AS "id", 1 AS version, event.planting_id::TEXT AS "plantingId",
               event.event_type AS "eventType", event.note, event.occurred_on::TEXT AS "occurredOn"
          FROM public.planting_events AS event
         WHERE event.organization_id = ${organizationId}::uuid AND event.farm_id = ${farmId}::uuid
         ORDER BY event.id`),
      await run('herd', Prisma.sql`
        SELECT herd.id::TEXT AS "id", herd.version, herd.mode, herd.species, herd.status,
               CASE WHEN herd.mode = 'tracked' THEN (
                   SELECT count(*)::INTEGER FROM public.animals AS animal
                    WHERE animal.organization_id = herd.organization_id
                      AND animal.farm_id = herd.farm_id AND animal.herd_id = herd.id
                      AND animal.status = 'alive' AND NOT animal.archived)
               ELSE COALESCE((
                   SELECT sum(movement.delta) FROM public.livestock_movements AS movement
                    WHERE movement.organization_id = herd.organization_id
                      AND movement.farm_id = herd.farm_id AND movement.herd_id = herd.id), 0)::INTEGER
               END AS "headcount"
          FROM public.herds AS herd
         WHERE herd.organization_id = ${organizationId}::uuid AND herd.farm_id = ${farmId}::uuid
         ORDER BY herd.id`),
      await run('animal', Prisma.sql`
        SELECT animal.id::TEXT AS "id", animal.version, animal.herd_id::TEXT AS "herdId",
               animal.tag, animal.name, animal.birth_date::TEXT AS "birthDate",
               animal.status, animal.archived
          FROM public.animals AS animal
         WHERE animal.organization_id = ${organizationId}::uuid AND animal.farm_id = ${farmId}::uuid
         ORDER BY animal.id`),
      await run('livestockMovement', Prisma.sql`
        SELECT movement.id::TEXT AS "id", 1 AS version, movement.herd_id::TEXT AS "herdId",
               movement.movement_type AS "movementType", movement.delta,
               movement.occurred_at AS "occurredAt"
          FROM public.livestock_movements AS movement
         WHERE movement.organization_id = ${organizationId}::uuid AND movement.farm_id = ${farmId}::uuid
         ORDER BY movement.id`),
      await run('animalObservation', Prisma.sql`
        SELECT observation.id::TEXT AS "id", 1 AS version, observation.herd_id::TEXT AS "herdId",
               observation.animal_id::TEXT AS "animalId", observation.kind, observation.note,
               observation.observed_on::TEXT AS "observedOn"
          FROM public.animal_observations AS observation
         WHERE observation.organization_id = ${organizationId}::uuid AND observation.farm_id = ${farmId}::uuid
         ORDER BY observation.id`),
      await run('productionRecord', Prisma.sql`
        SELECT record.id::TEXT AS "id", 1 AS version, record.herd_id::TEXT AS "herdId",
               record.animal_id::TEXT AS "animalId", record.product, record.quantity::TEXT AS "quantity",
               record.unit, record.recorded_on::TEXT AS "recordedOn"
          FROM public.production_records AS record
         WHERE record.organization_id = ${organizationId}::uuid AND record.farm_id = ${farmId}::uuid
         ORDER BY record.id`),
      await run('taskTemplate', Prisma.sql`
        SELECT template.id::TEXT AS "id", template.version, template.title, template.kind,
               template.zone_id::TEXT AS "zoneId", template.recurrence,
               template.assignee_membership_id::TEXT AS "assigneeMembershipId",
               template.starts_on::TEXT AS "startsOn", template.ends_on::TEXT AS "endsOn",
               template.status
          FROM public.task_templates AS template
         WHERE template.organization_id = ${organizationId}::uuid AND template.farm_id = ${farmId}::uuid
         ORDER BY template.id`),
      await run('taskOccurrence', Prisma.sql`
        SELECT occurrence.id::TEXT AS "id", occurrence.version,
               occurrence.template_id::TEXT AS "templateId",
               occurrence.occurrence_date::TEXT AS "occurrenceDate",
               occurrence.slot, occurrence.status,
               occurrence.due_at AS "dueAt", occurrence.completed_by AS "completedBy"
          FROM public.task_occurrences AS occurrence
         WHERE occurrence.organization_id = ${organizationId}::uuid AND occurrence.farm_id = ${farmId}::uuid
         ORDER BY occurrence.id`),
      await run('taskTransition', Prisma.sql`
        SELECT transition.id::TEXT AS "id", 1 AS version,
               transition.occurrence_id::TEXT AS "occurrenceId", transition.transition,
               transition.from_status AS "fromStatus", transition.to_status AS "toStatus"
          FROM public.task_transitions AS transition
         WHERE transition.organization_id = ${organizationId}::uuid AND transition.farm_id = ${farmId}::uuid
         ORDER BY transition.id`),
      await run('harvest', Prisma.sql`
        SELECT head.harvest_id::TEXT AS "id", head.version,
               head.planting_id::TEXT AS "plantingId",
               record.quantity_kg::TEXT AS "quantityKg",
               record.harvest_date::TEXT AS "harvestDate", head.status
          FROM public.harvest_heads AS head
          JOIN public.harvest_records AS record
            ON record.organization_id = head.organization_id
           AND record.farm_id = head.farm_id
           AND record.id = head.effective_record_id
         WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
         ORDER BY head.harvest_id`),
      await run('harvestRecord', Prisma.sql`
        SELECT record.id::TEXT AS "id", 1 AS version, record.harvest_id::TEXT AS "harvestId",
               record.quantity_kg::TEXT AS "quantityKg",
               record.harvest_date::TEXT AS "harvestDate",
               record.supersedes_record_id::TEXT AS "supersedesRecordId"
          FROM public.harvest_records AS record
         WHERE record.organization_id = ${organizationId}::uuid AND record.farm_id = ${farmId}::uuid
         ORDER BY record.id`),
      await run('correctionProposal', Prisma.sql`
        SELECT proposal.id::TEXT AS "id", 1 AS version, proposal.harvest_id::TEXT AS "harvestId",
               proposal.proposed_quantity_kg::TEXT AS "proposedQuantityKg",
               proposal.reason, proposal.status
          FROM public.correction_proposals AS proposal
         WHERE proposal.organization_id = ${organizationId}::uuid AND proposal.farm_id = ${farmId}::uuid
         ORDER BY proposal.id`),
      await run('moistureReading', Prisma.sql`
        SELECT reading.id::TEXT AS "id", 1 AS version, reading.zone_id::TEXT AS "zoneId",
               reading.value::TEXT AS "value", reading.method, reading.source,
               reading.measured_at AS "measuredAt"
          FROM public.moisture_readings AS reading
         WHERE reading.organization_id = ${organizationId}::uuid AND reading.farm_id = ${farmId}::uuid
         ORDER BY reading.id`),
      await run('waterTank', Prisma.sql`
        SELECT tank.id::TEXT AS "id", tank.version, tank.name, tank.zone_id::TEXT AS "zoneId",
               tank.capacity_litres::TEXT AS "capacityLitres",
               tank.stored_litres::TEXT AS "storedLitres", tank.status
          FROM public.water_tanks AS tank
         WHERE tank.organization_id = ${organizationId}::uuid AND tank.farm_id = ${farmId}::uuid
         ORDER BY tank.id`),
      await run('waterReading', Prisma.sql`
        SELECT reading.id::TEXT AS "id", 1 AS version, reading.tank_id::TEXT AS "tankId",
               reading.stored_litres::TEXT AS "storedLitres",
               reading.capacity_snapshot_litres::TEXT AS "capacityLitres",
               reading.source, reading.measured_at AS "measuredAt"
          FROM public.water_readings AS reading
         WHERE reading.organization_id = ${organizationId}::uuid AND reading.farm_id = ${farmId}::uuid
         ORDER BY reading.id`),
      await run('waterUsage', Prisma.sql`
        SELECT usage.id::TEXT AS "id", 1 AS version, usage.tank_id::TEXT AS "tankId",
               usage.usage_litres::TEXT AS "usageLitres",
               usage.usage_date::TEXT AS "usageDate", usage.note
          FROM public.water_usages AS usage
         WHERE usage.organization_id = ${organizationId}::uuid AND usage.farm_id = ${farmId}::uuid
         ORDER BY usage.id`),
    ];
  }

  /**
   * Read one immutable bootstrap page. The snapshot is creator-private
   * (actor pseudonym must match — foreign handles get the same 404 as an
   * unknown id), expires strictly on its 15-minute TTL, and is invalidated
   * by any epoch or policy-version change (spec04 §7: grant/policy change
   * invalidates; page reads never extend TTL).
   */
  async getBootstrapPage(
    principal: VerifiedPrincipal,
    organizationId: string,
    farmId: string,
    snapshotId: string,
    pageCursor?: string,
  ) {
    const pseudonym = actorPseudonym(principal.actorId);
    const pageIndex = pageCursor === undefined ? 1 : Number(pageCursor);
    if (!Number.isInteger(pageIndex) || pageIndex < 1) {
      throw new BadRequestException({ code: 'PAGE_CURSOR_INVALID' });
    }

    const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return { kind: 'unknown' as const };

      const snapshots = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT snapshot.id::TEXT AS "snapshotId", snapshot.actor_pseudonym,
               snapshot.scope_policy_version::TEXT AS "scopePolicyVersion",
               snapshot.continuity_epoch::TEXT AS "continuityEpoch",
               snapshot.high_watermark::TEXT AS "highWatermark",
               snapshot.chunk_count AS "chunkCount", snapshot.expires_at AS "expiresAt",
               org.policy_version::TEXT AS "currentPolicyVersion",
               clock.continuity_epoch::TEXT AS "currentEpoch"
          FROM public.bootstrap_snapshots AS snapshot
          JOIN public.organizations AS org ON org.id = snapshot.organization_id
          JOIN public.farm_clocks AS clock
            ON clock.organization_id = snapshot.organization_id AND clock.farm_id = snapshot.farm_id
         WHERE snapshot.organization_id = ${organizationId}::uuid
           AND snapshot.farm_id = ${farmId}::uuid
           AND snapshot.id = ${snapshotId}::uuid
      `;
      const snapshot = snapshots[0];
      // Unknown snapshot and foreign-creator snapshot share the same 404 —
      // no cross-actor enumeration of private snapshot ids (spec04 §204).
      if (!snapshot || snapshot.actor_pseudonym !== pseudonym) return { kind: 'unknown' as const };

      const expired = new Date(String(snapshot.expiresAt)).getTime() <= Date.now();
      const invalidated = snapshot.currentPolicyVersion !== snapshot.scopePolicyVersion
        || snapshot.currentEpoch !== snapshot.continuityEpoch;
      if (expired || invalidated) return { kind: 'expired' as const };

      const chunks = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT chunk.page_index AS "pageIndex", chunk.row_count AS "rowCount", chunk.payload
          FROM public.bootstrap_snapshot_chunks AS chunk
         WHERE chunk.organization_id = ${organizationId}::uuid
           AND chunk.farm_id = ${farmId}::uuid
           AND chunk.snapshot_id = ${snapshotId}::uuid
           AND chunk.page_index = ${pageIndex}
      `;
      if (!chunks[0]) return { kind: 'page-out-of-range' as const, snapshot };
      return { kind: 'ok' as const, snapshot, chunk: chunks[0] };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (result.kind === 'unknown') throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    if (result.kind === 'expired') throw new GoneException({ code: 'CURSOR_EXPIRED' });
    if (result.kind === 'page-out-of-range') {
      throw new BadRequestException({ code: 'PAGE_CURSOR_INVALID' });
    }

    const chunkCount = Number(result.snapshot.chunkCount);
    const hasMore = pageIndex < chunkCount;
    return {
      data: {
        snapshotId,
        pageIndex,
        rowCount: Number(result.chunk.rowCount),
        blocks: result.chunk.payload,
      },
      page: {
        hasMore,
        nextPageCursor: hasMore ? String(pageIndex + 1) : null,
        chunkCount,
      },
      meta: { schemaVersion: 'farm-bootstrap.v1', asOf: new Date().toISOString() },
    };
  }

  /**
   * Read committed change sets in revision order from a signed cursor. The
   * cursor binds org/farm/policy/epoch/actor/page-size; any drift, expired
   * floor, or revision beyond the current watermark returns CURSOR_EXPIRED
   * (410) — never an empty success above the retention floor (spec04 §200).
   */
  async getChanges(principal: VerifiedPrincipal, organizationId: string, farmId: string, cursorToken: string) {
    const cursor = readChangesCursor(cursorToken, this.cursorSigningKey);
    if (cursor === null
      || cursor.organizationId !== organizationId
      || cursor.farmId !== farmId
      || cursor.actorBinding !== changesActorBinding(principal.actorId, this.cursorSigningKey)) {
      throw new GoneException({ code: 'CURSOR_EXPIRED' });
    }

    const result = await this.tenantDatabase.client.$transaction(async (transaction) => {
      await transaction.$queryRaw`SELECT set_config('app.actor_id', ${principal.actorId}, TRUE)`;
      const access = await transaction.$queryRaw<AccessRow[]>`
        SELECT public.farmly_actor_can_read_farm(${organizationId}::uuid, ${farmId}::uuid) AS can_read
      `;
      if (!access[0]?.can_read) return null;

      const scopeRows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT clock.revision::TEXT AS "highWatermark",
               clock.continuity_epoch::TEXT AS "continuityEpoch",
               clock.pruned_through_revision::TEXT AS "prunedThroughRevision",
               org.policy_version::TEXT AS "scopePolicyVersion"
          FROM public.farm_clocks AS clock
          JOIN public.organizations AS org ON org.id = clock.organization_id
         WHERE clock.organization_id = ${organizationId}::uuid AND clock.farm_id = ${farmId}::uuid
      `;
      const scope = scopeRows[0];
      if (!scope) return null;

      const cursorRevision = BigInt(cursor.revision);
      const watermark = BigInt(scope.highWatermark as string);
      const floor = BigInt(scope.prunedThroughRevision as string);
      const epochMismatch = cursor.continuityEpoch !== String(scope.continuityEpoch);
      const policyMismatch = cursor.scopePolicyVersion !== String(scope.scopePolicyVersion);
      const outOfBounds = cursorRevision < floor || cursorRevision > watermark;
      if (epochMismatch || policyMismatch || outOfBounds) {
        return { expired: true as const };
      }

      const rows = await transaction.$queryRaw<Record<string, unknown>[]>`
        SELECT change.revision::TEXT AS "revision",
               change.continuity_epoch::TEXT AS "continuityEpoch",
               change.operation_id::TEXT AS "operationId",
               change.schema_version AS "schemaVersion",
               change.changes, change.created_at AS "createdAt"
          FROM public.change_sets AS change
         WHERE change.organization_id = ${organizationId}::uuid
           AND change.farm_id = ${farmId}::uuid
           AND change.revision > ${cursorRevision}::bigint
           AND change.revision <= ${watermark}::bigint
         ORDER BY change.revision
         LIMIT ${cursor.pageSize}
      `;
      return { expired: false as const, scope, rows, watermark };
    }, { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted });

    if (result === null) throw new NotFoundException({ code: 'SCOPE_UNKNOWN' });
    if (result.expired) throw new GoneException({ code: 'CURSOR_EXPIRED' });

    const lastRevision = result.rows.length > 0
      ? String(result.rows[result.rows.length - 1].revision)
      : cursor.revision;
    const hasMore = BigInt(lastRevision) < result.watermark;
    const nextCursor = signChangesCursor({
      ...cursor,
      revision: lastRevision,
    }, this.cursorSigningKey);
    return {
      data: {
        changeSets: result.rows.map((row) => stripNulls({
          revision: String(row.revision),
          continuityEpoch: String(row.continuityEpoch),
          operationId: row.operationId,
          schemaVersion: row.schemaVersion,
          changes: row.changes,
          createdAt: isoInstant(row.createdAt),
        })),
        highWatermark: String(result.watermark),
      },
      page: { hasMore, nextCursor },
      meta: { schemaVersion: 'farm-changes.v1', asOf: new Date().toISOString() },
    };
  }
}

function isBootstrapTooLarge(error: unknown): boolean {
  return typeof error === 'object' && error !== null
    && 'message' in error && String((error as { message: unknown }).message).includes('BOOTSTRAP_TOO_LARGE');
}

function stripNulls(row: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined && value !== null));
}
