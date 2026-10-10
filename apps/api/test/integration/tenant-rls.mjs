import { randomUUID } from 'node:crypto';
import { Client, Pool } from 'pg';

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantUrl = process.env.DATABASE_URL_TENANT;
const suffix = randomUUID().replaceAll('-', '');
const privateChatTable = `_farmly_rls_private_chat_${suffix}`;

function assert(condition, code) {
  if (condition) return;
  const error = new Error(code);
  error.code = code;
  throw error;
}

function databaseName(url) {
  try {
    return decodeURIComponent(new URL(url).pathname.slice(1));
  } catch {
    return null;
  }
}

async function expectSqlState(client, query, parameters, expectedCode) {
  const transactionClient = typeof client.connect === 'function' ? await client.connect() : client;
  const savepoint = `farmly_rls_case_${randomUUID().replaceAll('-', '')}`;
  let failure;
  try {
    await transactionClient.query('BEGIN');
    await transactionClient.query(`SAVEPOINT ${savepoint}`);
    try {
      await transactionClient.query(query, parameters);
    } catch (error) {
      failure = error;
    }
    await transactionClient.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
    await transactionClient.query(`RELEASE SAVEPOINT ${savepoint}`);
    await transactionClient.query('COMMIT');
    assert(failure?.code === expectedCode, `${expectedCode}_EXPECTED`);
  } catch (error) {
    await transactionClient.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    if (transactionClient !== client) transactionClient.release();
  }
}

function sortedIds(rows) {
  return rows.map((row) => row.id).sort();
}

async function main() {
  assert(migrationUrl && tenantUrl, 'RLS_DATABASE_CONFIGURATION_REQUIRED');
  assert(databaseName(migrationUrl) === expectedDatabaseName, 'UNAPPROVED_RLS_MIGRATION_DATABASE');
  assert(databaseName(tenantUrl) === expectedDatabaseName, 'UNAPPROVED_RLS_TENANT_DATABASE');

  const migration = new Client({ connectionString: migrationUrl });
  const appPool = new Pool({ connectionString: tenantUrl, max: 1 });
  let migrationConnected = false;
  let fixtureIds;
  let privateTableCreated = false;
  let stage = 'preflight';

  try {
    await migration.connect();
    migrationConnected = true;
    const ready = await migration.query(`
      SELECT to_regprocedure('public.farmly_actor_can_read_farm(uuid,uuid)') IS NOT NULL AS ready,
             to_regclass('public.organization_memberships') IS NOT NULL AS tenant_ready
    `);
    assert(ready.rows[0].ready && ready.rows[0].tenant_ready, 'RLS_MIGRATION_REQUIRED');

    const ownerId = `rls-owner-${suffix}`;
    const memberId = `rls-member-${suffix}`;
    const viewerId = `rls-viewer-${suffix}`;
    const adminId = `rls-admin-${suffix}`;
    const otherOwnerId = `rls-other-${suffix}`;
    const isolatedId = `rls-isolated-${suffix}`;
    const actors = [ownerId, memberId, viewerId, adminId, otherOwnerId, isolatedId];
    const emails = actors.map((actorId) => `${actorId}@farmly.test`);

    await migration.query('BEGIN');
    stage = 'fixtures';
    await migration.query(`
      INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt")
      SELECT actor_id, actor_id, email, TRUE, CURRENT_TIMESTAMP
        FROM unnest($1::text[], $2::text[]) AS fixture(actor_id, email)
    `, [actors, emails]);

    const orgARequest = randomUUID();
    await migration.query("SELECT set_config('app.actor_id', $1, TRUE)", [ownerId]);
    const orgAResult = await migration.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [ownerId, orgARequest, `RLS org A ${suffix}`],
    );
    const orgA = orgAResult.rows[0].organization_id;
    const ownerMembership = orgAResult.rows[0].membership_id;

    await migration.query("SELECT set_config('app.actor_id', $1, TRUE)", [otherOwnerId]);
    const orgBResult = await migration.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [otherOwnerId, randomUUID(), `RLS org B ${suffix}`],
    );
    const orgB = orgBResult.rows[0].organization_id;
    const otherOwnerMembership = orgBResult.rows[0].membership_id;

    const memberMembership = randomUUID();
    const viewerMembership = randomUUID();
    const adminMembership = randomUUID();
    await migration.query(`
      INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status)
      VALUES ($1, $4, $5, 'member', 'active'),
             ($2, $4, $6, 'viewer', 'active'),
             ($3, $4, $7, 'admin', 'active')
    `, [memberMembership, viewerMembership, adminMembership, orgA, memberId, viewerId, adminId]);

    const farmA1 = randomUUID();
    const farmA2 = randomUUID();
    const farmB1 = randomUUID();
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone)
      VALUES ($1, $4, 'RLS Farm A1', 'Asia/Bangkok'),
             ($2, $4, 'RLS Farm A2', 'Asia/Bangkok'),
             ($3, $5, 'RLS Farm B1', 'Asia/Bangkok')
    `, [farmA1, farmA2, farmB1, orgA, orgB]);
    await migration.query(`
      INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
      VALUES ($1, $2, $3, 'worker'), ($1, $4, $3, 'manager')
    `, [orgA, memberMembership, farmA1, viewerMembership]);

    const privateChatIdentifier = `public."${privateChatTable}"`;
    await migration.query(`
      CREATE TABLE ${privateChatIdentifier} (
        id UUID PRIMARY KEY,
        organization_id UUID NOT NULL,
        farm_id UUID NOT NULL,
        owner_id TEXT NOT NULL REFERENCES auth."user"(id) ON DELETE CASCADE,
        CONSTRAINT ${privateChatTable}_farm_fkey
          FOREIGN KEY (organization_id, farm_id) REFERENCES public.farms(organization_id, id) ON DELETE CASCADE
      )
    `);
    privateTableCreated = true;
    await migration.query(`ALTER TABLE ${privateChatIdentifier} ENABLE ROW LEVEL SECURITY`);
    await migration.query(`ALTER TABLE ${privateChatIdentifier} FORCE ROW LEVEL SECURITY`);
    await migration.query(`
      CREATE POLICY migration_access ON ${privateChatIdentifier}
        TO farmly_migration USING (TRUE) WITH CHECK (TRUE)
    `);
    await migration.query(`
      CREATE POLICY owner_private_read ON ${privateChatIdentifier}
        FOR SELECT TO farmly_tenant_app
        USING (
          owner_id = NULLIF(current_setting('app.actor_id', TRUE), '')
          AND public.farmly_actor_can_read_farm(organization_id, farm_id)
        )
    `);
    await migration.query(`GRANT SELECT ON TABLE ${privateChatIdentifier} TO farmly_tenant_app`);
    await migration.query(`
      INSERT INTO ${privateChatIdentifier} (id, organization_id, farm_id, owner_id)
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4)
    `, [randomUUID(), orgA, farmA1, ownerId]);
    await migration.query('COMMIT');

    fixtureIds = { organizations: [orgA, orgB], actors, ownerId, memberId, viewerId, adminId, farmA1, farmA2, farmB1, memberMembership, viewerMembership, ownerMembership, otherOwnerMembership, adminMembership };

    const role = await appPool.query(`
      SELECT current_user AS role_name, role.rolsuper, role.rolbypassrls, role.rolcreatedb, role.rolcreaterole,
             has_schema_privilege(current_user, 'public', 'CREATE') AS can_create_in_public,
             has_database_privilege(current_user, current_database(), 'CREATE') AS can_create_database,
             has_database_privilege(current_user, current_database(), 'TEMP') AS can_create_temp
        FROM pg_catalog.pg_roles AS role
       WHERE role.rolname = current_user
    `);
    stage = 'role-check';
    assert(role.rows[0]?.role_name === 'farmly_tenant_app', 'TENANT_DATABASE_ROLE_MISMATCH');
    assert(!role.rows[0].rolsuper && !role.rows[0].rolbypassrls && !role.rows[0].rolcreatedb && !role.rows[0].rolcreaterole, 'TENANT_ROLE_PRIVILEGES_INVALID');
    assert(!role.rows[0].can_create_in_public && !role.rows[0].can_create_database && !role.rows[0].can_create_temp, 'TENANT_ROLE_DDL_PRIVILEGE_PRESENT');
    assert(!(await appPool.query("SELECT has_table_privilege(current_user, 'public.farms', 'UPDATE') AS can_update")).rows[0].can_update, 'TENANT_ROLE_WRITE_PRIVILEGE_PRESENT');

    const unscoped = await appPool.query(`
      SELECT (SELECT count(*) FROM public.organizations)::int AS organizations,
             (SELECT count(*) FROM public.farms)::int AS farms,
             (SELECT count(*) FROM public.organization_memberships)::int AS memberships,
             (SELECT count(*) FROM public.farm_grants)::int AS grants
    `);
    stage = 'missing-context';
    assert(Object.values(unscoped.rows[0]).every((count) => count === 0), 'MISSING_CONTEXT_RETURNED_ROWS');

    await expectSqlState(appPool,
      `CREATE TABLE public.${privateChatTable}_ddl_denied (id INTEGER)`, [], '42501');
    stage = 'no-ddl';
    await expectSqlState(appPool,
      `CREATE TEMPORARY TABLE ${privateChatTable}_temp_denied (id INTEGER)`, [], '42501');

    stage = 'organization-scope';
    const visibleOrgs = await withActor(appPool, fixtureIds.ownerId, (client) => client.query(
      'SELECT id FROM public.organizations WHERE id = ANY($1::uuid[])', [fixtureIds.organizations],
    ));
    assert(sortedIds(visibleOrgs.rows).join(',') === [fixtureIds.organizations[0]].sort().join(','), 'CROSS_ORG_ROWS_VISIBLE');

    stage = 'farm-grant-scope';
    const memberFarms = await withActor(appPool, fixtureIds.memberId, (client) => client.query(
      'SELECT id FROM public.farms WHERE id = ANY($1::uuid[])', [[fixtureIds.farmA1, fixtureIds.farmA2, fixtureIds.farmB1]],
    ));
    assert(sortedIds(memberFarms.rows).join(',') === fixtureIds.farmA1, 'UNGRANTED_OR_CROSS_ORG_FARM_VISIBLE');
    const memberGrants = await withActor(appPool, fixtureIds.memberId, (client) => client.query(
      'SELECT membership_id FROM public.farm_grants WHERE organization_id = $1', [fixtureIds.organizations[0]],
    ));
    assert(memberGrants.rowCount === 1 && memberGrants.rows[0].membership_id === fixtureIds.memberMembership, 'OTHER_MEMBERS_GRANTS_VISIBLE');

    stage = 'viewer-ceiling';
    const viewerFarms = await withActor(appPool, fixtureIds.viewerId, (client) => client.query(
      'SELECT id FROM public.farms WHERE id = ANY($1::uuid[])', [[fixtureIds.farmA1, fixtureIds.farmA2]],
    ));
    assert(viewerFarms.rowCount === 1 && viewerFarms.rows[0].id === fixtureIds.farmA1, 'VIEWER_GRANT_CEILING_INVALID');
    const viewerUpdatePrivilege = await appPool.query("SELECT has_table_privilege(current_user, 'public.farms', 'UPDATE') AS allowed");
    assert(!viewerUpdatePrivilege.rows[0].allowed, 'VIEWER_WRITE_PRIVILEGE_PRESENT');

    stage = 'admin-memberships';
    const adminMemberships = await withActor(appPool, fixtureIds.adminId, (client) => client.query(
      'SELECT user_id FROM public.organization_memberships WHERE organization_id = $1', [fixtureIds.organizations[0]],
    ));
    assert(adminMemberships.rowCount === 4, 'ORG_ADMIN_MEMBERSHIP_VISIBILITY_INVALID');

    stage = 'private-chat-owner';
    const adminPrivateChat = await withActor(appPool, fixtureIds.adminId, (client) => client.query(
      `SELECT id FROM ${privateChatIdentifier}`,
    ));
    assert(adminPrivateChat.rowCount === 0, 'ORG_ADMIN_PRIVATE_CHAT_BYPASS');
    const ownerPrivateChat = await withActor(appPool, fixtureIds.ownerId, (client) => client.query(
      `SELECT id FROM ${privateChatIdentifier}`,
    ));
    assert(ownerPrivateChat.rowCount === 1, 'PRIVATE_OWNER_CANNOT_READ_OWN_CHAT');

    stage = 'pool-reset';
    const afterScopedUse = await appPool.query(`
      SELECT (SELECT count(*) FROM public.organizations)::int AS organizations,
             NULLIF(current_setting('app.actor_id', TRUE), '') IS NULL AS actor_cleared
    `);
    assert(afterScopedUse.rows[0].organizations === 0 && afterScopedUse.rows[0].actor_cleared, 'POOL_CONTEXT_LEAKED');

    process.stdout.write(JSON.stringify({
      status: 'passed',
      database: expectedDatabaseName,
      role: 'farmly_tenant_app',
      checks: [
        'missing-context-deny', 'cross-org-deny', 'ungranted-farm-deny', 'own-grants-only',
        'viewer-read-only-ceiling', 'org-admin-membership-read', 'private-chat-owner-policy',
        'pool-context-reset', 'no-ddl-or-bypassrls',
      ],
    }) + '\n');
  } catch (error) {
    if (migrationConnected) await migration.query('ROLLBACK').catch(() => undefined);
    const code = error instanceof Error && 'code' in error && typeof error.code === 'string'
      ? error.code
      : 'TENANT_RLS_TEST_FAILED';
    process.stderr.write(JSON.stringify({ status: 'failed', stage, code }) + '\n');
    process.exitCode = 1;
  } finally {
    await appPool.end().catch(() => undefined);
    if (migrationConnected) {
      if (privateTableCreated) await migration.query(`DROP TABLE IF EXISTS public."${privateChatTable}"`).catch(() => undefined);
      if (fixtureIds) {
        await migration.query('BEGIN').catch(() => undefined);
        await migration.query('DELETE FROM public.organizations WHERE id = ANY($1::uuid[])', [fixtureIds.organizations]).catch(() => undefined);
        await migration.query('DELETE FROM auth."user" WHERE id = ANY($1::text[])', [fixtureIds.actors]).catch(() => undefined);
        await migration.query('COMMIT').catch(() => undefined);
      }
      await migration.end().catch(() => undefined);
    }
  }
}

async function withActor(pool, actorId, callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

await main();
