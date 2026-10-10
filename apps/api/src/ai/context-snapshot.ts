import type { Prisma } from '@prisma/client';
import { AI_SNAPSHOT_SCHEMA } from './ai-provider.js';

// ---------------------------------------------------------------------------
// Allowlisted private context snapshot (spec05 §2). Confirmed scalar facts
// only: planting stage/dates/count, herd count/species, task due/state,
// harvest/production totals+units, latest manual readings, coarse
// weather/source/freshness. Hard exclusions: full rows, contacts, email,
// phone, session data, keys, teammate chats, exact farm location, personal
// or veterinary free-text notes. Pending unsynced local edits never appear —
// every read is server-side authorized state.
// ---------------------------------------------------------------------------

export interface AiContextSnapshotSource {
  readonly sourceId: string;
  readonly coverage: string;
  readonly observedAt?: string;
  readonly recordedAt?: string;
  readonly unit?: string;
  readonly method?: string;
}

export interface AiContextSnapshot {
  readonly schemaVersion: typeof AI_SNAPSHOT_SCHEMA;
  readonly asOf: string;
  readonly facts: Readonly<Record<string, unknown>>;
  readonly sources: readonly AiContextSnapshotSource[];
}

type Tx = Prisma.TransactionClient;

export async function buildContextSnapshot(
  transaction: Tx,
  organizationId: string,
  farmId: string,
): Promise<AiContextSnapshot> {
  const farmRows = await transaction.$queryRaw<{ name: string; timezone: string }[]>`
    SELECT farm.name, farm.timezone
      FROM public.farms AS farm
     WHERE farm.organization_id = ${organizationId}::uuid AND farm.id = ${farmId}::uuid
  `;
  const farm = farmRows[0] ?? { name: 'farm', timezone: 'UTC' };
  const timezone = farm.timezone;

  const [plantings, herds, tasks, harvests, water, moisture, weather] = await Promise.all([
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT count(*) FILTER (WHERE planting.status = 'active')::INTEGER AS "active",
             count(*)::INTEGER AS "total"
        FROM public.plantings AS planting
       WHERE planting.organization_id = ${organizationId}::uuid AND planting.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT count(*) FILTER (WHERE herd.status = 'active')::INTEGER AS "herds",
             COALESCE(sum(CASE WHEN herd.mode = 'tracked' THEN (
                 SELECT count(*) FROM public.animals AS animal
                  WHERE animal.organization_id = herd.organization_id
                    AND animal.farm_id = herd.farm_id AND animal.herd_id = herd.id
                    AND animal.status = 'alive' AND NOT animal.archived
               ) ELSE COALESCE((
                 SELECT sum(movement.delta) FROM public.livestock_movements AS movement
                  WHERE movement.organization_id = herd.organization_id
                    AND movement.farm_id = herd.farm_id AND movement.herd_id = herd.id
               ), 0) END), 0)::INTEGER AS "headcount"
        FROM public.herds AS herd
       WHERE herd.organization_id = ${organizationId}::uuid AND herd.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT count(*) FILTER (WHERE occurrence.occurrence_date = (CURRENT_TIMESTAMP AT TIME ZONE ${timezone})::DATE
                AND occurrence.status IN ('open', 'in_progress'))::INTEGER AS "openToday",
             count(*) FILTER (WHERE occurrence.status = 'open' AND occurrence.due_at IS NOT NULL
                AND occurrence.due_at < CURRENT_TIMESTAMP)::INTEGER AS "overdue"
        FROM public.task_occurrences AS occurrence
       WHERE occurrence.organization_id = ${organizationId}::uuid AND occurrence.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT count(*) FILTER (WHERE head.status = 'active')::INTEGER AS "harvests",
             COALESCE(sum(record.quantity_kg) FILTER (WHERE head.status = 'active'), 0)::TEXT AS "totalKg"
        FROM public.harvest_heads AS head
        JOIN public.harvest_records AS record
          ON record.organization_id = head.organization_id AND record.farm_id = head.farm_id
         AND record.harvest_id = head.harvest_id AND record.id = head.effective_record_id
       WHERE head.organization_id = ${organizationId}::uuid AND head.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT count(*) FILTER (WHERE tank.status = 'active')::INTEGER AS "tanks",
             COALESCE(sum(tank.stored_litres) FILTER (WHERE tank.status = 'active'), 0)::TEXT AS "storedLitres",
             (SELECT max(reading.measured_at) FROM public.water_readings AS reading
               WHERE reading.organization_id = ${organizationId}::uuid
                 AND reading.farm_id = ${farmId}::uuid) AS "latestReadingAt"
        FROM public.water_tanks AS tank
       WHERE tank.organization_id = ${organizationId}::uuid AND tank.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT max(reading.measured_at) AS "latestMeasuredAt",
             count(DISTINCT reading.zone_id)::INTEGER AS "zonesCovered"
        FROM public.moisture_readings AS reading
       WHERE reading.organization_id = ${organizationId}::uuid AND reading.farm_id = ${farmId}::uuid
    `,
    transaction.$queryRaw<Record<string, unknown>[]>`
      SELECT snapshot.payload->>'temperatureC' AS "temperatureC",
             snapshot.payload->>'weatherCode' AS "weatherCode",
             snapshot.provider,
             snapshot.fetched_at AS "fetchedAt", snapshot.valid_at AS "validAt"
        FROM public.weather_snapshots AS snapshot
       WHERE snapshot.organization_id = ${organizationId}::uuid AND snapshot.farm_id = ${farmId}::uuid
         AND snapshot.kind = 'current'
       ORDER BY snapshot.fetched_at DESC
       LIMIT 1
    `,
  ]);

  const taskFacts = tasks[0] ?? {};
  const herdFacts = herds[0] ?? {};
  const plantingFacts = plantings[0] ?? {};
  const harvestFacts = harvests[0] ?? {};
  const waterFacts = water[0] ?? {};
  const moistureFacts = moisture[0] ?? {};
  const weatherFact = weather[0];

  const sources: AiContextSnapshotSource[] = [
    { sourceId: 'plantings', coverage: 'count+status' },
    { sourceId: 'herds', coverage: 'count' },
    { sourceId: 'animals', coverage: 'count' },
    { sourceId: 'taskOccurrences', coverage: 'due+state' },
    { sourceId: 'harvests', coverage: 'totals', unit: 'kg' },
    { sourceId: 'waterTanks', coverage: 'totals', unit: 'L' },
  ];
  if (moistureFacts['latestMeasuredAt']) {
    sources.push({
      sourceId: 'moistureReadings',
      coverage: 'latest',
      observedAt: asIso(moistureFacts['latestMeasuredAt']),
    });
  }
  if (waterFacts['latestReadingAt']) {
    sources.push({
      sourceId: 'waterReadings',
      coverage: 'latest',
      observedAt: asIso(waterFacts['latestReadingAt']),
    });
  }
  if (weatherFact) {
    sources.push({
      sourceId: 'weather',
      coverage: 'coarse-grid current',
      observedAt: asIso(weatherFact['fetchedAt']),
      method: asString(weatherFact['provider']) ?? undefined,
    });
  }

  return {
    schemaVersion: AI_SNAPSHOT_SCHEMA,
    asOf: new Date().toISOString(),
    facts: {
      farmName: farm.name,
      timezone,
      plantings: {
        active: toInt(plantingFacts['active']),
        total: toInt(plantingFacts['total']),
      },
      livestock: {
        herds: toInt(herdFacts['herds']),
        headcount: toInt(herdFacts['headcount']),
      },
      tasks: {
        openToday: toInt(taskFacts['openToday']),
        overdue: toInt(taskFacts['overdue']),
      },
      harvests: {
        count: toInt(harvestFacts['harvests']),
        totalKg: asString(harvestFacts['totalKg']),
      },
      water: {
        tanks: toInt(waterFacts['tanks']),
        storedLitres: asString(waterFacts['storedLitres']),
        latestReadingAt: asIso(waterFacts['latestReadingAt']),
      },
      moisture: {
        zonesCovered: toInt(moistureFacts['zonesCovered']),
        latestMeasuredAt: asIso(moistureFacts['latestMeasuredAt']),
      },
      weather: weatherFact
        ? {
            provider: asString(weatherFact['provider']),
            weatherCode: asString(weatherFact['weatherCode']),
            temperatureC: asString(weatherFact['temperatureC']),
            fetchedAt: asIso(weatherFact['fetchedAt']),
            validAt: asIso(weatherFact['validAt']),
          }
        : null,
    },
    sources,
  };
}

function toInt(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number.parseInt(String(value ?? '0'), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function asIso(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (value instanceof Date) return value.toISOString();
  return String(value);
}
