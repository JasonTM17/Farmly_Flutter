import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { randomUUID } from 'node:crypto';
import { Client } from 'pg';

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const configuredDatabaseName = process.env.FARMLY_TEST_DATABASE_NAME;
let currentStage = 'startup';

function assert(condition, code) {
  if (!condition) throw Object.assign(new Error(code), { code });
}

function assertTarget(url, username) {
  let parsed;
  try { parsed = new URL(url); } catch { assert(false, 'DATABASE_URL_INVALID'); }
  assert(parsed.hostname === 'postgres', 'DATABASE_HOST_INVALID');
  assert(decodeURIComponent(parsed.pathname.slice(1)) === expectedDatabaseName, 'DATABASE_NAME_INVALID');
  if (username) assert(decodeURIComponent(parsed.username) === username, 'DATABASE_ROLE_INVALID');
}

function tenantConnectionString(applicationName) {
  assert(tenantPassword, 'TENANT_ROLE_PASSWORD_REQUIRED');
  const encodedPassword = encodeURIComponent(tenantPassword);
  const encodedApplicationName = encodeURIComponent(applicationName);
  return `postgresql://farmly_tenant_app:${encodedPassword}@postgres:5432/${expectedDatabaseName}?application_name=${encodedApplicationName}`;
}

function withApplicationName(connectionString, applicationName) {
  const url = new URL(connectionString);
  url.searchParams.set('application_name', applicationName);
  return url.toString();
}

async function withActor(client, actorId, operation) {
  await client.query('BEGIN');
  try {
    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function expectServiceError(operation, status, code, failureCode) {
  let caught;
  try { await operation(); } catch (error) { caught = error; }
  const actualStatus = caught?.getStatus?.() ?? 'none';
  const actualCode = caught?.getResponse?.()?.code ?? 'none';
  const actualRawCode = typeof caught?.code === 'string' ? caught.code : 'none';
  const adapterError = caught?.meta?.driverAdapterError;
  const databaseCause = adapterError?.cause;
  const safeState = (value) => typeof value === 'string' && /^[0-9A-Z]{5}$/.test(value) ? value : 'none';
  const metaCode = safeState(caught?.meta?.code);
  const adapterCode = safeState(adapterError?.code);
  const causeCode = safeState(databaseCause?.code);
  const causeOriginalCode = safeState(databaseCause?.originalCode);
  const assertCode = `${failureCode}_STATUS_EXPECTED_${status}_ACTUAL_${actualStatus}_RESPONSE_${actualCode}_RAW_${actualRawCode}_META_${metaCode}_ADAPTER_${adapterCode}_CAUSE_${causeCode}_CAUSE_ORIGINAL_${causeOriginalCode}_THREW_${Boolean(caught)}`;
  assert(actualStatus === status, assertCode);
  assert(actualCode === code, `${failureCode}_CODE_EXPECTED_${code}_ACTUAL_${actualCode}`);
}

async function expectSqlState(operation, sqlState, failureCode) {
  let caught;
  try { await operation(); } catch (error) { caught = error; }
  assert(caught?.code === sqlState, failureCode);
}

function verifiedPrincipal(user) {
  return {
    actorId: user.id,
    email: user.email,
    displayName: 'Membership integration user',
    sessionId: randomUUID(),
    sessionExpiresAt: new Date(Date.now() + 60_000),
  };
}

async function insertVerifiedUsers(migration, users) {
  const values = [];
  const rows = users.map(({ id, email }, index) => {
    const offset = index * 4;
    values.push(id, email, true, new Date());
    return `($${offset + 1}, 'Membership test user', $${offset + 2}, $${offset + 3}, $${offset + 4})`;
  });
  await migration.query(`
    INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt")
    VALUES ${rows.join(', ')}
  `, values);
}

async function createOrganization(migration, actorId, name) {
  await migration.query('BEGIN');
  try {
    await migration.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const result = await migration.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, randomUUID(), name],
    );
    await migration.query('COMMIT');
    return result.rows[0].organization_id;
  } catch (error) {
    await migration.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function waitForLockWaits(migration, applicationNames, lockHolderPid) {
  let latestRows = [];
  for (let attempt = 0; attempt < 250; attempt += 1) {
    const result = await migration.query(`
      SELECT pid,
             application_name,
             wait_event_type,
             pg_catalog.pg_blocking_pids(pid) AS blocking_pids
        FROM pg_catalog.pg_stat_activity
       WHERE application_name = ANY($1::text[])
    `, [applicationNames]);
    latestRows = result.rows;
    const waitsOnLockHolder = (row, seen = new Set()) => {
      if (!row || seen.has(row.pid)) return false;
      if (row.blocking_pids.includes(lockHolderPid)) return true;
      seen.add(row.pid);
      return row.blocking_pids.some((blockerPid) => {
        const blocker = result.rows.find((candidate) => candidate.pid === blockerPid);
        return waitsOnLockHolder(blocker, new Set(seen));
      });
    };
    if (applicationNames.every((name) => {
      const row = result.rows.find((candidate) => candidate.application_name === name);
      return waitsOnLockHolder(row);
    })) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const prefixes = applicationNames.map((name) => `${name.slice(0, -36)}%`);
  const observed = await migration.query(`
    SELECT pid, application_name, wait_event_type, pg_catalog.pg_blocking_pids(pid) AS blocking_pids
      FROM pg_catalog.pg_stat_activity
     WHERE application_name LIKE ANY($1::text[])
  `, [prefixes]);
  const diagnostics = prefixes.map((prefix, index) => {
    const rows = observed.rows.filter((row) => row.application_name.startsWith(prefix.slice(0, -1)));
    const exact = latestRows.some((row) => row.application_name === applicationNames[index]);
    const locked = rows.filter((row) => row.wait_event_type === 'Lock').length;
    const blocked = rows.filter((row) => row.blocking_pids.includes(lockHolderPid)).length;
    const otherBlocked = rows.filter((row) => row.blocking_pids.length > 0 && !row.blocking_pids.includes(lockHolderPid)).length;
    const otherWait = rows.filter((row) => row.wait_event_type && row.wait_event_type !== 'Lock').length;
    return `A${index}_N${rows.length}_EXACT${Number(exact)}_LOCK${locked}_BLOCKED${blocked}_OTHERBLOCK${otherBlocked}_OTHERWAIT${otherWait}`;
  }).join('_');
  const code = `MEMBERSHIP_LOCK_WAIT_NOT_OBSERVED_${diagnostics}`;
  throw Object.assign(new Error(code), { code });
}

async function main() {
  assert(migrationUrl && configuredDatabaseName === expectedDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assertTarget(migrationUrl, 'farmly_migration');

  const suffix = randomUUID();
  const applicationA = `farmly-membership-a-${suffix}`;
  const applicationB = `farmly-membership-b-${suffix}`;
  const serviceApplicationA = `farmly-membership-svc-a-${suffix}`;
  const serviceApplicationB = `farmly-membership-svc-b-${suffix}`;
  const migration = new Client({ connectionString: withApplicationName(migrationUrl, `farmly-membership-migration-${suffix}`) });
  const appA = new Client({ connectionString: tenantConnectionString(applicationA) });
  const appB = new Client({ connectionString: tenantConnectionString(applicationB) });
  const users = [
    { id: `member-owner-a-${suffix}`, email: `owner-a-${suffix}@farmly.test` },
    { id: `member-owner-b-${suffix}`, email: `owner-b-${suffix}@farmly.test` },
    { id: `member-admin-a-${suffix}`, email: `admin-a-${suffix}@farmly.test` },
    { id: `member-target-a-${suffix}`, email: `target-a-${suffix}@farmly.test` },
    { id: `member-owner-c-${suffix}`, email: `owner-c-${suffix}@farmly.test` },
    { id: `member-target-b-${suffix}`, email: `target-b-${suffix}@farmly.test` },
    { id: `member-target-c-${suffix}`, email: `target-c-${suffix}@farmly.test` },
  ];
  assert([applicationA, applicationB, serviceApplicationA, serviceApplicationB].every((name) => Buffer.byteLength(name, 'utf8') <= 63), 'POSTGRES_APPLICATION_NAME_TOO_LONG');
  const organizationIds = [];
  const tenantServices = [];
  let operationError = null;
  let operationStage = null;
  let cleanupError = null;
  let membershipsA;
  let membershipsB;
  let organizationsA;
  let organizationsB;
  let membershipHttpApp;

  try {
    currentStage = 'connect-and-load-service';
    await Promise.all([migration.connect(), appA.connect(), appB.connect()]);
    const [
      { TenantDatabaseService },
      { OrganizationMembershipsService },
      { OrganizationsService },
      { OrganizationMembershipsController },
      { VerifiedSessionGuard },
      { FARMLY_AUTH },
      { FarmlyHttpExceptionFilter },
    ] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/organizations/organization-memberships.service.js', import.meta.url)),
      import(new URL('../../dist/organizations/organizations.service.js', import.meta.url)),
      import(new URL('../../dist/organizations/organization-memberships.controller.js', import.meta.url)),
      import(new URL('../../dist/auth/verified-session.guard.js', import.meta.url)),
      import(new URL('../../dist/auth/auth.module.js', import.meta.url)),
      import(new URL('../../dist/common/farmly-http-exception.filter.js', import.meta.url)),
    ]);
    const tenantA = new TenantDatabaseService({
      get: (key) => key === 'farmlyEnvironment' ? { databaseUrlTenant: tenantConnectionString(serviceApplicationA) } : undefined,
    });
    const tenantB = new TenantDatabaseService({
      get: (key) => key === 'farmlyEnvironment' ? { databaseUrlTenant: tenantConnectionString(serviceApplicationB) } : undefined,
    });
    tenantServices.push(tenantA, tenantB);
    await Promise.all(tenantServices.map((service) => service.onModuleInit()));
    membershipsA = new OrganizationMembershipsService(tenantA);
    membershipsB = new OrganizationMembershipsService(tenantB);
    const cursorConfig = {
      get: (key) => key === 'farmlyEnvironment' ? { cursorSigningKey: process.env.CURSOR_SIGNING_KEY } : undefined,
    };
    organizationsA = new OrganizationsService(tenantA, cursorConfig);
    organizationsB = new OrganizationsService(tenantB, cursorConfig);

    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'MIGRATION_DATABASE_IDENTITY_INVALID');
    const ready = await migration.query(`
      SELECT to_regprocedure('public.list_organization_memberships(uuid,integer,uuid)') IS NOT NULL AS list_ready,
             to_regprocedure('public.update_organization_membership(uuid,uuid,uuid,text,public.organization_role,jsonb)') IS NOT NULL AS update_ready,
             to_regprocedure('public.remove_organization_membership(uuid,uuid)') IS NOT NULL AS remove_ready,
             to_regprocedure('public.transfer_organization_ownership(uuid,uuid,text,uuid,boolean)') IS NOT NULL AS transfer_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060007_organization_memberships') AS migration_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060008_ownership_transfer_replay') AS transfer_replay_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060009_qualify_membership_actor') AS actor_variable_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060010_validate_membership_grants') AS exact_grant_validation_ready
    `);
    assert(Object.values(ready.rows[0]).every(Boolean), 'ORGANIZATION_MEMBERSHIPS_MIGRATION_REQUIRED');

    currentStage = 'seed-fixtures';
    await insertVerifiedUsers(migration, users);
    const organizationA = await createOrganization(migration, users[0].id, `Membership Org A ${suffix}`);
    organizationIds.push(organizationA);
    const organizationB = await createOrganization(migration, users[4].id, `Membership Org B ${suffix}`);
    organizationIds.push(organizationB);
    const highPolicyVersion = '9007199254740993';
    await migration.query(
      'UPDATE public.organizations SET policy_version = $2::bigint WHERE id = $1::uuid',
      [organizationB, highPolicyVersion],
    );
    const farmA = randomUUID();
    const farmA2 = randomUUID();
    const farmB = randomUUID();
    const directoryFarmIdsB = [farmB, ...Array.from({ length: 100 }, () => randomUUID())];
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone)
      VALUES ($1::uuid, $2::uuid, 'Membership Farm A', 'Asia/Ho_Chi_Minh'),
             ($3::uuid, $2::uuid, 'Membership Farm A2', 'Asia/Ho_Chi_Minh')
    `, [farmA, organizationA, farmA2]);
    const directoryFarmValues = [];
    const directoryFarmRows = directoryFarmIdsB.map((farmId, index) => {
      const offset = index * 4;
      directoryFarmValues.push(farmId, organizationB, `Directory Farm ${index}`, 'Asia/Ho_Chi_Minh');
      return `($${offset + 1}::uuid, $${offset + 2}::uuid, $${offset + 3}, $${offset + 4})`;
    });
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone)
      VALUES ${directoryFarmRows.join(', ')}
    `, directoryFarmValues);
    const seeded = await migration.query(`
      INSERT INTO public.organization_memberships (organization_id, user_id, role, status)
      VALUES ($1::uuid, $2, 'owner', 'active'),
             ($1::uuid, $3, 'admin', 'active'),
             ($1::uuid, $4, 'member', 'active'),
             ($5::uuid, $6, 'member', 'active'),
             ($5::uuid, $7, 'member', 'active')
      RETURNING organization_id, user_id, id, role
    `, [organizationA, users[1].id, users[2].id, users[3].id, organizationB, users[5].id, users[6].id]);
    const membershipId = (organizationId, userId) => {
      const row = seeded.rows.find((item) => item.organization_id === organizationId && item.user_id === userId);
      assert(row?.id, 'FIXTURE_MEMBERSHIP_MISSING');
      return row.id;
    };
    const initialOwner = await migration.query(
      'SELECT id FROM public.organization_memberships WHERE organization_id = $1::uuid AND user_id = $2',
      [organizationA, users[0].id],
    );
    const ownerAId = initialOwner.rows[0]?.id;
    assert(ownerAId, 'INITIAL_OWNER_MEMBERSHIP_MISSING');
    const initialOwnerB = await migration.query(
      'SELECT id FROM public.organization_memberships WHERE organization_id = $1::uuid AND user_id = $2',
      [organizationB, users[4].id],
    );
    const ownerCId = initialOwnerB.rows[0]?.id;
    assert(ownerCId, 'SECOND_INITIAL_OWNER_MEMBERSHIP_MISSING');
    const ownerBId = membershipId(organizationA, users[1].id);
    const adminAId = membershipId(organizationA, users[2].id);
    const memberAId = membershipId(organizationA, users[3].id);
    const targetBId = membershipId(organizationB, users[5].id);
    const targetCId = membershipId(organizationB, users[6].id);
    await migration.query(`
      INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
      VALUES ($1::uuid, $2::uuid, $3::uuid, 'manager'),
             ($1::uuid, $4::uuid, $3::uuid, 'worker'),
             ($5::uuid, $6::uuid, $7::uuid, 'worker')
    `, [organizationA, memberAId, farmA, adminAId, organizationB, targetBId, farmB]);

    currentStage = 'roster-pagination-and-authorization';
    const owner = verifiedPrincipal(users[0]);
    const rosterFirst = await membershipsA.listFor(owner, organizationA, 2, null);
    assert(rosterFirst.data.memberships.length === 2 && rosterFirst.page.hasMore && rosterFirst.page.nextCursor, 'MEMBERSHIP_ROSTER_FIRST_PAGE_FAILED');
    assert(rosterFirst.meta.scopePolicyVersion === '1', 'MEMBERSHIP_ROSTER_SCOPE_POLICY_VERSION_MISSING');
    assert(rosterFirst.data.memberships.every((membership) => !('email' in membership) && !('displayName' in membership)), 'MEMBERSHIP_ROSTER_EXPOSED_PROFILE_PII');
    const rosterSecond = await membershipsA.listFor(owner, organizationA, 2, rosterFirst.page.nextCursor);
    assert(rosterSecond.data.memberships.length === 2 && !rosterSecond.page.hasMore, 'MEMBERSHIP_ROSTER_CURSOR_FAILED');
    assert(rosterFirst.data.memberships.at(-1).id < rosterSecond.data.memberships[0].id, 'MEMBERSHIP_ROSTER_CURSOR_ORDER_UNSTABLE');
    const memberView = [...rosterFirst.data.memberships, ...rosterSecond.data.memberships].find((row) => row.id === memberAId);
    assert(memberView?.userId === users[3].id && memberView.role === 'member' && memberView.status === 'active', 'MEMBERSHIP_ROSTER_VIEW_INCOMPLETE');
    assert(memberView.farmGrants.length === 1 && memberView.farmGrants[0].farmId === farmA && memberView.farmGrants[0].role === 'manager', 'MEMBERSHIP_ROSTER_GRANTS_MISSING');
    const adminRoster = await membershipsA.listFor(verifiedPrincipal(users[2]), organizationA, 25, null);
    assert(adminRoster.data.memberships.length === 4, 'ADMIN_MEMBERSHIP_ROSTER_DENIED');
    const largeVersionRoster = await membershipsB.listFor(verifiedPrincipal(users[4]), organizationB, 25, null);
    assert(largeVersionRoster.meta.scopePolicyVersion === highPolicyVersion, 'ROSTER_BIGINT_SCOPE_POLICY_VERSION_LOST_PRECISION');
    await expectServiceError(
      () => membershipsA.listFor(verifiedPrincipal(users[3]), organizationA, 25, null),
      403, 'PERMISSION_DENIED', 'MEMBER_LISTED_ROSTER',
    );
    await expectServiceError(
      () => membershipsA.listFor(owner, organizationB, 25, null),
      403, 'PERMISSION_DENIED', 'CROSS_ORGANIZATION_ROSTER_DISCLOSED',
    );

    currentStage = 'rls-farm-directory-and-bigint-wire-version';
    const ownerDirectoryA = await organizationsA.farmDirectoryFor(owner, organizationA, null, null);
    assert(ownerDirectoryA.scopePolicyVersion === '1' && ownerDirectoryA.continuityEpoch === '1', 'FARM_DIRECTORY_SCOPE_METADATA_MISSING');
    assert(ownerDirectoryA.farms.length === 2 && ownerDirectoryA.farms.every((farm) => farm.grantRole === 'owner'), 'OWNER_FARM_DIRECTORY_INCOMPLETE');
    const memberDirectoryA = await organizationsA.farmDirectoryFor(verifiedPrincipal(users[3]), organizationA, null, null);
    assert(memberDirectoryA.farms.length === 1 && memberDirectoryA.farms[0].farmId === farmA && memberDirectoryA.farms[0].grantRole === 'manager', 'FARM_DIRECTORY_LEAKED_UNGRANTED_FARM');
    assert(memberDirectoryA.farms[0].farmName === 'Membership Farm A', 'FARM_DIRECTORY_FARM_NAME_MISSING');
    const ownerB = verifiedPrincipal(users[4]);
    const ownerDirectoryB = await organizationsB.farmDirectoryFor(ownerB, organizationB, 100, null);
    assert(ownerDirectoryB.scopePolicyVersion === highPolicyVersion, 'FARM_DIRECTORY_BIGINT_SCOPE_POLICY_VERSION_LOST_PRECISION');
    assert(ownerDirectoryB.farms.length === 100 && ownerDirectoryB.nextCursor, 'FARM_DIRECTORY_FIRST_PAGE_BOUNDARY_INVALID');
    assert(ownerDirectoryB.farms.every((farm) => farm.grantRole === 'owner'), 'OWNER_FARM_DIRECTORY_SCOPE_INVALID');
    const ownerDirectoryBSecond = await organizationsB.farmDirectoryFor(ownerB, organizationB, null, ownerDirectoryB.nextCursor);
    assert(ownerDirectoryBSecond.farms.length === 1 && !ownerDirectoryBSecond.nextCursor, 'FARM_DIRECTORY_SECOND_PAGE_BOUNDARY_INVALID');
    assert(ownerDirectoryBSecond.scopePolicyVersion === ownerDirectoryB.scopePolicyVersion
      && ownerDirectoryBSecond.continuityEpoch === ownerDirectoryB.continuityEpoch, 'FARM_DIRECTORY_PAGE_SCOPE_DRIFTED');
    const ownerDirectoryFarmIds = [...ownerDirectoryB.farms, ...ownerDirectoryBSecond.farms].map((farm) => farm.farmId);
    assert(JSON.stringify(ownerDirectoryFarmIds) === JSON.stringify([...directoryFarmIdsB].sort()), 'FARM_DIRECTORY_PAGINATION_OMITTED_DUPLICATED_OR_UNORDERED_FARMS');
    await expectServiceError(
      () => organizationsA.farmDirectoryFor(owner, organizationA, null, ownerDirectoryB.nextCursor),
      410, 'CURSOR_EXPIRED', 'CROSS_ORGANIZATION_FARM_DIRECTORY_CURSOR_ACCEPTED',
    );
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(verifiedPrincipal(users[5]), organizationB, null, ownerDirectoryB.nextCursor),
      410, 'CURSOR_EXPIRED', 'CROSS_ACTOR_FARM_DIRECTORY_CURSOR_ACCEPTED',
    );
    const [encodedCursorPayload, encodedCursorSignature] = ownerDirectoryB.nextCursor.split('.');
    const tamperedCursor = `${encodedCursorPayload[0] === 'A' ? 'B' : 'A'}${encodedCursorPayload.slice(1)}.${encodedCursorSignature}`;
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(ownerB, organizationB, null, tamperedCursor),
      410, 'CURSOR_EXPIRED', 'TAMPERED_FARM_DIRECTORY_CURSOR_ACCEPTED',
    );
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(ownerB, organizationB, 25, ownerDirectoryB.nextCursor),
      410, 'CURSOR_EXPIRED', 'FARM_DIRECTORY_CURSOR_PAGE_SIZE_CHANGED',
    );
    await migration.query('UPDATE public.organizations SET policy_version = policy_version + 1 WHERE id = $1::uuid', [organizationB]);
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(ownerB, organizationB, null, ownerDirectoryB.nextCursor),
      410, 'CURSOR_EXPIRED', 'STALE_POLICY_VERSION_FARM_DIRECTORY_CURSOR_ACCEPTED',
    );
    const afterPolicyRestart = await organizationsB.farmDirectoryFor(ownerB, organizationB, 100, null);
    assert(afterPolicyRestart.scopePolicyVersion === (BigInt(highPolicyVersion) + 1n).toString(), 'FARM_DIRECTORY_POLICY_VERSION_RESTART_INVALID');
    await migration.query('UPDATE public.organizations SET continuity_epoch = continuity_epoch + 1 WHERE id = $1::uuid', [organizationB]);
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(ownerB, organizationB, null, afterPolicyRestart.nextCursor),
      410, 'CURSOR_EXPIRED', 'STALE_CONTINUITY_EPOCH_FARM_DIRECTORY_CURSOR_ACCEPTED',
    );
    const restartedDirectory = await organizationsB.farmDirectoryFor(ownerB, organizationB, 100, null);
    const restartedDirectorySecond = await organizationsB.farmDirectoryFor(ownerB, organizationB, null, restartedDirectory.nextCursor);
    assert(restartedDirectory.continuityEpoch === '2' && restartedDirectorySecond.continuityEpoch === '2', 'FARM_DIRECTORY_EPOCH_RESTART_INVALID');
    assert(JSON.stringify([...restartedDirectory.farms, ...restartedDirectorySecond.farms].map((farm) => farm.farmId))
      === JSON.stringify([...directoryFarmIdsB].sort()), 'FARM_DIRECTORY_RESTART_DID_NOT_REBUILD_COMPLETE_MANIFEST');
    const workerDirectoryB = await organizationsB.farmDirectoryFor(verifiedPrincipal(users[5]), organizationB, null, null);
    assert(workerDirectoryB.farms.length === 1 && workerDirectoryB.farms[0].grantRole === 'worker', 'FARM_DIRECTORY_GRANT_ROLE_MISSING');
    const ungrantedDirectoryB = await organizationsB.farmDirectoryFor(verifiedPrincipal(users[6]), organizationB, null, null);
    assert(ungrantedDirectoryB.farms.length === 0
      && ungrantedDirectoryB.scopePolicyVersion === (BigInt(highPolicyVersion) + 1n).toString(), 'FARM_DIRECTORY_UNGRANTED_MEMBER_SCOPE_LEAKED');
    await expectServiceError(
      () => organizationsB.farmDirectoryFor(owner, organizationB, null, null),
      403, 'ACCESS_REVOKED', 'CROSS_ORGANIZATION_FARM_DIRECTORY_DISCLOSED',
    );

    currentStage = 'role-grant-replacement-and-replay';
    const patchOperationId = randomUUID();
    const replacement = { role: 'viewer', farmGrants: [{ farmId: farmA, role: 'viewer' }, { farmId: farmA2, role: 'viewer' }] };
    const patched = await membershipsA.updateFor(verifiedPrincipal(users[2]), organizationA, memberAId, patchOperationId, replacement);
    assert(patched.data.membership.role === 'viewer' && patched.data.membership.version === 2, 'MEMBERSHIP_ROLE_REPLACEMENT_FAILED');
    assert(patched.data.membership.farmGrants.length === 2 && patched.data.policyVersion === '2' && patched.data.changed, 'MEMBERSHIP_GRANT_REPLACEMENT_FAILED');
    const emptyRosterAfterPatch = await membershipsA.listFor(owner, organizationA, 25, 'ffffffff-ffff-ffff-ffff-ffffffffffff');
    assert(emptyRosterAfterPatch.data.memberships.length === 0 && emptyRosterAfterPatch.meta.scopePolicyVersion === '2', 'EMPTY_MEMBERSHIP_PAGE_LOST_SCOPE_POLICY_VERSION');
    const replayed = await membershipsA.updateFor(verifiedPrincipal(users[2]), organizationA, memberAId, patchOperationId, replacement);
    assert(replayed.data.replayed && replayed.data.policyVersion === '2', 'MEMBERSHIP_PATCH_REPLAY_FAILED');
    await expectServiceError(
      () => membershipsA.updateFor(verifiedPrincipal(users[2]), organizationA, memberAId, patchOperationId, { role: 'member', farmGrants: [] }),
      409, 'OPERATION_ID_REUSED', 'MEMBERSHIP_OPERATION_ID_REUSE_ACCEPTED',
    );
    await expectServiceError(
      () => membershipsA.updateFor(verifiedPrincipal(users[2]), organizationA, ownerAId, randomUUID(), { role: 'admin', farmGrants: [] }),
      403, 'PERMISSION_DENIED', 'ADMIN_MODIFIED_OWNER',
    );
    await expectSqlState(
      () => withActor(appA, users[2].id, (client) => client.query(
        `SELECT * FROM public.update_organization_membership(
          $1::uuid, $2::uuid, $3::uuid, $4, 'owner'::public.organization_role, '[]'::jsonb
        )`,
        [organizationA, memberAId, randomUUID(), '3'.repeat(64)],
      )),
      '22023', 'ADMIN_OWNER_ESCALATION_ACCEPTED',
    );
    await expectServiceError(
      () => membershipsA.updateFor(owner, organizationA, memberAId, randomUUID(), { role: 'member', farmGrants: [{ farmId: farmB, role: 'worker' }] }),
      400, 'MEMBERSHIP_REQUEST_INVALID', 'CROSS_ORGANIZATION_GRANT_ACCEPTED',
    );
    await expectServiceError(
      () => membershipsA.updateFor(owner, organizationA, memberAId, randomUUID(), { role: 'viewer', farmGrants: [{ farmId: farmA, role: 'manager' }] }),
      400, 'MEMBERSHIP_REQUEST_INVALID', 'VIEWER_WRITE_GRANT_ACCEPTED',
    );
    await expectSqlState(
      () => withActor(appA, owner.actorId, (client) => client.query(
        `SELECT * FROM public.update_organization_membership(
          $1::uuid, $2::uuid, $3::uuid, $4, $5::public.organization_role, $6::jsonb
        )`,
        [organizationA, memberAId, randomUUID(), '0'.repeat(64), 'viewer', JSON.stringify([{ farmId: farmA, role: 'viewer', extra: true }])],
      )),
      '22023', 'EXTRA_MEMBERSHIP_GRANT_KEY_ACCEPTED',
    );

    currentStage = 'membership-removal-clears-grants';
    const removed = await membershipsA.removeFor(owner, organizationA, memberAId);
    assert(removed.data.membership.status === 'removed' && removed.data.membership.farmGrants.length === 0 && removed.data.changed, 'MEMBERSHIP_REMOVAL_FAILED');
    const grantCount = await migration.query('SELECT count(*)::INTEGER AS count FROM public.farm_grants WHERE organization_id = $1::uuid AND membership_id = $2::uuid', [organizationA, memberAId]);
    assert(grantCount.rows[0].count === 0, 'REMOVED_MEMBERSHIP_RETAINED_GRANTS');
    const removeReplay = await membershipsA.removeFor(owner, organizationA, memberAId);
    assert(!removeReplay.data.changed && removeReplay.data.policyVersion === removed.data.policyVersion, 'MEMBERSHIP_DELETE_NOT_IDEMPOTENT');

    currentStage = 'concurrent-owner-demotion-barrier';
    let lockHeld = false;
    const outcomes = [];
    try {
      await migration.query('BEGIN');
      lockHeld = true;
      await migration.query('SELECT id FROM public.organizations WHERE id = $1::uuid FOR UPDATE', [organizationA]);
      const lockHolder = await migration.query('SELECT pg_catalog.pg_backend_pid() AS pid');
      const demoteOwnerB = withActor(appA, owner.actorId, (client) => client.query(
        `SELECT * FROM public.update_organization_membership(
          $1::uuid, $2::uuid, $3::uuid, $4, 'admin'::public.organization_role, '[]'::jsonb
        )`,
        [organizationA, ownerBId, randomUUID(), '1'.repeat(64)],
      ))
        .then((value) => ({ value }), (error) => ({ error }));
      try {
        await waitForLockWaits(migration, [applicationA], Number(lockHolder.rows[0].pid));
      } catch (error) {
        await migration.query('ROLLBACK');
        lockHeld = false;
        const outcome = await Promise.race([demoteOwnerB, new Promise((resolve) => setTimeout(() => resolve(null), 1_000))]);
        const raw = outcome?.error;
        const databaseCode = raw?.meta?.driverAdapterError?.cause?.originalCode
          ?? raw?.meta?.driverAdapterError?.cause?.code
          ?? raw?.meta?.code
          ?? raw?.code
          ?? 'none';
        const code = `${error.code}_REQUEST_${outcome === null ? 'PENDING' : raw ? `ERROR_${databaseCode}` : 'RESOLVED'}`;
        throw Object.assign(new Error(code), { code });
      }
      const demoteOwnerA = withActor(appB, users[1].id, (client) => client.query(
        `SELECT * FROM public.update_organization_membership(
          $1::uuid, $2::uuid, $3::uuid, $4, 'admin'::public.organization_role, '[]'::jsonb
        )`,
        [organizationA, ownerAId, randomUUID(), '2'.repeat(64)],
      ))
        .then((value) => ({ value }), (error) => ({ error }));
      try {
        await waitForLockWaits(migration, [applicationA, applicationB], Number(lockHolder.rows[0].pid));
      } catch (error) {
        await migration.query('ROLLBACK');
        lockHeld = false;
        const outcome = await Promise.race([demoteOwnerA, new Promise((resolve) => setTimeout(() => resolve(null), 1_000))]);
        const raw = outcome?.error;
        const databaseCode = raw?.meta?.driverAdapterError?.cause?.originalCode
          ?? raw?.meta?.driverAdapterError?.cause?.code
          ?? raw?.meta?.code
          ?? raw?.code
          ?? 'none';
        const code = `${error.code}_SECOND_REQUEST_${outcome === null ? 'PENDING' : raw ? `ERROR_${databaseCode}` : 'RESOLVED'}`;
        throw Object.assign(new Error(code), { code });
      }
      await migration.query('COMMIT');
      lockHeld = false;
      outcomes.push(...await Promise.all([demoteOwnerB, demoteOwnerA]));
    } finally {
      if (lockHeld) await migration.query('ROLLBACK').catch(() => {});
    }
    assert(outcomes.filter((result) => result.value).length === 1, 'OWNER_DEMOTION_DID_NOT_HAVE_SINGLE_WINNER');
    assert(outcomes.filter((result) => ['42501', 'P0001'].includes(result.error?.code)).length === 1, 'CONCURRENT_OWNER_DEMOTION_NOT_REJECTED');
    const ownerCountA = await migration.query("SELECT count(*)::INTEGER AS count FROM public.organization_memberships WHERE organization_id = $1::uuid AND status = 'active' AND role = 'owner'", [organizationA]);
    assert(ownerCountA.rows[0].count === 1, 'CONCURRENT_OWNER_DEMOTION_REMOVED_LAST_OWNER');
    const remainingOwner = await migration.query("SELECT id,user_id FROM public.organization_memberships WHERE organization_id = $1::uuid AND status = 'active' AND role = 'owner'", [organizationA]);
    const remainingOwnerUser = users.find((user) => user.id === remainingOwner.rows[0].user_id);
    const remainingOwnerPrincipal = verifiedPrincipal(remainingOwnerUser);
    await expectServiceError(
      () => membershipsA.updateFor(remainingOwnerPrincipal, organizationA, remainingOwner.rows[0].id, randomUUID(), { role: 'admin', farmGrants: [] }),
      409, 'VERSION_CONFLICT', 'LAST_OWNER_DEMOTION_ACCEPTED',
    );
    const bearer = 'farmly-p03-membership-http-fixture';
    const auth = {
      api: {
        getSession: async ({ headers }) => headers.get('authorization') === `Bearer ${bearer}` ? {
          user: {
            id: remainingOwnerPrincipal.actorId,
            email: remainingOwnerPrincipal.email,
            name: remainingOwnerPrincipal.displayName,
            emailVerified: true,
          },
          session: {
            id: remainingOwnerPrincipal.sessionId,
            expiresAt: remainingOwnerPrincipal.sessionExpiresAt,
          },
        } : null,
      },
    };
    class MembershipHttpTestModule {}
    Module({
      controllers: [OrganizationMembershipsController],
      providers: [
        VerifiedSessionGuard,
        { provide: FARMLY_AUTH, useValue: auth },
        { provide: OrganizationMembershipsService, useValue: membershipsA },
      ],
    })(MembershipHttpTestModule);
    membershipHttpApp = await NestFactory.create(MembershipHttpTestModule, new ExpressAdapter(), { logger: false });
    membershipHttpApp.useGlobalFilters(new FarmlyHttpExceptionFilter());
    await membershipHttpApp.listen(0, '127.0.0.1');
    const address = membershipHttpApp.getHttpServer().address();
    assert(address && typeof address !== 'string', 'MEMBERSHIP_HTTP_LISTENER_UNAVAILABLE');
    const lastOwnerRemoval = await fetch(`http://127.0.0.1:${address.port}/v1/organizations/${organizationA}/memberships/${remainingOwner.rows[0].id}`, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${bearer}` },
    });
    assert(lastOwnerRemoval.status === 409, 'LAST_OWNER_HTTP_SELF_REMOVAL_STATUS_INVALID');
    const lastOwnerError = await lastOwnerRemoval.json();
    assert(lastOwnerError?.error?.code === 'VERSION_CONFLICT' && lastOwnerError.error.retryable === false, 'LAST_OWNER_HTTP_SELF_REMOVAL_ERROR_INVALID');
    await membershipHttpApp.close();
    membershipHttpApp = undefined;

    currentStage = 'ownership-transfer-demote-and-remove';
    const ownerC = verifiedPrincipal(users[4]);
    const transferOneId = randomUUID();
    const transferOne = await membershipsB.transferFor(ownerC, organizationB, transferOneId, targetBId, false);
    assert(transferOne.data.targetMembershipId === targetBId && transferOne.data.formerOwnerMembershipId === ownerCId, 'OWNERSHIP_TRANSFER_TARGET_INVALID');
    assert(transferOne.data.formerOwnerRole === 'admin' && transferOne.data.formerOwnerStatus === 'active', 'FORMER_OWNER_NOT_DEMOTED');
    const transferOneReplay = await membershipsB.transferFor(ownerC, organizationB, transferOneId, targetBId, false);
    assert(transferOneReplay.data.replayed && transferOneReplay.data.policyVersion === transferOne.data.policyVersion, 'OWNERSHIP_TRANSFER_REPLAY_FAILED');
    const newOwnerB = verifiedPrincipal(users[5]);
    const transferTwoId = randomUUID();
    const transferTwo = await membershipsB.transferFor(newOwnerB, organizationB, transferTwoId, targetCId, true);
    assert(transferTwo.data.formerOwnerRole === 'owner' && transferTwo.data.formerOwnerStatus === 'removed', 'FORMER_OWNER_NOT_REMOVED');
    const transferTwoReplay = await membershipsB.transferFor(newOwnerB, organizationB, transferTwoId, targetCId, true);
    assert(transferTwoReplay.data.replayed && transferTwoReplay.data.policyVersion === transferTwo.data.policyVersion, 'REMOVED_FORMER_OWNER_REPLAY_FAILED');
    await expectServiceError(
      () => membershipsB.transferFor(ownerC, organizationB, randomUUID(), targetCId, false),
      403, 'PERMISSION_DENIED', 'ADMIN_TRANSFERRED_OWNERSHIP',
    );
    const ownerCountB = await migration.query("SELECT count(*)::INTEGER AS count FROM public.organization_memberships WHERE organization_id = $1::uuid AND status = 'active' AND role = 'owner'", [organizationB]);
    assert(ownerCountB.rows[0].count === 1, 'OWNERSHIP_TRANSFER_VIOLATED_OWNER_INVARIANT');
    await expectServiceError(
      () => membershipsB.removeFor(verifiedPrincipal(users[6]), organizationB, targetCId),
      409, 'VERSION_CONFLICT', 'LAST_OWNER_SELF_REMOVAL_ACCEPTED_AFTER_TRANSFER',
    );

    currentStage = 'postgres-bigint-max-scope-policy-version-wire';
    const maxPolicyVersion = '9223372036854775807';
    await migration.query(
      'UPDATE public.organizations SET policy_version = $2::bigint WHERE id = $1::uuid',
      [organizationB, maxPolicyVersion],
    );
    const maxVersionOwner = verifiedPrincipal(users[6]);
    const maxVersionRoster = await membershipsB.listFor(maxVersionOwner, organizationB, 25, null);
    assert(maxVersionRoster.meta.scopePolicyVersion === maxPolicyVersion
      && typeof maxVersionRoster.meta.scopePolicyVersion === 'string', 'ROSTER_MAX_BIGINT_SCOPE_POLICY_VERSION_LOST');
    const maxVersionDirectory = await organizationsB.farmDirectoryFor(maxVersionOwner, organizationB, 100, null);
    assert(maxVersionDirectory.scopePolicyVersion === maxPolicyVersion
      && typeof maxVersionDirectory.scopePolicyVersion === 'string', 'FARM_DIRECTORY_MAX_BIGINT_SCOPE_POLICY_VERSION_LOST');

    currentStage = 'least-privilege-control-receipt';
    await expectSqlState(
      () => withActor(appA, users[0].id, (client) => client.query('SELECT * FROM public.organization_control_receipts')),
      '42501', 'TENANT_ROLE_READS_CONTROL_RECEIPTS',
    );

    currentStage = 'completed';
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
  } finally {
    currentStage = 'cleanup';
    try {
      if (membershipHttpApp) await membershipHttpApp.close();
      if (organizationIds.length > 0) await migration.query('DELETE FROM public.organizations WHERE id = ANY($1::uuid[])', [organizationIds]);
      if (users.length > 0) await migration.query('DELETE FROM auth."user" WHERE id = ANY($1::text[])', [users.map((user) => user.id)]);
      const remaining = await migration.query(`
        SELECT (SELECT count(*)::INTEGER FROM public.organizations WHERE id = ANY($1::uuid[])) AS organizations,
               (SELECT count(*)::INTEGER FROM auth."user" WHERE id = ANY($2::text[])) AS users
      `, [organizationIds, users.map((user) => user.id)]);
      assert(remaining.rows[0].organizations === 0 && remaining.rows[0].users === 0, 'MEMBERSHIP_FIXTURES_REMAIN');
    } catch (error) {
      cleanupError = error;
    }
    await Promise.all(tenantServices.map((service) => service.onModuleDestroy().catch(() => {})));
    await Promise.all([migration.end(), appA.end(), appB.end()].map((promise) => promise.catch(() => {})));
  }

  if (cleanupError) throw Object.assign(new Error('ORGANIZATION_MEMBERSHIP_CLEANUP_FAILED'), { cleanupError, operationError, operationStage });
  if (operationError) throw Object.assign(operationError, { operationStage });
  process.stdout.write(JSON.stringify({ status: 'PASS', gate: 'P03-organization-memberships', evidence: 'PostgreSQL 17.11 + app role + Nest HTTP/controller/filter + service adapter; test session stub' }) + '\n');
}

main().catch((error) => {
  const failure = error?.operationError ?? error;
  const code = typeof failure?.code === 'string' ? failure.code : 'UNEXPECTED';
  const nestedSqlState = failure?.meta?.driverAdapterError?.cause?.code;
  const safeSqlState = typeof nestedSqlState === 'string' && /^[0-9A-Z]{5}$/.test(nestedSqlState) ? nestedSqlState : null;
  const databaseMessage = failure?.meta?.driverAdapterError?.cause?.message;
  const ambiguousColumn = safeSqlState === '42702' && typeof databaseMessage === 'string'
    ? databaseMessage.match(/^column reference ["']?([A-Za-z_][A-Za-z0-9_]*)["']? is ambiguous$/i)?.[1]
    : null;
  const stage = error?.operationStage ?? currentStage;
  const cleanupCode = typeof error?.cleanupError?.code === 'string' ? error.cleanupError.code : null;
  console.error(`ORGANIZATION_MEMBERSHIPS_FAILED: stage=${stage} code=${code}${safeSqlState ? ` sqlstate=${safeSqlState}` : ''}${ambiguousColumn ? ` ambiguous_column=${ambiguousColumn}` : ''}${cleanupCode ? ` cleanup=${cleanupCode}` : ''}`);
  process.exitCode = 1;
});
