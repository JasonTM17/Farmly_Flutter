import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { createHash, randomUUID } from 'node:crypto';
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

function mutation(operationId = randomUUID(), resourceId = randomUUID(), name = 'Mutation test farm') {
  return {
    schemaVersion: 'farm-mutation.v1',
    continuityEpoch: '1',
    operationId,
    type: 'farm.create',
    resourceId,
    dependsOn: [],
    payload: { name, areaM2: '125000.00', timezone: 'Asia/Ho_Chi_Minh' },
  };
}

function occurrenceIdFor(farmId, templateId, occurrenceDate, slot) {
  const hash = createHash('md5')
    .update(`taskocc:${farmId}:${templateId}:${occurrenceDate}:${slot}`)
    .digest('hex');
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-5${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}

function reorderedMutation(value) {
  return {
    type: value.type,
    payload: { timezone: value.payload.timezone, areaM2: value.payload.areaM2, name: value.payload.name },
    resourceId: value.resourceId,
    operationId: value.operationId,
    continuityEpoch: value.continuityEpoch,
    dependsOn: [...value.dependsOn],
    schemaVersion: value.schemaVersion,
  };
}

function fixtureUser(suffix, label, token) {
  return {
    id: `mutation-${label}-${suffix}`,
    email: `${label}-${suffix}@farmly.test`,
    token,
    name: `Mutation ${label}`,
    sessionId: randomUUID(),
  };
}

function sessionFor(user) {
  return {
    user: { id: user.id, email: user.email, name: user.name, emailVerified: true },
    session: { id: user.sessionId, expiresAt: new Date(Date.now() + 60_000) },
  };
}

function httpHeaders(token, extra = {}) {
  return { authorization: `Bearer ${token}`, ...extra };
}

async function readBody(response) {
  try { return await response.json(); } catch { return null; }
}

async function expectJson(response, status, code) {
  const body = await readBody(response);
  assert(response.status === status, `${code}_STATUS_${response.status}`);
  return body;
}

async function expectForbidden(response, code) {
  const body = await readBody(response);
  assert(response.status === 403 || response.status === 404, `${code}_STATUS_${response.status}`);
  assert(body?.error?.code !== undefined, `${code}_SAFE_ERROR_MISSING`);
  return body;
}

function assertBatchOutcome(body, operationId, expected, code) {
  const outcomes = body?.data?.outcomes;
  assert(Array.isArray(outcomes), `${code}_OUTCOMES_MISSING`);
  const result = outcomes.find((item) => item.operationId === operationId);
  assert(result?.outcome === expected, `${code}_OUTCOME_${result?.outcome ?? 'MISSING'}`);
  assert(Object.keys(result).every((key) => ['operationId', 'outcome', 'code'].includes(key)), `${code}_OUTCOME_LEAK`);
  return result;
}

async function countOperation(migration, organizationId, farmId, operationId) {
  const result = await migration.query(`
    SELECT
      (SELECT count(*)::INTEGER FROM public.farms WHERE organization_id = $1::uuid AND id = $2::uuid) AS farms,
      (SELECT count(*)::INTEGER FROM public.farm_clocks WHERE organization_id = $1::uuid AND farm_id = $2::uuid) AS clocks,
      (SELECT count(*)::INTEGER FROM public.applied_operations WHERE organization_id = $1::uuid AND operation_id = $3::uuid) AS proofs,
      (SELECT count(*)::INTEGER FROM public.operation_response_cache WHERE organization_id = $1::uuid AND operation_id = $3::uuid) AS caches,
      (SELECT count(*)::INTEGER FROM public.change_sets WHERE organization_id = $1::uuid AND operation_id = $3::uuid) AS changes,
      (SELECT count(*)::INTEGER FROM public.audit_events WHERE organization_id = $1::uuid AND operation_id = $3::uuid) AS audits,
      (SELECT policy_version::TEXT FROM public.organizations WHERE id = $1::uuid) AS policy_version
  `, [organizationId, farmId, operationId]);
  return result.rows[0];
}

async function expectNoAppliedMutation(migration, organizationId, farmId, operationId, expectedPolicyVersion, code) {
  const counts = await countOperation(migration, organizationId, farmId, operationId);
  assert(counts.farms === 0 && counts.clocks === 0 && counts.proofs === 0
    && counts.changes === 0 && counts.audits === 0,
  `${code}_PARTIAL_MUTATION`);
  assert(counts.policy_version === expectedPolicyVersion, `${code}_POLICY_VERSION_CHANGED`);
}

async function insertVerifiedUsers(migration, users) {
  const values = [];
  const rows = users.map((user, index) => {
    const offset = index * 4;
    values.push(user.id, user.name, user.email, new Date());
    return `($${offset + 1}, $${offset + 2}, $${offset + 3}, TRUE, $${offset + 4})`;
  });
  await migration.query(`
    INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt")
    VALUES ${rows.join(', ')}
  `, values);
}

async function waitForLockWait(migration, applicationName, blockingPid) {
  for (let attempt = 0; attempt < 250; attempt += 1) {
    await migration.query('SELECT pg_catalog.pg_stat_clear_snapshot()');
    const result = await migration.query(`
      SELECT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_stat_activity AS activity
        WHERE activity.application_name = $1
          AND $2::INTEGER = ANY(pg_catalog.pg_blocking_pids(activity.pid))
      ) AS blocked
    `, [applicationName, blockingPid]);
    if (result.rows[0]?.blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw Object.assign(new Error('MUTATION_ORGANIZATION_LOCK_WAIT_NOT_OBSERVED'), { code: 'MUTATION_ORGANIZATION_LOCK_WAIT_NOT_OBSERVED' });
}

async function main() {
  assert(migrationUrl && configuredDatabaseName === expectedDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assertTarget(migrationUrl, 'farmly_migration');
  assertTarget(tenantConnectionString('farmly-mutation-preflight'), 'farmly_tenant_app');

  const suffix = randomUUID().replaceAll('-', '');
  const httpApplicationName = `farmly-mutation-http-${suffix}`;
  assert(Buffer.byteLength(httpApplicationName, 'utf8') <= 63, 'POSTGRES_APPLICATION_NAME_TOO_LONG');
  const owner = fixtureUser(suffix, 'owner', `mutation-owner-${suffix}`);
  const admin = fixtureUser(suffix, 'admin', `mutation-admin-${suffix}`);
  const pendingAdmin = fixtureUser(suffix, 'pending-admin', `mutation-pending-admin-${suffix}`);
  const member = fixtureUser(suffix, 'member', `mutation-member-${suffix}`);
  const viewer = fixtureUser(suffix, 'viewer', `mutation-viewer-${suffix}`);
  const foreignOwner = fixtureUser(suffix, 'foreign-owner', `mutation-foreign-owner-${suffix}`);
  const users = [owner, admin, pendingAdmin, member, viewer, foreignOwner];
  const userByToken = new Map(users.map((user) => [user.token, user]));
  const organizationId = randomUUID();
  const foreignOrganizationId = randomUUID();
  const organizationIds = [organizationId, foreignOrganizationId];
  const suffixUuid = randomUUID();
  const migration = new Client({ connectionString: withApplicationName(migrationUrl, `farmly-mutation-migration-${suffix}`) });
  let taskResourceLocker;
  const createdDatabaseServices = [];
  let app;
  let mutationHttpTestServer;
  let auditFailureTriggerName;
  let auditFailureFunctionName;
  let operationError;
  let operationStage;
  let cleanupError;

  try {
    currentStage = 'connect-and-check-kernel-schema';
    await migration.connect();
    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'MIGRATION_DATABASE_IDENTITY_INVALID');
    const schema = await migration.query(`
      SELECT to_regclass('public.farm_clocks') IS NOT NULL AS clocks_ready,
             to_regclass('public.applied_operations') IS NOT NULL AS proofs_ready,
             to_regclass('public.operation_response_cache') IS NOT NULL AS cache_ready,
             to_regclass('public.change_sets') IS NOT NULL AS changes_ready,
             to_regclass('public.audit_events') IS NOT NULL AS audit_ready,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'apply_farm_mutation') AS apply_ready,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'get_my_operation_status') AS status_ready
    `);
    assert(Object.values(schema.rows[0]).every(Boolean), 'MUTATION_KERNEL_SCHEMA_NOT_READY');

    currentStage = 'check-mutation-guard-execution-privileges';
    const timezoneGuardPrivileges = await migration.query(`
      SELECT
        pg_catalog.has_function_privilege('farmly_tenant_app', wrapper.oid, 'EXECUTE') AS wrapper_tenant,
        pg_catalog.has_function_privilege('farmly_tenant_app', schedule_guard.oid, 'EXECUTE') AS schedule_guard_tenant,
        pg_catalog.has_function_privilege('farmly_tenant_app', core.oid, 'EXECUTE') AS core_tenant,
        EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(COALESCE(schedule_guard.proacl, pg_catalog.acldefault('f', schedule_guard.proowner))) AS privilege
          WHERE privilege.grantee = 0 AND privilege.privilege_type = 'EXECUTE'
        ) AS schedule_guard_public,
        EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(COALESCE(core.proacl, pg_catalog.acldefault('f', core.proowner))) AS privilege
          WHERE privilege.grantee = 0 AND privilege.privilege_type = 'EXECUTE'
        ) AS core_public,
        EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(COALESCE(wrapper.proacl, pg_catalog.acldefault('f', wrapper.proowner))) AS privilege
          WHERE privilege.grantee = 0 AND privilege.privilege_type = 'EXECUTE'
        ) AS wrapper_public
      FROM pg_catalog.pg_proc AS wrapper
      JOIN pg_catalog.pg_proc AS schedule_guard
        ON schedule_guard.oid = 'public.apply_farm_mutation_without_task_schedule_guard(uuid,text,text,uuid,text,bigint,jsonb,text,uuid)'::regprocedure
      JOIN pg_catalog.pg_proc AS core
        ON core.oid = 'public.apply_farm_mutation_without_iana_timezone_guard(uuid,text,text,uuid,text,bigint,jsonb,text,uuid)'::regprocedure
      WHERE wrapper.oid = 'public.apply_farm_mutation(uuid,text,text,uuid,text,bigint,jsonb,text,uuid)'::regprocedure
    `);
    const guardPrivileges = timezoneGuardPrivileges.rows[0];
    assert(guardPrivileges?.wrapper_tenant === true, 'TIMEZONE_GUARD_WRAPPER_NOT_GRANTED_TO_TENANT');
    assert(guardPrivileges?.schedule_guard_tenant === false, 'TASK_SCHEDULE_INNER_GUARD_GRANTED_TO_TENANT');
    assert(guardPrivileges?.core_tenant === false, 'TIMEZONE_GUARD_CORE_GRANTED_TO_TENANT');
    assert(guardPrivileges?.schedule_guard_public === false, 'TASK_SCHEDULE_INNER_GUARD_GRANTED_TO_PUBLIC');
    assert(guardPrivileges?.core_public === false, 'TIMEZONE_GUARD_CORE_GRANTED_TO_PUBLIC');
    assert(guardPrivileges?.wrapper_public === false, 'TIMEZONE_GUARD_WRAPPER_GRANTED_TO_PUBLIC');

    currentStage = 'seed-verified-actors-and-organizations';
    await insertVerifiedUsers(migration, users);
    await migration.query(`
      INSERT INTO public.organizations (id, name, continuity_epoch)
      VALUES ($1::uuid, 'Mutation kernel fixture', 1), ($2::uuid, 'Foreign mutation fixture', 1)
    `, [organizationId, foreignOrganizationId]);
    await migration.query(`
      INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status)
      VALUES
        ($1::uuid, $2::uuid, $3, 'owner', 'active'),
        ($4::uuid, $2::uuid, $5, 'admin', 'active'),
        ($6::uuid, $2::uuid, $7, 'admin', 'active'),
        ($8::uuid, $2::uuid, $9, 'member', 'active'),
        ($10::uuid, $2::uuid, $11, 'viewer', 'active'),
        ($12::uuid, $13::uuid, $14, 'owner', 'active')
    `, [
      randomUUID(), organizationId, owner.id,
      randomUUID(), admin.id,
      randomUUID(), pendingAdmin.id,
      randomUUID(), member.id,
      randomUUID(), viewer.id,
      randomUUID(), foreignOrganizationId, foreignOwner.id,
    ]);

    currentStage = 'load-verified-http-controller-and-kernel';
    const [
      { TenantDatabaseService },
      { MutationKernelService },
      { MutationKernelController },
      { FarmDomainController },
      { FarmDomainService },
      { OrganizationsService },
      { VerifiedSessionGuard },
      { FARMLY_AUTH },
      { FarmlyHttpExceptionFilter },
    ] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/common/mutations/mutation-kernel.service.js', import.meta.url)),
      import(new URL('../../dist/common/mutations/mutation-kernel.controller.js', import.meta.url)),
      import(new URL('../../dist/farm-domain/farm-domain.controller.js', import.meta.url)),
      import(new URL('../../dist/farm-domain/farm-domain.service.js', import.meta.url)),
      import(new URL('../../dist/organizations/organizations.service.js', import.meta.url)),
      import(new URL('../../dist/auth/verified-session.guard.js', import.meta.url)),
      import(new URL('../../dist/auth/auth.module.js', import.meta.url)),
      import(new URL('../../dist/common/farmly-http-exception.filter.js', import.meta.url)),
    ]);
    const tenant = new TenantDatabaseService({
      get: (key) => key === 'farmlyEnvironment'
        ? { databaseUrlTenant: tenantConnectionString(httpApplicationName), cursorSigningKey: process.env.CURSOR_SIGNING_KEY }
        : undefined,
    });
    createdDatabaseServices.push(tenant);
    await tenant.onModuleInit();
    const config = { get: (key) => key === 'farmlyEnvironment' ? { cursorSigningKey: process.env.CURSOR_SIGNING_KEY } : undefined };
    const kernel = new MutationKernelService(tenant, config);
    const organizations = new OrganizationsService(tenant, config);
    const auth = {
      api: {
        getSession: async ({ headers }) => {
          const authorization = headers.get('authorization') ?? '';
          const user = authorization.startsWith('Bearer ') ? userByToken.get(authorization.slice(7)) : undefined;
          return user ? sessionFor(user) : null;
        },
      },
    };
    class MutationKernelHttpTestModule {}
    Module({
      controllers: [MutationKernelController, FarmDomainController],
      providers: [
        VerifiedSessionGuard,
        { provide: FARMLY_AUTH, useValue: auth },
        { provide: MutationKernelService, useValue: kernel },
        { provide: FarmDomainService, useValue: {} },
      ],
    })(MutationKernelHttpTestModule);
    app = await NestFactory.create(MutationKernelHttpTestModule, new ExpressAdapter(), { logger: false });
    app.useGlobalFilters(new FarmlyHttpExceptionFilter());
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address();
    assert(address && typeof address !== 'string', 'MUTATION_HTTP_LISTENER_UNAVAILABLE');
    const origin = `http://127.0.0.1:${address.port}`;
    const direct = (token, orgId, intent, idempotencyKey = intent.operationId) => fetch(
      `${origin}/v1/organizations/${orgId}/farms`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json', ...(idempotencyKey ? { 'idempotency-key': idempotencyKey } : {}) }),
        body: JSON.stringify(intent),
      },
    );
    const updateFarm = (token, orgId, farmId, intent) => fetch(
      `${origin}/v1/organizations/${orgId}/farms/${farmId}`,
      {
        method: 'PATCH',
        headers: httpHeaders(token, {
          'content-type': 'application/json',
          'idempotency-key': intent.operationId,
        }),
        body: JSON.stringify(intent),
      },
    );
    const batch = (token, orgId, intents) => fetch(
      `${origin}/v1/organizations/${orgId}/sync/mutations`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify({ schemaVersion: 'farm-mutation-batch.v1', continuityEpoch: '1', operations: intents }),
      },
    );
    const farmBatch = (token, orgId, farmId, intents) => fetch(
      `${origin}/v1/organizations/${orgId}/farms/${farmId}/sync/mutations`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify({ schemaVersion: 'farm-mutation-batch.v1', continuityEpoch: '1', operations: intents }),
      },
    );
    const statuses = (token, operationIds) => fetch(
      `${origin}/v1/me/operation-status?operationIds=${operationIds.join(',')}`,
      { headers: httpHeaders(token) },
    );

    currentStage = 'authentication-and-idempotency-denials';
    const noSession = await fetch(`${origin}/v1/organizations/${organizationId}/farms`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(mutation()),
    });
    assert(noSession.status === 401, 'FARM_CREATE_MISSING_SESSION_ACCEPTED');
    const missingKeyIntent = mutation();
    const missingKey = await direct(owner.token, organizationId, missingKeyIntent, '');
    assert(missingKey.status === 400, 'FARM_CREATE_MISSING_IDEMPOTENCY_KEY_ACCEPTED');
    const mismatchedKeyIntent = mutation();
    const mismatchedKey = await direct(owner.token, organizationId, mismatchedKeyIntent, randomUUID());
    assert(mismatchedKey.status === 400, 'FARM_CREATE_IDEMPOTENCY_MISMATCH_ACCEPTED');
    const bodySpoofIntent = { ...mutation(), actorId: foreignOwner.id, organizationId: foreignOrganizationId };
    const bodySpoof = await direct(owner.token, organizationId, bodySpoofIntent);
    assert(bodySpoof.status === 400, 'FARM_CREATE_CLIENT_SCOPE_FIELDS_ACCEPTED');

    currentStage = 'owner-admin-success-and-decimal-policy-version';
    const ownerIntent = mutation(randomUUID(), randomUUID(), 'Owner-created farm');
    const ownerCreate = await direct(owner.token, organizationId, ownerIntent);
    const ownerResponse = await expectJson(ownerCreate, 200, 'OWNER_FARM_CREATE');
    assert(ownerResponse?.data && ownerResponse?.meta?.scopePolicyVersion === '2', 'OWNER_FARM_CREATE_ENVELOPE_INVALID');
    const ownerCounts = await countOperation(migration, organizationId, ownerIntent.resourceId, ownerIntent.operationId);
    assert(ownerCounts.farms === 1 && ownerCounts.clocks === 1 && ownerCounts.proofs === 1
      && ownerCounts.changes === 1 && ownerCounts.audits === 1 && ownerCounts.policy_version === '2',
    'OWNER_FARM_CREATE_NOT_ATOMIC');
    const ownerProof = await migration.query(`
      SELECT actor_pseudonym, continuity_epoch::TEXT AS continuity_epoch, request_hash,
             outcome
      FROM public.applied_operations
      WHERE organization_id = $1::uuid AND operation_id = $2::uuid
    `, [organizationId, ownerIntent.operationId]);
    assert(ownerProof.rows.length === 1 && ownerProof.rows[0].actor_pseudonym !== owner.id
      && ownerProof.rows[0].continuity_epoch === '1' && /^[a-f0-9]{64}$/.test(ownerProof.rows[0].request_hash)
      && ownerProof.rows[0].outcome === 'applied', 'FARM_OPERATION_PROOF_INVALID');
    const cacheLifetime = await migration.query(`
      SELECT EXTRACT(EPOCH FROM (expires_at - created_at)) * 1000 AS lifetime_ms
      FROM public.operation_response_cache WHERE organization_id = $1::uuid AND operation_id = $2::uuid
    `, [organizationId, ownerIntent.operationId]);
    assert(Math.abs(Number(cacheLifetime.rows[0]?.lifetime_ms) - 7 * 24 * 60 * 60 * 1000) < 1_000, 'FARM_RESPONSE_CACHE_NOT_SEVEN_DAYS');
    const adminIntent = mutation(randomUUID(), randomUUID(), 'Admin-created farm');
    const adminCreate = await direct(admin.token, organizationId, adminIntent);
    const adminResponse = await expectJson(adminCreate, 200, 'ADMIN_FARM_CREATE');
    assert(adminResponse?.data && adminResponse?.meta?.scopePolicyVersion === '3', 'ADMIN_FARM_CREATE_ENVELOPE_INVALID');

    currentStage = 'invalid-farm-timezone-durable-rejection-and-replay';
    const timezoneCreate = mutation(randomUUID(), randomUUID(), 'Invalid timezone farm');
    timezoneCreate.payload.timezone = 'Mars/Olympus_Mons';
    const invalidCreateResponse = await direct(owner.token, organizationId, timezoneCreate);
    const invalidCreateBody = await expectJson(invalidCreateResponse, 200, 'TIMEZONE_CREATE_RESPONSE');
    assert(invalidCreateBody?.data?.outcome === 'rejected'
      && invalidCreateBody.data.code === 'FIELD_VALIDATION_FAILED', 'TIMEZONE_CREATE_NOT_REJECTED');
    const invalidCreateCounts = await countOperation(migration, organizationId, timezoneCreate.resourceId, timezoneCreate.operationId);
    assert(invalidCreateCounts.farms === 0 && invalidCreateCounts.clocks === 0
      && invalidCreateCounts.proofs === 1 && invalidCreateCounts.caches === 1
      && invalidCreateCounts.changes === 0 && invalidCreateCounts.audits === 0
      && invalidCreateCounts.policy_version === '3', 'TIMEZONE_CREATE_NOT_DURABLY_REJECTED');
    const invalidCreateProof = await migration.query(`
      SELECT outcome, result_code
      FROM public.applied_operations
      WHERE organization_id = $1::uuid AND operation_id = $2::uuid
    `, [organizationId, timezoneCreate.operationId]);
    assert(invalidCreateProof.rows[0]?.outcome === 'rejected'
      && invalidCreateProof.rows[0]?.result_code === 'FIELD_VALIDATION_FAILED', 'TIMEZONE_CREATE_PROOF_INVALID');
    const invalidCreateStatus = await readBody(await statuses(owner.token, [timezoneCreate.operationId]));
    assert(invalidCreateStatus?.data?.operations?.[0]?.outcome === 'rejected', 'TIMEZONE_CREATE_STATUS_NOT_REJECTED');
    const invalidCreateReplay = await readBody(await direct(owner.token, organizationId, timezoneCreate));
    assert(invalidCreateReplay?.data?.outcome === 'rejected'
      && invalidCreateReplay.data.code === 'FIELD_VALIDATION_FAILED', 'TIMEZONE_CREATE_REPLAY_CHANGED');
    const changedCreate = {
      ...timezoneCreate,
      payload: { ...timezoneCreate.payload, timezone: 'Asia/Ho_Chi_Minh' },
    };
    const changedCreateResponse = await direct(owner.token, organizationId, changedCreate);
    const changedCreateBody = await readBody(changedCreateResponse);
    assert(changedCreateResponse.status === 409 && changedCreateBody?.error?.code === 'OPERATION_ID_REUSED',
      'TIMEZONE_CREATE_CHANGED_HASH_NOT_REJECTED');

    currentStage = 'invalid-farm-update-timezone-does-not-mutate-farm';
    const readFarmState = () => migration.query(`
      SELECT farm.timezone, farm.version, clock.revision::TEXT AS clock_revision,
             organization.policy_version::TEXT AS policy_version,
             (SELECT count(*)::INTEGER FROM public.change_sets AS change_set
               WHERE change_set.organization_id = farm.organization_id AND change_set.farm_id = farm.id) AS changes,
             (SELECT count(*)::INTEGER FROM public.audit_events AS audit
               WHERE audit.organization_id = farm.organization_id AND audit.farm_id = farm.id) AS audits
      FROM public.farms AS farm
      JOIN public.organizations AS organization ON organization.id = farm.organization_id
      JOIN public.farm_clocks AS clock ON clock.organization_id = farm.organization_id AND clock.farm_id = farm.id
      WHERE farm.organization_id = $1::uuid AND farm.id = $2::uuid
    `, [organizationId, ownerIntent.resourceId]);
    const farmBeforeInvalidUpdate = await readFarmState();
    assert(farmBeforeInvalidUpdate.rows.length === 1, 'TIMEZONE_UPDATE_FIXTURE_MISSING');
    const timezoneUpdate = {
      ...mutation(randomUUID(), ownerIntent.resourceId, 'Invalid timezone update'),
      type: 'farm.update',
      baseVersion: 1,
      payload: { timezone: 'Mars/Olympus_Mons' },
    };
    const invalidUpdateResponse = await updateFarm(owner.token, organizationId, ownerIntent.resourceId, timezoneUpdate);
    const invalidUpdateBody = await expectJson(invalidUpdateResponse, 200, 'TIMEZONE_UPDATE_RESPONSE');
    assert(invalidUpdateBody?.data?.outcome === 'rejected'
      && invalidUpdateBody.data.code === 'FIELD_VALIDATION_FAILED', 'TIMEZONE_UPDATE_NOT_REJECTED');
    const farmAfterInvalidUpdate = await readFarmState();
    assert(JSON.stringify(farmAfterInvalidUpdate.rows[0]) === JSON.stringify(farmBeforeInvalidUpdate.rows[0]),
      'TIMEZONE_UPDATE_MUTATED_FARM');
    const invalidUpdateCounts = await countOperation(migration, organizationId, ownerIntent.resourceId, timezoneUpdate.operationId);
    assert(invalidUpdateCounts.farms === 1 && invalidUpdateCounts.clocks === 1
      && invalidUpdateCounts.proofs === 1 && invalidUpdateCounts.caches === 1
      && invalidUpdateCounts.changes === 0 && invalidUpdateCounts.audits === 0
      && invalidUpdateCounts.policy_version === '3', 'TIMEZONE_UPDATE_NOT_DURABLY_REJECTED');
    const invalidUpdateStatus = await readBody(await statuses(owner.token, [timezoneUpdate.operationId]));
    assert(invalidUpdateStatus?.data?.operations?.[0]?.outcome === 'rejected', 'TIMEZONE_UPDATE_STATUS_NOT_REJECTED');
    const invalidUpdateReplay = await readBody(await updateFarm(owner.token, organizationId, ownerIntent.resourceId, timezoneUpdate));
    assert(invalidUpdateReplay?.data?.outcome === 'rejected'
      && invalidUpdateReplay.data.code === 'FIELD_VALIDATION_FAILED', 'TIMEZONE_UPDATE_REPLAY_CHANGED');
    const changedUpdate = {
      ...timezoneUpdate,
      payload: { timezone: 'Asia/Ho_Chi_Minh' },
    };
    const changedUpdateResponse = await updateFarm(owner.token, organizationId, ownerIntent.resourceId, changedUpdate);
    const changedUpdateBody = await readBody(changedUpdateResponse);
    assert(changedUpdateResponse.status === 409 && changedUpdateBody?.error?.code === 'OPERATION_ID_REUSED',
      'TIMEZONE_UPDATE_CHANGED_HASH_NOT_REJECTED');
    const validTimezoneUpdate = {
      ...timezoneUpdate,
      operationId: randomUUID(),
      payload: { timezone: 'America/New_York' },
    };
    const validUpdateBody = await readBody(await updateFarm(owner.token, organizationId, ownerIntent.resourceId, validTimezoneUpdate));
    assert(validUpdateBody?.data?.outcome === 'applied'
      && validUpdateBody.data.farm?.timezone === 'America/New_York', 'TIMEZONE_UPDATE_VALID_IANA_REJECTED');

    currentStage = 'role-and-cross-scope-denials-both-transports';
    for (const [actor, label] of [[member, 'MEMBER'], [viewer, 'VIEWER']]) {
      const directDenied = await direct(actor.token, organizationId, mutation());
      await expectForbidden(directDenied, `${label}_DIRECT_FARM_CREATE`);
      const batchDenied = await batch(actor.token, organizationId, [mutation()]);
      await expectForbidden(batchDenied, `${label}_BATCH_FARM_CREATE`);
    }
    const foreignScopeDirect = await direct(owner.token, foreignOrganizationId, mutation());
    await expectForbidden(foreignScopeDirect, 'CROSS_ORGANIZATION_DIRECT_FARM_CREATE');
    const foreignScopeBatch = await batch(owner.token, foreignOrganizationId, [mutation()]);
    await expectForbidden(foreignScopeBatch, 'CROSS_ORGANIZATION_BATCH_FARM_CREATE');

    currentStage = 'same-operation-cross-transport-concurrency-and-canonical-hash';
    const concurrentIntent = mutation(randomUUID(), randomUUID(), 'Concurrent canonical farm');
    const [concurrentDirect, concurrentBatch] = await Promise.all([
      direct(owner.token, organizationId, concurrentIntent),
      batch(owner.token, organizationId, [reorderedMutation(concurrentIntent)]),
    ]);
    const [concurrentDirectBody, concurrentBatchBody] = await Promise.all([readBody(concurrentDirect), readBody(concurrentBatch)]);
    assert(concurrentDirect.status === 200 && concurrentBatch.status === 200, 'S05_SAME_ID_CROSS_TRANSPORT_FAILED');
    assertBatchOutcome(concurrentBatchBody, concurrentIntent.operationId, 'applied', 'S05_CROSS_TRANSPORT_REPLAY');
    const concurrentCounts = await countOperation(migration, organizationId, concurrentIntent.resourceId, concurrentIntent.operationId);
    assert(concurrentCounts.farms === 1 && concurrentCounts.clocks === 1 && concurrentCounts.proofs === 1
      && concurrentCounts.changes === 1 && concurrentCounts.audits === 1,
    'S05_SAME_ID_CREATED_MORE_THAN_ONCE');
    assert(concurrentCounts.policy_version === '4' && concurrentDirectBody?.meta?.scopePolicyVersion === '4', 'SCOPE_POLICY_VERSION_NOT_EXACTLY_ONCE');
    const changedHashIntent = { ...concurrentIntent, payload: { ...concurrentIntent.payload, name: 'Changed immutable intent' } };
    const changedHash = await direct(owner.token, organizationId, changedHashIntent);
    const changedHashBody = await expectJson(changedHash, 409, 'S05_CHANGED_HASH');
    assert(changedHashBody?.error?.code === 'OPERATION_ID_REUSED', 'S05_CHANGED_HASH_ERROR_INVALID');

    currentStage = 'organization-lock-rechecks-current-authorization';
    const pendingIntent = mutation(randomUUID(), randomUUID(), 'Must be denied after demotion');
    await migration.query('BEGIN');
    let lockHeld = true;
    try {
      const lock = await migration.query('SELECT pg_backend_pid() AS pid FROM public.organizations WHERE id = $1::uuid FOR UPDATE', [organizationId]);
      const waitingRequest = direct(pendingAdmin.token, organizationId, pendingIntent);
      try {
        await waitForLockWait(migration, httpApplicationName, Number(lock.rows[0].pid));
      } catch (error) {
        await migration.query('ROLLBACK');
        lockHeld = false;
        await waitingRequest.catch(() => undefined);
        throw error;
      }
      await migration.query("UPDATE public.organization_memberships SET role = 'member' WHERE organization_id = $1::uuid AND user_id = $2", [organizationId, pendingAdmin.id]);
      await migration.query('COMMIT');
      lockHeld = false;
      const afterLock = await waitingRequest;
      await expectForbidden(afterLock, 'AUTHORITY_NOT_RECHECKED_AFTER_ORG_LOCK');
      await expectNoAppliedMutation(migration, organizationId, pendingIntent.resourceId, pendingIntent.operationId, concurrentCounts.policy_version, 'REVOKED_ROLE_MUTATED_AFTER_ORG_LOCK');
    } finally {
      if (lockHeld) await migration.query('ROLLBACK').catch(() => {});
    }

    currentStage = 'task-occurrence-authorization-rechecked-before-farm-lock';
    const memberMembership = await migration.query(`
      SELECT id FROM public.organization_memberships
      WHERE organization_id = $1::uuid AND user_id = $2 AND status = 'active'
    `, [organizationId, member.id]);
    assert(memberMembership.rowCount === 1, 'TASK_SCHEDULE_MEMBER_FIXTURE_MISSING');
    const taskTemplateId = randomUUID();
    const targetDate = await migration.query(`
      SELECT (CURRENT_DATE + 1)::TEXT AS occurrence_date,
             ((EXTRACT(DOW FROM CURRENT_DATE + 1)::INTEGER + 1) % 7) AS unselected_weekday
    `);
    const occurrenceDate = targetDate.rows[0].occurrence_date;
    const selectedWeekday = targetDate.rows[0].unselected_weekday;
    await migration.query(`
      INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
      VALUES ($1::uuid, $2::uuid, $3::uuid, 'manager')
    `, [organizationId, memberMembership.rows[0].id, ownerIntent.resourceId]);
    await migration.query(`
      INSERT INTO public.task_templates (
        organization_id, farm_id, id, title, kind, recurrence, starts_on, status, version
      ) VALUES (
        $1::uuid, $2::uuid, $3::uuid, 'Task schedule lock test', 'general',
        $4::jsonb, CURRENT_DATE - 1, 'active', 1
      )
    `, [
      organizationId,
      ownerIntent.resourceId,
      taskTemplateId,
      JSON.stringify({ freq: 'weekly', timeOfDay: '06:00', daysOfWeek: [selectedWeekday] }),
    ]);
    const occurrenceSlot = 'default';
    const occurrenceId = occurrenceIdFor(ownerIntent.resourceId, taskTemplateId, occurrenceDate, occurrenceSlot);
    const transitionIntent = {
      schemaVersion: 'farm-mutation.v1',
      continuityEpoch: '1',
      operationId: randomUUID(),
      type: 'taskOccurrence.transition',
      resourceId: occurrenceId,
      dependsOn: [],
      payload: {
        templateId: taskTemplateId,
        occurrenceDate,
        slot: occurrenceSlot,
        transition: 'complete',
      },
    };
    taskResourceLocker = new Client({
      connectionString: withApplicationName(migrationUrl, `farmly-task-lock-${suffix}`),
    });
    await taskResourceLocker.connect();
    await taskResourceLocker.query('BEGIN');
    let resourceLockHeld = true;
    let organizationLockHeld = false;
    let waitingTaskRequest;
    try {
      await taskResourceLocker.query(
        'SELECT id FROM public.farms WHERE organization_id = $1::uuid AND id = $2::uuid FOR UPDATE',
        [organizationId, ownerIntent.resourceId],
      );

      await migration.query('BEGIN');
      organizationLockHeld = true;
      const lock = await migration.query(
        'SELECT pg_backend_pid() AS pid FROM public.organizations WHERE id = $1::uuid FOR UPDATE',
        [organizationId],
      );
      waitingTaskRequest = farmBatch(member.token, organizationId, ownerIntent.resourceId, [transitionIntent]);
      await waitForLockWait(migration, httpApplicationName, Number(lock.rows[0].pid));

      const grantRemoval = await migration.query(`
        DELETE FROM public.farm_grants
        WHERE organization_id = $1::uuid AND membership_id = $2::uuid AND farm_id = $3::uuid
        RETURNING farm_id
      `, [organizationId, memberMembership.rows[0].id, ownerIntent.resourceId]);
      assert(grantRemoval.rowCount === 1, 'TASK_SCHEDULE_MANAGER_GRANT_NOT_REVOKED');
      await migration.query('COMMIT');
      organizationLockHeld = false;

      let timeoutId;
      const responseBeforeFarmUnlock = await Promise.race([
        waitingTaskRequest.then((response) => ({ response })),
        new Promise((resolve) => {
          timeoutId = setTimeout(() => resolve({ timedOut: true }), 5_000);
        }),
      ]);
      clearTimeout(timeoutId);
      if (responseBeforeFarmUnlock.timedOut) {
        await taskResourceLocker.query('ROLLBACK');
        resourceLockHeld = false;
        await waitingTaskRequest.catch(() => undefined);
        assert(false, 'TASK_SCHEDULE_GUARD_LOCKED_FARM_BEFORE_AUTH_RECHECK');
      }
      await expectForbidden(responseBeforeFarmUnlock.response, 'TASK_SCHEDULE_GRANT_REVOKED_AFTER_ORG_LOCK');

      const deniedMutation = await migration.query(`
        SELECT
          (SELECT count(*)::INTEGER FROM public.applied_operations WHERE organization_id = $1::uuid AND operation_id = $2::uuid) AS proofs,
          (SELECT count(*)::INTEGER FROM public.change_sets WHERE organization_id = $1::uuid AND farm_id = $3::uuid AND operation_id = $2::uuid) AS changes,
          (SELECT count(*)::INTEGER FROM public.audit_events WHERE organization_id = $1::uuid AND farm_id = $3::uuid AND operation_id = $2::uuid) AS audits,
          (SELECT count(*)::INTEGER FROM public.task_occurrences WHERE organization_id = $1::uuid AND farm_id = $3::uuid AND id = $4::uuid) AS occurrences
      `, [organizationId, transitionIntent.operationId, ownerIntent.resourceId, occurrenceId]);
      assert(Object.values(deniedMutation.rows[0]).every((count) => count === 0), 'TASK_SCHEDULE_REVOKED_TRANSITION_MUTATED');
      await taskResourceLocker.query('COMMIT');
      resourceLockHeld = false;
    } finally {
      if (organizationLockHeld) await migration.query('ROLLBACK').catch(() => {});
      if (resourceLockHeld) await taskResourceLocker.query('ROLLBACK').catch(() => {});
      await waitingTaskRequest?.catch(() => undefined);
    }
    await taskResourceLocker.end();
    taskResourceLocker = undefined;

    currentStage = 'S06_RESPONSE_CACHE_EXPIRY_DURABLE_PROOF';
    const cacheIntent = mutation(randomUUID(), randomUUID(), 'Cache-expiry farm');
    const cacheCreate = await direct(owner.token, organizationId, cacheIntent);
    await expectJson(cacheCreate, 200, 'S06_INITIAL_CREATE');
    const beforeExpiredReplay = await countOperation(migration, organizationId, cacheIntent.resourceId, cacheIntent.operationId);
    await migration.query(`
      UPDATE public.operation_response_cache
      SET created_at = clock_timestamp() - interval '2 seconds',
          expires_at = clock_timestamp() - interval '1 second'
      WHERE organization_id = $1::uuid AND operation_id = $2::uuid
    `, [organizationId, cacheIntent.operationId]);
    const expiredReplay = await direct(owner.token, organizationId, cacheIntent);
    assert(expiredReplay.status === 200 || expiredReplay.status === 409, 'S06_EXPIRED_REPLAY_STATUS_INVALID');
    const afterExpiredReplay = await countOperation(migration, organizationId, cacheIntent.resourceId, cacheIntent.operationId);
    assert(afterExpiredReplay.farms === 1 && afterExpiredReplay.clocks === 1 && afterExpiredReplay.proofs === 1
      && afterExpiredReplay.changes === 1 && afterExpiredReplay.audits === 1
      && afterExpiredReplay.policy_version === beforeExpiredReplay.policy_version,
    'S06_EXPIRED_REPLAY_REAPPLIED_MUTATION');

    currentStage = 'batch-independent-outcomes-and-parent-blocking';
    const rejectedParent = mutation(randomUUID(), randomUUID(), '   ');
    const blockedChild = mutation(randomUUID(), randomUUID(), 'Must stay blocked');
    blockedChild.dependsOn = [rejectedParent.operationId];
    const independent = mutation(randomUUID(), randomUUID(), 'Independent successful sibling');
    const mixedBatch = await batch(owner.token, organizationId, [rejectedParent, blockedChild, independent]);
    const mixedBody = await expectJson(mixedBatch, 200, 'BATCH_PARTIAL_RESULT');
    assertBatchOutcome(mixedBody, rejectedParent.operationId, 'rejected', 'BATCH_PARENT_REJECTED');
    assertBatchOutcome(mixedBody, blockedChild.operationId, 'rejected', 'BATCH_CHILD_NOT_BLOCKED');
    assertBatchOutcome(mixedBody, independent.operationId, 'applied', 'BATCH_INDEPENDENT_SIBLING_LOST');
    const parentCounts = await countOperation(migration, organizationId, rejectedParent.resourceId, rejectedParent.operationId);
    const childCounts = await countOperation(migration, organizationId, blockedChild.resourceId, blockedChild.operationId);
    const independentCounts = await countOperation(migration, organizationId, independent.resourceId, independent.operationId);
    assert(parentCounts.farms === 0 && childCounts.farms === 0 && independentCounts.farms === 1, 'BATCH_DEPENDENCY_OR_PARTIAL_COMMIT_INVALID');

    currentStage = 'S08_FAULT_ROLLBACK_ALL_MUTATION_RECORDS';
    const faultIntent = mutation(randomUUID(), randomUUID(), 'Fault-injected farm');
    auditFailureTriggerName = `farmly_mutation_fail_${suffix}`;
    auditFailureFunctionName = `farmly_mutation_fail_fn_${suffix}`;
    await migration.query(`
      CREATE FUNCTION public.${auditFailureFunctionName}() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $body$ BEGIN
        IF NEW.operation_id = '${faultIntent.operationId}'::uuid THEN
          RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'test-only audit fault';
        END IF;
        RETURN NEW;
      END; $body$
    `);
    await migration.query(`CREATE TRIGGER ${auditFailureTriggerName} BEFORE INSERT ON public.audit_events FOR EACH ROW EXECUTE FUNCTION public.${auditFailureFunctionName}()`);
    const faultResponse = await direct(owner.token, organizationId, faultIntent);
    const faultBody = await readBody(faultResponse);
    assert(faultResponse.status >= 500, 'S08_FAULT_DID_NOT_ABORT_REQUEST');
    assert(!JSON.stringify(faultBody).includes('test-only audit fault'), 'S08_RAW_DATABASE_ERROR_LEAKED');
    await migration.query(`DROP TRIGGER ${auditFailureTriggerName} ON public.audit_events`);
    await migration.query(`DROP FUNCTION public.${auditFailureFunctionName}()`);
    auditFailureTriggerName = undefined;
    auditFailureFunctionName = undefined;
    await expectNoAppliedMutation(migration, organizationId, faultIntent.resourceId, faultIntent.operationId, independentCounts.policy_version, 'S08_PARTIAL_COMMIT');

    currentStage = 'S19_LOST_ACK_REVOKE_AND_MINIMAL_OWN_STATUS';
    const lostAckIntent = mutation(randomUUID(), randomUUID(), 'Lost acknowledgement farm');
    const committedResponse = await direct(admin.token, organizationId, lostAckIntent);
    assert(committedResponse.status === 200, 'S19_COMMIT_BEFORE_ACK_LOSS');
    await committedResponse.body?.cancel();
    await migration.query("UPDATE public.organization_memberships SET status = 'removed' WHERE organization_id = $1::uuid AND user_id = $2", [organizationId, admin.id]);
    const retryAfterRevoke = await direct(admin.token, organizationId, lostAckIntent);
    await expectForbidden(retryAfterRevoke, 'S19_REVOKED_DOMAIN_RETRY');
    const ownStatusResponse = await statuses(admin.token, [lostAckIntent.operationId, suffixUuid]);
    const ownStatusBody = await expectJson(ownStatusResponse, 200, 'S19_OWN_OPERATION_STATUS');
    const ownStatuses = ownStatusBody?.data?.operations;
    assert(Array.isArray(ownStatuses), 'S19_STATUS_LIST_MISSING');
    const knownStatus = ownStatuses.find((item) => item.operationId === lostAckIntent.operationId);
    const unknownStatus = ownStatuses.find((item) => item.operationId === suffixUuid);
    assert(knownStatus?.outcome === 'applied' && unknownStatus?.outcome === 'unknown', 'S19_STATUS_OUTCOME_INVALID');
    assert(Object.keys(knownStatus).sort().join(',') === 'operationId,outcome', 'S19_STATUS_PAYLOAD_LEAK');
    const foreignStatusResponse = await statuses(foreignOwner.token, [lostAckIntent.operationId]);
    const foreignStatusBody = await expectJson(foreignStatusResponse, 200, 'S19_FOREIGN_STATUS_UNKNOWN');
    const foreignStatuses = foreignStatusBody?.data?.operations;
    assert(foreignStatuses?.[0]?.operationId === lostAckIntent.operationId && foreignStatuses[0].outcome === 'unknown', 'S19_FOREIGN_STATUS_ORACLE');
    assert(Object.keys(foreignStatuses[0]).sort().join(',') === 'operationId,outcome', 'S19_FOREIGN_STATUS_PAYLOAD_LEAK');
    const tooManyStatuses = await statuses(owner.token, Array.from({ length: 51 }, () => randomUUID()));
    assert(tooManyStatuses.status === 400, 'S19_OPERATION_STATUS_LIMIT_NOT_ENFORCED');

    currentStage = 'bigint-policy-version-exact-wire-value';
    await migration.query('UPDATE public.organizations SET policy_version = 9007199254740993 WHERE id = $1::uuid', [organizationId]);
    const largePolicyIntent = mutation(randomUUID(), randomUUID(), 'Exact policy version farm');
    const largePolicyResponse = await direct(owner.token, organizationId, largePolicyIntent);
    const largePolicyBody = await expectJson(largePolicyResponse, 200, 'POLICY_BIGINT_CREATE');
    assert(largePolicyBody?.meta?.scopePolicyVersion === '9007199254740994', 'POLICY_BIGINT_NOT_EXACT_DECIMAL_STRING');

    currentStage = 'S01_multi_farm_same_epoch_policy_bump_and_directory_discovery';
    const firstOfflineFarm = mutation(randomUUID(), randomUUID(), 'First offline farm');
    const secondOfflineFarm = mutation(randomUUID(), randomUUID(), 'Second offline farm');
    const multiFarmResponse = await batch(owner.token, organizationId, [firstOfflineFarm, secondOfflineFarm]);
    const multiFarmBody = await expectJson(multiFarmResponse, 200, 'S01_MULTI_FARM_BATCH');
    assertBatchOutcome(multiFarmBody, firstOfflineFarm.operationId, 'applied', 'S01_FIRST_FARM_NOT_APPLIED');
    assertBatchOutcome(multiFarmBody, secondOfflineFarm.operationId, 'applied', 'S01_SECOND_FARM_INVALIDATED_BY_POLICY_BUMP');
    assert(multiFarmBody?.meta?.scopePolicyVersion === '9007199254740996', 'S01_MULTI_FARM_POLICY_VERSION_NOT_EXACT');
    for (const farmIntent of [firstOfflineFarm, secondOfflineFarm]) {
      const counts = await countOperation(migration, organizationId, farmIntent.resourceId, farmIntent.operationId);
      assert(counts.farms === 1 && counts.clocks === 1 && counts.proofs === 1
        && counts.changes === 1 && counts.audits === 1 && counts.policy_version === '9007199254740996',
      'S01_MULTI_FARM_MUTATION_NOT_ATOMIC');
    }
    const refreshedDirectory = await organizations.farmDirectoryFor(
      { actorId: owner.id }, organizationId, null, null,
    );
    const discoveredFarmIds = new Set(refreshedDirectory.farms.map((farm) => farm.farmId));
    assert(refreshedDirectory.scopePolicyVersion === '9007199254740996'
      && discoveredFarmIds.has(firstOfflineFarm.resourceId)
      && discoveredFarmIds.has(secondOfflineFarm.resourceId),
    'S01_SECOND_INSTALL_DIRECTORY_DISCOVERY_FAILED');

    currentStage = 'task-schedule-archived-farm-canonical-rejection';
    await migration.query(`
      UPDATE public.farms
         SET status = 'archived'
       WHERE organization_id = $1::uuid AND id = $2::uuid
    `, [organizationId, ownerIntent.resourceId]);
    const archivedFarmTransition = { ...transitionIntent, operationId: randomUUID() };
    const archivedTransitionResponse = await farmBatch(
      owner.token,
      organizationId,
      ownerIntent.resourceId,
      [archivedFarmTransition],
    );
    const archivedTransitionBody = await expectJson(archivedTransitionResponse, 200, 'TASK_SCHEDULE_ARCHIVED_FARM');
    const archivedOutcome = assertBatchOutcome(
      archivedTransitionBody,
      archivedFarmTransition.operationId,
      'rejected',
      'TASK_SCHEDULE_ARCHIVED_FARM',
    );
    assert(archivedOutcome.code === 'RESOURCE_ARCHIVED', 'TASK_SCHEDULE_ARCHIVED_FARM_CODE');
    const archivedOccurrence = await migration.query(`
      SELECT count(*)::INTEGER AS count
        FROM public.task_occurrences
       WHERE organization_id = $1::uuid AND farm_id = $2::uuid AND id = $3::uuid
    `, [organizationId, ownerIntent.resourceId, occurrenceId]);
    assert(archivedOccurrence.rows[0].count === 0, 'TASK_SCHEDULE_ARCHIVED_FARM_MATERIALIZED_OCCURRENCE');

    currentStage = 'complete';
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
  } finally {
    if (app) await app.close().catch(() => {});
    await Promise.all(createdDatabaseServices.map((service) => service.onModuleDestroy().catch(() => {})));
    if (taskResourceLocker) {
      await taskResourceLocker.query('ROLLBACK').catch(() => {});
      await taskResourceLocker.end().catch(() => {});
    }
    if (migration) {
      await migration.query('ROLLBACK').catch(() => {});
      if (auditFailureTriggerName) await migration.query(`DROP TRIGGER IF EXISTS ${auditFailureTriggerName} ON public.audit_events`).catch(() => {});
      if (auditFailureFunctionName) await migration.query(`DROP FUNCTION IF EXISTS public.${auditFailureFunctionName}()`).catch(() => {});
      await migration.query('DELETE FROM public.organizations WHERE id = ANY($1::uuid[])', [organizationIds]).catch((error) => { cleanupError = error; });
      await migration.query('DELETE FROM auth."user" WHERE id = ANY($1::text[])', [users.map((user) => user.id)]).catch((error) => { cleanupError = error; });
      await migration.end().catch((error) => { cleanupError = cleanupError ?? error; });
    }
  }

  if (operationError) {
    const code = operationError && typeof operationError === 'object' && typeof operationError.code === 'string'
      && /^[A-Z0-9_]{1,100}$/.test(operationError.code) ? operationError.code : 'UNEXPECTED_FAILURE';
    process.stderr.write(JSON.stringify({ status: 'failed', stage: operationStage, code }) + '\n');
    process.exitCode = 1;
    return;
  }
  if (cleanupError) {
    process.stderr.write(JSON.stringify({ status: 'failed', stage: 'fixture-cleanup', code: 'FIXTURE_CLEANUP_FAILED' }) + '\n');
    process.exitCode = 1;
    return;
  }
  process.stdout.write(JSON.stringify({
    status: 'passed',
    scope: 'P03.5 mutation-kernel real PostgreSQL/app-role + verified Nest HTTP integration',
    cases: ['S-01-multi-farm-policy-bump-directory-discovery', 'S-05', 'S-06', 'S-08', 'S-19', 'owner-admin', 'role-denial', 'cross-scope', 'shared-transports', 'post-lock-auth', 'task-schedule-post-lock-authorization-before-farm-lock', 'task-schedule-archived-farm-canonical-rejection', 'batch-siblings-parent-block', 'bigint-policy-version'],
  }) + '\n');
}

await main();
