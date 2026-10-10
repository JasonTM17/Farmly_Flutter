import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const tenantMigrationId = '202610060002_tenant_identity';
const expectedDatabaseName = 'farmly_test_261005';
const connectionString = process.env.MIGRATION_DATABASE_URL;
const configuredDatabaseName = process.env.FARMLY_MIGRATION_DATABASE_NAME;

function assert(condition, code) {
  if (condition) return;
  const error = new Error(code);
  error.code = code;
  throw error;
}

async function expectSqlState(client, query, parameters, expectedCode) {
  const savepoint = `farmly_case_${randomUUID().replaceAll('-', '')}`;
  await client.query(`SAVEPOINT ${savepoint}`);
  let failure;
  try {
    await client.query(query, parameters);
  } catch (error) {
    failure = error;
  }
  await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
  await client.query(`RELEASE SAVEPOINT ${savepoint}`);
  assert(failure?.code === expectedCode, `${expectedCode}_EXPECTED`);
}

function targetDatabaseName(url) {
  try {
    return decodeURIComponent(new URL(url).pathname.slice(1));
  } catch {
    return null;
  }
}

async function main() {
  assert(connectionString && configuredDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_REQUIRED');
  assert(configuredDatabaseName === expectedDatabaseName, 'UNAPPROVED_MIGRATION_DATABASE');
  assert(targetDatabaseName(connectionString) === expectedDatabaseName, 'MIGRATION_DATABASE_TARGET_MISMATCH');

  const client = new Client({ connectionString });
  let transactionOpen = false;
  try {
    await client.connect();
    await client.query('BEGIN');
    transactionOpen = true;

    const authReady = await client.query("SELECT to_regclass('auth.\"user\"') IS NOT NULL AS ready");
    assert(authReady.rows[0].ready, 'AUTH_MIGRATION_REQUIRED');
    const tenantReady = await client.query("SELECT to_regclass('public.organizations') IS NOT NULL AS ready");
    if (!tenantReady.rows[0].ready) {
      const migrationSql = await readFile(new URL(`../../prisma/migrations/${tenantMigrationId}/migration.sql`, import.meta.url), 'utf8');
      await client.query(migrationSql);
    }

    const suffix = randomUUID();
    const actorId = `tenant-it-${suffix}`;
    const otherActorId = `tenant-it-other-${suffix}`;
    const unverifiedActorId = `tenant-it-unverified-${suffix}`;
    await client.query(`
      INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt")
      VALUES ($1, 'Tenant integration owner', $2, TRUE, CURRENT_TIMESTAMP),
             ($3, 'Other verified principal', $4, TRUE, CURRENT_TIMESTAMP),
             ($5, 'Unverified principal', $6, FALSE, CURRENT_TIMESTAMP)
    `, [
      actorId, `${suffix}@farmly.test`,
      otherActorId, `other-${suffix}@farmly.test`,
      unverifiedActorId, `unverified-${suffix}@farmly.test`,
    ]);

    const firstRequestId = randomUUID();
    const secondRequestId = randomUUID();
    const replayRequest = '23505';
    await expectSqlState(client,
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, firstRequestId, 'No context'], '42501');

    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const first = await client.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, firstRequestId, 'Farmly Integration One'],
    );
    assert(first.rowCount === 1 && first.rows[0].policy_version === '1', 'ORG_OWNER_FACTORY_FAILED');
    const firstOrgId = first.rows[0].organization_id;

    await expectSqlState(client,
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, firstRequestId, 'Replayed create'], replayRequest);
    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [otherActorId]);
    await expectSqlState(client,
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, randomUUID(), 'Other principal'], '42501');
    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [unverifiedActorId]);
    await expectSqlState(client,
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [unverifiedActorId, randomUUID(), 'Unverified'], '42501');

    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const secondOrg = await client.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, secondRequestId, 'Farmly Integration Two'],
    );
    const secondOrgId = secondOrg.rows[0].organization_id;

    const firstPage = await client.query(
      'SELECT * FROM public.list_my_organizations($1, $2, $3::uuid)',
      [actorId, 1, null],
    );
    assert(firstPage.rowCount === 2, 'ORG_INDEX_PAGE_BOUND_FAILED');
    const nextPage = await client.query(
      'SELECT * FROM public.list_my_organizations($1, $2, $3::uuid)',
      [actorId, 1, firstPage.rows[0].organization_id],
    );
    assert(nextPage.rowCount === 1 && nextPage.rows[0].organization_id !== firstPage.rows[0].organization_id, 'ORG_INDEX_CURSOR_FAILED');
    await expectSqlState(client,
      'SELECT * FROM public.list_my_organizations($1, $2, $3::uuid)',
      [otherActorId, 1, null], '42501');
    await expectSqlState(client,
      'SELECT * FROM public.list_my_organizations($1, $2, $3::uuid)',
      [actorId, 101, null], '22023');

    const authTenantGrants = await client.query(`
      SELECT has_table_privilege('farmly_auth_app', 'public.organizations', 'SELECT') AS can_read,
             has_function_privilege('farmly_tenant_app',
               'public.create_organization_for_verified_principal(text,uuid,text)', 'EXECUTE') AS can_create
    `);
    assert(!authTenantGrants.rows[0].can_read && authTenantGrants.rows[0].can_create, 'ROLE_GRANTS_INVALID');

    const firstFarmId = randomUUID();
    const secondFarmId = randomUUID();
    await client.query(`
      INSERT INTO public.farms (organization_id, id, name, timezone)
      VALUES ($1, $2::uuid, 'Farm One', 'Asia/Bangkok'), ($3, $4::uuid, 'Farm Two', 'Asia/Bangkok')
    `, [firstOrgId, firstFarmId, secondOrgId, secondFarmId]);
    const membership = await client.query(
      'SELECT id FROM public.organization_memberships WHERE organization_id = $1 AND user_id = $2',
      [firstOrgId, actorId],
    );
    await expectSqlState(client,
      "INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role) VALUES ($1, $2::uuid, $3::uuid, 'manager')",
      [firstOrgId, membership.rows[0].id, secondFarmId], '23503');

    await expectSqlState(client, `
      UPDATE public.organization_memberships SET role = 'admin'
      WHERE organization_id = $1 AND user_id = $2 AND role = 'owner' AND status = 'active'
    `, [firstOrgId, actorId], '23514');
    const activeOwners = await client.query(
      "SELECT count(*)::int AS count FROM public.organization_memberships WHERE organization_id = $1 AND role = 'owner' AND status = 'active'",
      [firstOrgId],
    );
    assert(activeOwners.rows[0].count === 1, 'LAST_OWNER_INVARIANT_FAILED');

    process.stdout.write(JSON.stringify({
      status: 'passed',
      database: expectedDatabaseName,
      checks: ['verified-factory', 'actor-context', 'single-owner', 'request-replay', 'org-index-pagination', 'same-org-fk', 'last-owner-guard', 'role-grants'],
    }) + '\n');
  } catch (error) {
    const code = error instanceof Error && 'code' in error && typeof error.code === 'string'
      ? error.code
      : 'TENANT_IDENTITY_TEST_FAILED';
    process.stderr.write(JSON.stringify({ status: 'failed', code }) + '\n');
    process.exitCode = 1;
  } finally {
    if (transactionOpen) await client.query('ROLLBACK').catch(() => undefined);
    await client.end().catch(() => undefined);
  }
}

await main();
