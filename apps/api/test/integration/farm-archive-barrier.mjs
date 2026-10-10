// S-07/S-18 deterministic barrier: an in-flight farm-scoped write and a
// farm.archive must serialize on the farms row lock — either the write commits
// before the archive decision, or it is denied after the archive commits. No
// post-archive write may apply, and the pair must never deadlock.

import { randomBytes, createHash, randomUUID } from 'node:crypto';
import { Client } from 'pg';

const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const databaseName = process.env.FARMLY_MIGRATION_DATABASE_NAME ?? 'farmly_test_261005';
const SAFE_CODE = /^[A-Z0-9_]+$/;

function assert(condition, code) {
  if (!condition) throw Object.assign(new Error(code), { code });
}
function tenantUrl(name) {
  return `postgresql://farmly_tenant_app:${encodeURIComponent(tenantPassword)}@postgres:5432/${databaseName}?application_name=${name}`;
}
function hash(text) {
  return createHash('sha256').update(text).digest('hex');
}
function intent(type, resourceId, payload, overrides = {}) {
  return JSON.stringify({
    schemaVersion: 'farm-mutation.v1',
    continuityEpoch: '1',
    operationId: randomUUID(),
    type,
    resourceId,
    dependsOn: [],
    payload,
    ...overrides,
  });
}

async function applyMutation(client, orgId, actorId, intentJson, farmId) {
  const rows = await client.query(
    `SELECT outcome, code, response_data FROM public.apply_farm_mutation(
       $1::uuid, $2, $3, ($4::jsonb ->> 'operationId')::uuid, $5, 1::bigint, $4::jsonb, NULL::text, $6::uuid)`,
    [orgId, actorId, hash(`actor:${actorId}`), intentJson, hash(`req:${intentJson}`), farmId],
  );
  return rows.rows[0];
}

async function main() {
  assert(migrationUrl && tenantPassword, 'BARRIER_ENV_MISSING');
  const suffix = randomUUID().replaceAll('-', '').slice(0, 12);
  const actorId = `barrier-actor-${suffix}`;
  const orgId = randomUUID();
  const farmId = randomUUID();

  const migration = new Client({ connectionString: migrationUrl });
  const tx1 = new Client({ connectionString: tenantUrl(`barrier-a-${suffix}`) });
  const tx2 = new Client({ connectionString: tenantUrl(`barrier-b-${suffix}`) });
  await Promise.all([migration.connect(), tx1.connect(), tx2.connect()]);

  try {
    // Fixture: verified actor + org + owner membership + one farm with clock.
    await migration.query(`INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt") VALUES ($1, 'Barrier', $2, TRUE, now())`, [actorId, `barrier-${suffix}@farmly.test`]);
    await migration.query(`INSERT INTO public.organizations (id, name, continuity_epoch) VALUES ($1::uuid, 'Barrier org', 1)`, [orgId]);
    await migration.query(`INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status) VALUES ($1::uuid, $2::uuid, $3, 'owner', 'active')`, [randomUUID(), orgId, actorId]);
    await migration.query(`INSERT INTO public.farms (id, organization_id, name, timezone, status, version) VALUES ($1::uuid, $2::uuid, 'Barrier farm', 'UTC', 'active', 1)`, [farmId, orgId]);
    await migration.query(`INSERT INTO public.farm_clocks (organization_id, farm_id, continuity_epoch, revision) VALUES ($1::uuid, $2::uuid, 1, 1)`, [orgId, farmId]);

    const setActor = async (client) => client.query(`SELECT set_config('app.actor_id', $1, TRUE)`, [actorId]);

    // ---- Order A: write commits first, archive applies after ---------------
    await tx1.query('BEGIN');
    await setActor(tx1);
    const zoneAId = randomUUID();
    const zoneA = intent('zone.create', zoneAId, {
      name: `Barrier zone A ${suffix}`, type: 'crop_plot',
      geometry: { points: [{ x: '0', y: '0' }, { x: '1', y: '0' }, { x: '0.5', y: '1' }] },
    });
    const zoneAResult = await applyMutation(tx1, orgId, actorId, zoneA, farmId);
    assert(zoneAResult.outcome === 'applied', `ORDER_A_ZONE_CREATE_${zoneAResult.outcome}_${zoneAResult.code ?? ''}`);

    await tx2.query('BEGIN');
    await setActor(tx2);
    const archiveOp = intent('farm.archive', farmId, {}, { baseVersion: 1 });
    let archiveResolved = false;
    const archivePromise = applyMutation(tx2, orgId, actorId, archiveOp, farmId).then((r) => { archiveResolved = true; return r; });
    await new Promise((resolve) => setTimeout(resolve, 700));
    assert(archiveResolved === false, 'ORDER_A_ARCHIVE_NOT_BLOCKED_ON_FARM_LOCK');
    await tx1.query('COMMIT');
    const archiveResult = await archivePromise;
    assert(archiveResult.outcome === 'applied', `ORDER_A_ARCHIVE_${archiveResult.outcome}_${archiveResult.code ?? ''}`);
    await tx2.query('COMMIT');
    console.log(JSON.stringify({ orderA: 'commit-before-archive verified: write committed, archive applied after unblock' }));

    // Post-archive write must be denied (deny-after) on a fresh transaction.
    const tx3 = new Client({ connectionString: tenantUrl(`barrier-c-${suffix}`) });
    await tx3.connect();
    try {
      await tx3.query('BEGIN');
      await setActor(tx3);
      const postWrite = intent('zone.create', randomUUID(), {
        name: `Post-archive zone ${suffix}`, type: 'other',
        geometry: { points: [{ x: '0', y: '0' }, { x: '1', y: '0' }, { x: '0.5', y: '1' }] },
      });
      const postResult = await applyMutation(tx3, orgId, actorId, postWrite, farmId);
      assert(postResult.outcome === 'rejected' && postResult.code === 'RESOURCE_ARCHIVED',
        `POST_ARCHIVE_WRITE_${postResult.outcome}_${postResult.code ?? ''}`);
      await tx3.query('ROLLBACK');
      console.log(JSON.stringify({ orderA_postArchive: 'deny-after verified: post-archive write rejected' }));
    } finally {
      await tx3.end().catch(() => {});
    }

    // ---- Order B on a second farm: archive commits first, write denied ------
    const farmBId = randomUUID();
    await migration.query(`INSERT INTO public.farms (id, organization_id, name, timezone, status, version) VALUES ($1::uuid, $2::uuid, 'Barrier farm B', 'UTC', 'active', 1)`, [farmBId, orgId]);
    await migration.query(`INSERT INTO public.farm_clocks (organization_id, farm_id, continuity_epoch, revision) VALUES ($1::uuid, $2::uuid, 1, 1)`, [orgId, farmBId]);

    // Archive must win the lock: launch it first, then the write blocks on it.
    await tx2.query('BEGIN');
    await setActor(tx2);
    const archiveB = intent('farm.archive', farmBId, {}, { baseVersion: 1 });
    const archiveBPromise = applyMutation(tx2, orgId, actorId, archiveB, farmBId);
    await new Promise((resolve) => setTimeout(resolve, 500));

    await tx1.query('BEGIN');
    await setActor(tx1);
    const zoneBId = randomUUID();
    const zoneB = intent('zone.create', zoneBId, {
      name: `Barrier zone B ${suffix}`, type: 'crop_plot',
      geometry: { points: [{ x: '0', y: '0' }, { x: '1', y: '0' }, { x: '0.5', y: '1' }] },
    });
    let zoneBResolved = false;
    const zoneBPromise = applyMutation(tx1, orgId, actorId, zoneB, farmBId).then((r) => { zoneBResolved = true; return r; });
    await new Promise((resolve) => setTimeout(resolve, 700));
    assert(zoneBResolved === false, 'ORDER_B_WRITE_NOT_BLOCKED_ON_LOCK');

    const archiveBResult = await archiveBPromise;
    assert(archiveBResult.outcome === 'applied', `ORDER_B_ARCHIVE_${archiveBResult.outcome}_${archiveBResult.code ?? ''}`);
    await tx2.query('COMMIT');
    const zoneBResult = await zoneBPromise;
    // The archive committed first: the in-flight write must see archived state
    // and be denied — not applied, not deadlocked.
    assert(zoneBResult.outcome === 'rejected' && zoneBResult.code === 'RESOURCE_ARCHIVED',
      `ORDER_B_WRITE_${zoneBResult.outcome}_${zoneBResult.code ?? ''}`);
    await tx1.query('ROLLBACK');
    const zoneRow = await migration.query(
      `SELECT count(*)::INTEGER AS n FROM public.zones WHERE organization_id=$1::uuid AND farm_id=$2::uuid AND id=$3::uuid`,
      [orgId, farmBId, zoneBId]);
    assert(zoneRow.rows[0].n === 0, 'ORDER_B_DENIED_WRITE_PERSISTED');
    console.log(JSON.stringify({ orderB: 'deny-after verified: archive committed, blocked write rejected, no row persisted' }));

    console.log(JSON.stringify({ status: 'passed', gate: 'S-07/S-18 farm-archive barrier', deadlock: false }));
  } catch (error) {
    const code = error && typeof error === 'object' && typeof error.code === 'string' && SAFE_CODE.test(error.code)
      ? error.code : 'UNEXPECTED_FAILURE';
    console.error(JSON.stringify({ status: 'failed', code, detail: error instanceof Error ? error.message.slice(0, 200) : '' }));
    process.exitCode = 1;
  } finally {
    for (const client of [tx1, tx2]) await client.query('ROLLBACK').catch(() => {});
    await migration.query(`DELETE FROM public.zones WHERE organization_id = $1::uuid`, [orgId]).catch(() => {});
    await migration.query(`DELETE FROM public.organizations WHERE id = $1::uuid`, [orgId]).catch(() => {});
    await migration.query(`DELETE FROM auth."user" WHERE id = $1`, [actorId]).catch(() => {});
    await Promise.allSettled([tx1.end(), tx2.end(), migration.end()]);
  }
}

await main();
