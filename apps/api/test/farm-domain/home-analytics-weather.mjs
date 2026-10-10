import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { createHash, randomUUID } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Client } from 'pg';

// P07 step — home/weather/analytics read-surface suite for the approved wire
// contract (decision record 2026-10-08, spec04 §5.1, contracts/openapi/farmly-v1.yaml).
// Every assertion names DESIRED behavior; the suite is expected to fail while the
// farm-scoped read routes are missing. Setup stages stay fail-fast
// so a red baseline always means "contract behavior missing", never "fixture broken".

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const configuredDatabaseName = process.env.FARMLY_TEST_DATABASE_NAME;
const cursorSigningKey = process.env.CURSOR_SIGNING_KEY;
const authDatabaseUrl = process.env.DATABASE_URL_AUTH;

const SAFE_CODE = /^[A-Z0-9_]{1,140}$/;
const POSITIVE_DECIMAL = /^[1-9][0-9]*$/;
const REVISION_DECIMAL = /^(0|[1-9][0-9]*)$/;
const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
const DOMAIN_TABLES = {
  zone: 'zones',
  cropSpecies: 'crop_species',
  planting: 'plantings',
  herd: 'herds',
  animal: 'animals',
  waterTank: 'water_tanks',
  livestockMovement: 'livestock_movements',
};

let currentStage = 'startup';
const results = [];

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

function stage(name) {
  currentStage = name;
}

async function check(caseCode, fn) {
  try {
    await fn();
    results.push({ stage: currentStage, case: caseCode, status: 'passed' });
  } catch (error) {
    const detail = error && typeof error === 'object' && typeof error.code === 'string' && SAFE_CODE.test(error.code)
      ? error.code
      : 'UNEXPECTED_FAILURE';
    results.push({ stage: currentStage, case: caseCode, status: 'failed', detail });
  }
}

function fixtureUser(suffix, label) {
  return {
    id: `domain-${label}-${suffix}`,
    email: `${label}-${suffix}@farmly.test`,
    token: `domain-${label}-${suffix}`,
    name: `Domain ${label}`,
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

// HTTP-level denial per spec04 §4: unknown scope ->404, revoked scope/denied action ->403.
async function expectDenied(response, code) {
  const body = await readBody(response);
  assert(response.status === 403 || response.status === 404, `${code}_STATUS_${response.status}`);
  assert(typeof body?.error?.code === 'string' && body.error.code.length > 0, `${code}_SAFE_ERROR_MISSING`);
  return body;
}

// A domain rule rejection: the write must be actively refused by an implemented
// contract surface (typed rejected outcome or safe 4xx). A bare missing-route 404
// is deliberately not accepted for schema/rule assertions.
async function expectDomainRejected(response, code, { allowConflict = false, operationId } = {}) {
  const body = await readBody(response);
  if (response.status === 200) {
    const entry = Array.isArray(body?.data?.outcomes)
      ? body.data.outcomes.find((item) => item.operationId === operationId)
      : body?.data;
    const outcome = entry?.outcome;
    assert(
      outcome === 'rejected' || (allowConflict && outcome === 'conflict'),
      `${code}_UNEXPECTED_OUTCOME_${outcome ?? 'MISSING'}`,
    );
    return body;
  }
  assert([400, 403, 409, 422].includes(response.status), `${code}_STATUS_${response.status}`);
  assert(typeof body?.error?.code === 'string' && body.error.code.length > 0, `${code}_SAFE_ERROR_MISSING`);
  return body;
}

// Scope/FK-level non-application: unknown-in-scope objects may surface as 404
// without enumeration, as a safe 4xx, or as a non-applied typed outcome.
async function expectDomainNotApplied(response, code) {
  const body = await readBody(response);
  if (response.status === 200) {
    assert(body?.data && typeof body.data === 'object', `${code}_ENVELOPE_INVALID`);
    assert(body.data.outcome !== 'applied', `${code}_WAS_APPLIED`);
    return body;
  }
  assert([400, 403, 404, 409, 410, 422].includes(response.status), `${code}_STATUS_${response.status}`);
  assert(typeof body?.error?.code === 'string' && body.error.code.length > 0, `${code}_SAFE_ERROR_MISSING`);
  return body;
}

async function expectVersionConflict(response, code) {
  const body = await readBody(response);
  if (response.status === 200) {
    const outcome = body?.data?.outcome;
    assert(
      (outcome === 'conflict' || outcome === 'rejected') && body?.data?.code === 'VERSION_CONFLICT',
      `${code}_NO_VERSION_CONFLICT`,
    );
    return body;
  }
  assert(response.status === 409, `${code}_STATUS_${response.status}`);
  assert(body?.error?.code === 'VERSION_CONFLICT', `${code}_ERROR_${body?.error?.code ?? 'MISSING'}`);
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

// ---- immutable intent builders (farm-mutation.v1 envelope, spec04 §5.1) ----

function intent(type, resourceId, payload, continuityEpoch, overrides = {}) {
  return {
    schemaVersion: 'farm-mutation.v1',
    continuityEpoch,
    operationId: randomUUID(),
    type,
    resourceId,
    dependsOn: [],
    payload,
    ...overrides,
  };
}

const ZONE_TRIANGLE = [
  { x: '0', y: '0' },
  { x: '1', y: '0' },
  { x: '0.5', y: '1' },
];

function zonePoints(overrides = []) {
  return ZONE_TRIANGLE.map((point, index) => ({ ...point, ...(overrides[index] ?? {}) }));
}

// ---- compiled-surface discovery: register every dist controller whose
// dependencies can be satisfied, so the suite exercises whichever farm-scoped
// controllers the implementation lands without editing this file. ----

function isClass(value) {
  return typeof value === 'function' && /^class\s/.test(Function.prototype.toString.call(value));
}

function dependencyToken(cls, index) {
  const declared = Reflect.getMetadata('self:paramtypes', cls) ?? [];
  const entry = declared.find((item) => item && item.index === index);
  if (entry) {
    const token = entry.param ?? entry.token ?? entry;
    if (token && typeof token === 'object' && typeof token.forwardRef === 'function') return token.forwardRef();
    if (typeof token === 'function' && entry.forwardRef === true) return token();
    return token;
  }
  const types = Reflect.getMetadata('design:paramtypes', cls) ?? [];
  return types[index];
}

function dependenciesOf(cls) {
  const deps = [];
  for (let index = 0; index < cls.length; index += 1) deps.push(dependencyToken(cls, index));
  return deps;
}

async function discoverNestArtifacts(distRoot) {
  const files = [];
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const child = join(directory, entry.name);
      if (entry.isDirectory()) walk(child);
      // Skip entrypoints and Nest module classes: importing *.module.js evaluates
      // decorator-time side effects (e.g. AppModule's ConfigModule.forRoot with
      // validateEnvironment, which rejects MIGRATION_DATABASE_URL asynchronously
      // and crashes the harness via unhandled rejection). Controllers/providers
      // are still discovered from their own compiled files.
      else if (entry.name.endsWith('.js') && entry.name !== 'main.js' && !entry.name.endsWith('.module.js')) files.push(child);
    }
  };
  walk(distRoot);
  const controllers = new Set();
  const providers = new Set();
  for (const file of files) {
    let module;
    try { module = await import(pathToFileURL(file).href); } catch { continue; }
    for (const exported of Object.values(module)) {
      if (!isClass(exported)) continue;
      if (Reflect.getMetadata('path', exported) !== undefined) { controllers.add(exported); continue; }
      if (Reflect.getMetadata('controllers', exported) !== undefined
        || Reflect.getMetadata('imports', exported) !== undefined) continue; // module classes
      providers.add(exported);
    }
  }
  return { controllers: [...controllers], providers: [...providers] };
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

async function main() {
  assert(migrationUrl && configuredDatabaseName === expectedDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assert(cursorSigningKey, 'CURSOR_SIGNING_KEY_REQUIRED');
  assertTarget(migrationUrl, 'farmly_migration');
  assertTarget(tenantConnectionString('farmly-domain-preflight'), 'farmly_tenant_app');

  const suffix = randomUUID().replaceAll('-', '');
  const httpApplicationName = `farmly-domain-http-${suffix}`;
  assert(Buffer.byteLength(httpApplicationName, 'utf8') <= 63, 'POSTGRES_APPLICATION_NAME_TOO_LONG');
  const s8 = () => randomUUID().slice(0, 8);

  const owner = fixtureUser(suffix, 'owner');
  const admin = fixtureUser(suffix, 'admin');
  const member = fixtureUser(suffix, 'member');
  const manager = fixtureUser(suffix, 'manager');
  const worker = fixtureUser(suffix, 'worker');
  const viewer = fixtureUser(suffix, 'viewer');
  const orgViewer = fixtureUser(suffix, 'orgviewer');
  const suspended = fixtureUser(suffix, 'suspended');
  const workerB = fixtureUser(suffix, 'workerb');
  const crossFarm = fixtureUser(suffix, 'crossfarm');
  const foreignOwner = fixtureUser(suffix, 'foreign-owner');
  const users = [owner, admin, member, manager, worker, workerB, viewer, orgViewer, suspended, crossFarm, foreignOwner];
  const userByToken = new Map(users.map((user) => [user.token, user]));

  const organizationId = randomUUID();
  const foreignOrganizationId = randomUUID();
  const organizationIds = [organizationId, foreignOrganizationId];
  const memberships = Object.fromEntries(
    ['owner', 'admin', 'member', 'manager', 'worker', 'workerb', 'viewer', 'orgviewer', 'suspended', 'crossfarm', 'foreign']
      .map((label) => [label, randomUUID()]),
  );

  const migration = new Client({ connectionString: withApplicationName(migrationUrl, `farmly-domain-migration-${suffix}`) });
  const domainTables = new Map();
  let app;
  let moduleMode = 'extended';
  let operationError;
  let operationStage;
  let cleanupError;
  let tenant;

  const setup = async () => {
    stage('setup-connect-and-check-kernel-schema');
    await migration.connect();
    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'MIGRATION_DATABASE_IDENTITY_INVALID');
    const schema = await migration.query(`
      SELECT to_regclass('public.organizations') IS NOT NULL AS organizations_ready,
             to_regclass('public.organization_memberships') IS NOT NULL AS memberships_ready,
             to_regclass('public.farms') IS NOT NULL AS farms_ready,
             to_regclass('public.farm_grants') IS NOT NULL AS grants_ready,
             to_regclass('public.farm_clocks') IS NOT NULL AS clocks_ready,
             to_regclass('public.applied_operations') IS NOT NULL AS proofs_ready,
             to_regclass('public.operation_response_cache') IS NOT NULL AS cache_ready,
             to_regclass('public.change_sets') IS NOT NULL AS changes_ready,
             to_regclass('public.audit_events') IS NOT NULL AS audit_ready,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'apply_farm_mutation') AS apply_ready
    `);
    assert(Object.values(schema.rows[0]).every(Boolean), 'MUTATION_KERNEL_SCHEMA_NOT_READY');
    const domainSchema = await migration.query(`
      SELECT
        to_regclass('public.zones') IS NOT NULL AS zones,
        to_regclass('public.crop_species') IS NOT NULL AS crop_species,
        to_regclass('public.plantings') IS NOT NULL AS plantings,
        to_regclass('public.herds') IS NOT NULL AS herds,
        to_regclass('public.animals') IS NOT NULL AS animals,
        to_regclass('public.water_tanks') IS NOT NULL AS water_tanks,
        to_regclass('public.livestock_movements') IS NOT NULL AS livestock_movements
    `);
    for (const [key, present] of Object.entries(domainSchema.rows[0])) domainTables.set(key, present === true);

    stage('setup-seed-verified-actors-organizations-memberships');
    await insertVerifiedUsers(migration, users);
    await migration.query(`
      INSERT INTO public.organizations (id, name, continuity_epoch)
      VALUES ($1::uuid, 'Farm domain fixture org', 1), ($2::uuid, 'Foreign domain fixture org', 1)
    `, [organizationId, foreignOrganizationId]);
    await migration.query(`
      INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status)
      VALUES
        ($1::uuid, $2::uuid, $3, 'owner', 'active'),
        ($4::uuid, $2::uuid, $5, 'admin', 'active'),
        ($6::uuid, $2::uuid, $7, 'member', 'active'),
        ($8::uuid, $2::uuid, $9, 'member', 'active'),
        ($10::uuid, $2::uuid, $11, 'member', 'active'),
        ($12::uuid, $2::uuid, $13, 'member', 'active'),
        ($14::uuid, $2::uuid, $15, 'viewer', 'active'),
        ($16::uuid, $2::uuid, $17, 'member', 'suspended'),
        ($18::uuid, $2::uuid, $19, 'member', 'active'),
        ($23::uuid, $2::uuid, $24, 'member', 'active'),
        ($20::uuid, $21::uuid, $22, 'owner', 'active')
    `, [
      memberships.owner, organizationId, owner.id,
      memberships.admin, admin.id,
      memberships.member, member.id,
      memberships.manager, manager.id,
      memberships.worker, worker.id,
      memberships.viewer, viewer.id,
      memberships.orgviewer, orgViewer.id,
      memberships.suspended, suspended.id,
      memberships.crossfarm, crossFarm.id,
      memberships.foreign, foreignOrganizationId, foreignOwner.id,
      memberships.workerb, workerB.id,
    ]);
  };

  const buildApp = async (controllers, providers) => {
    class DomainHttpTestModule {}
    Module({ controllers, providers })(DomainHttpTestModule);
    const instance = await NestFactory.create(DomainHttpTestModule, new ExpressAdapter(), { logger: false });
    const filterModule = await import(new URL('../../dist/common/farmly-http-exception.filter.js', import.meta.url));
    instance.useGlobalFilters(new filterModule.FarmlyHttpExceptionFilter());
    await instance.listen(0, '127.0.0.1');
    return instance;
  };

  try {
    await setup();

    stage('setup-load-http-surface-and-kernel');
    const [
      { TenantDatabaseService },
      { MutationKernelService },
      { MutationKernelController },
      { VerifiedSessionGuard },
      { FARMLY_AUTH },
      { API_ENVIRONMENT },
    ] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/common/mutations/mutation-kernel.service.js', import.meta.url)),
      import(new URL('../../dist/common/mutations/mutation-kernel.controller.js', import.meta.url)),
      import(new URL('../../dist/auth/verified-session.guard.js', import.meta.url)),
      import(new URL('../../dist/auth/auth.module.js', import.meta.url)),
      import(new URL('../../dist/config/environment.js', import.meta.url)),
    ]);

    const apiEnvironment = {
      nodeEnv: 'test',
      port: 0,
      databaseUrlTenant: tenantConnectionString(httpApplicationName),
      databaseUrlAuth: authDatabaseUrl ?? 'postgresql://farmly_auth_app:unused@postgres:5432/farmly_test_261005',
      betterAuthSecret: process.env.BETTER_AUTH_SECRET ?? 'farmly-domain-test-secret-000000000000',
      betterAuthUrl: 'http://127.0.0.1:3000',
      smtpHost: process.env.SMTP_HOST ?? 'mailpit',
      smtpPort: 1025,
      smtpSecure: false,
      smtpRequireTls: false,
      smtpFrom: 'Farmly <no-reply@farmly.test>',
      cursorSigningKey,
      aiEnabled: false,
      aiMaxOutputTokens: 1200,
      weatherEnabled: true,
      weatherFreshTtlSeconds: 3600,
    };
    const configStub = { get: (key) => (key === 'farmlyEnvironment' ? apiEnvironment : undefined) };
    tenant = new TenantDatabaseService(configStub);
    const kernel = new MutationKernelService(tenant);
    const auth = {
      api: {
        getSession: async ({ headers }) => {
          const authorization = headers.get('authorization') ?? '';
          const user = authorization.startsWith('Bearer ') ? userByToken.get(authorization.slice(7)) : undefined;
          return user ? sessionFor(user) : null;
        },
      },
    };

    // Fixed registry: tokens the harness itself satisfies.
    const registry = new Map([
      [TenantDatabaseService, { provide: TenantDatabaseService, useValue: tenant }],
      [ConfigService, { provide: ConfigService, useValue: configStub }],
      [FARMLY_AUTH, { provide: FARMLY_AUTH, useValue: auth }],
      [API_ENVIRONMENT, { provide: API_ENVIRONMENT, useValue: apiEnvironment }],
      [MutationKernelService, { provide: MutationKernelService, useValue: kernel }],
      [VerifiedSessionGuard, { provide: VerifiedSessionGuard, useClass: VerifiedSessionGuard }],
    ]);

    const distRoot = fileURLToPath(new URL('../../dist/', import.meta.url));
    const discovered = await discoverNestArtifacts(distRoot);
    // Fixpoint: offer every discovered injectable whose transitive constructor
    // dependencies are covered by the registry.
    let progressed = true;
    while (progressed) {
      progressed = false;
      for (const cls of discovered.providers) {
        if (registry.has(cls)) continue;
        const deps = dependenciesOf(cls);
        if (deps.every((token) => token != null && registry.has(token))) {
          registry.set(cls, { provide: cls, useClass: cls });
          progressed = true;
        }
      }
    }
    const activeControllers = discovered.controllers
      .filter((cls) => dependenciesOf(cls).every((token) => token != null && registry.has(token)));
    if (!activeControllers.includes(MutationKernelController)) activeControllers.push(MutationKernelController);
    const activeProviders = [...registry.values()];

    try {
      app = await buildApp(activeControllers, activeProviders);
    } catch {
      moduleMode = 'kernel-only';
      app = await buildApp(
        [MutationKernelController],
        [
          VerifiedSessionGuard,
          { provide: FARMLY_AUTH, useValue: auth },
          { provide: MutationKernelService, useValue: kernel },
        ],
      );
    }
    await tenant.onModuleInit().catch(() => {});
    const address = app.getHttpServer().address();
    assert(address && typeof address !== 'string', 'DOMAIN_HTTP_LISTENER_UNAVAILABLE');
    const origin = `http://127.0.0.1:${address.port}`;

    const farmBase = (orgId, farmId) => `${origin}/v1/organizations/${orgId}/farms/${farmId}`;
    const mutationPost = (token, url, intentValue, key = intentValue.operationId) => fetch(url, {
      method: 'POST',
      headers: httpHeaders(token, { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) }),
      body: JSON.stringify(intentValue),
    });
    const orgFarmCreate = (token, orgId, intentValue) => mutationPost(token, `${origin}/v1/organizations/${orgId}/farms`, intentValue);
    const orgBatch = (token, orgId, operations) => fetch(
      `${origin}/v1/organizations/${orgId}/sync/mutations`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify({ schemaVersion: 'farm-mutation-batch.v1', continuityEpoch: '1', operations }),
      },
    );
    const farmBatch = (token, orgId, farmId, operations, epochValue) => fetch(
      `${farmBase(orgId, farmId)}/sync/mutations`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify({ schemaVersion: 'farm-mutation-batch.v1', continuityEpoch: epochValue, operations }),
      },
    );
    const domainCreate = (token, orgId, farmId, slug, intentValue) => mutationPost(token, `${farmBase(orgId, farmId)}/${slug}`, intentValue);
    const domainUpdate = (token, orgId, farmId, slug, resourceId, intentValue) => fetch(
      `${farmBase(orgId, farmId)}/${slug}/${resourceId}`,
      {
        method: 'PATCH',
        headers: httpHeaders(token, { 'content-type': 'application/json', 'idempotency-key': intentValue.operationId }),
        body: JSON.stringify(intentValue),
      },
    );
    const domainArchive = (token, orgId, farmId, slug, resourceId, intentValue) => mutationPost(
      token, `${farmBase(orgId, farmId)}/${slug}/${resourceId}/archive`, intentValue,
    );
    const farmArchivePost = (token, orgId, farmId, intentValue) => mutationPost(token, `${farmBase(orgId, farmId)}/archive`, intentValue);
    const farmPatch = (token, orgId, farmId, intentValue) => fetch(
      `${farmBase(orgId, farmId)}`,
      {
        method: 'PATCH',
        headers: httpHeaders(token, { 'content-type': 'application/json', 'idempotency-key': intentValue.operationId }),
        body: JSON.stringify(intentValue),
      },
    );
    const domainList = (token, orgId, farmId, slug) => fetch(
      `${farmBase(orgId, farmId)}/${slug}`, { headers: httpHeaders(token) },
    );

    stage('setup-create-fixture-farms-via-org-kernel');
    const farmIntents = {};
    for (const [label, name] of [['farmA', 'Domain farm A'], ['farmB', 'Domain farm B'], ['farmC', 'Domain farm C archive target']]) {
      const farmIntent = intent('farm.create', randomUUID(), { name, timezone: 'Asia/Ho_Chi_Minh' }, '1');
      farmIntents[label] = farmIntent;
      const created = await orgFarmCreate(owner.token, organizationId, farmIntent);
      const body = await expectJson(created, 200, `FIXTURE_${label.toUpperCase()}_CREATE`);
      assert(body?.data?.outcome === 'applied', `FIXTURE_${label.toUpperCase()}_NOT_APPLIED`);
    }
    const farmAId = farmIntents.farmA.resourceId;
    const farmBId = farmIntents.farmB.resourceId;
    const farmCId = farmIntents.farmC.resourceId;

    stage('setup-seed-farm-grants');
    await migration.query(`
      INSERT INTO public.farm_grants (id, organization_id, membership_id, farm_id, role)
      VALUES
        ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'manager'),
        ($5::uuid, $2::uuid, $6::uuid, $4::uuid, 'worker'),
        ($7::uuid, $2::uuid, $8::uuid, $4::uuid, 'viewer'),
        ($9::uuid, $2::uuid, $10::uuid, $4::uuid, 'manager'),
        ($11::uuid, $2::uuid, $12::uuid, $4::uuid, 'manager'),
        ($13::uuid, $2::uuid, $14::uuid, $15::uuid, 'manager'),
        ($16::uuid, $2::uuid, $17::uuid, $4::uuid, 'worker')
    `, [
      randomUUID(), organizationId, memberships.manager, farmAId,
      randomUUID(), memberships.worker,
      randomUUID(), memberships.viewer,
      randomUUID(), memberships.orgviewer,
      randomUUID(), memberships.suspended,
      randomUUID(), memberships.crossfarm, farmBId,
      randomUUID(), memberships.workerb,
    ]);

    stage('setup-read-farm-clocks');
    const clockRows = await migration.query(
      'SELECT farm_id, continuity_epoch::TEXT AS epoch, revision::TEXT AS revision FROM public.farm_clocks WHERE organization_id = $1::uuid AND farm_id = ANY($2::uuid[])',
      [organizationId, [farmAId, farmBId, farmCId]],
    );
    assert(clockRows.rows.length === 3, 'FIXTURE_FARM_CLOCKS_MISSING');
    const farmEpochs = new Map(clockRows.rows.map((row) => [row.farm_id, row.epoch]));
    const farmRevisions = new Map(clockRows.rows.map((row) => [row.farm_id, BigInt(row.revision)]));
    for (const farmId of [farmAId, farmBId, farmCId]) {
      assert(farmEpochs.get(farmId) === '1' && farmRevisions.get(farmId) === 1n, 'FIXTURE_FARM_CLOCK_INVALID');
    }

    const policyVersion = async () => {
      const row = await migration.query('SELECT policy_version::TEXT AS v FROM public.organizations WHERE id = $1::uuid', [organizationId]);
      return row.rows[0]?.v;
    };
    const clockRevision = async (farmId) => {
      const row = await migration.query(
        'SELECT revision::TEXT AS r FROM public.farm_clocks WHERE organization_id = $1::uuid AND farm_id = $2::uuid',
        [organizationId, farmId],
      );
      return row.rows[0] ? BigInt(row.rows[0].r) : null;
    };
    const domainCounts = async (orgId, farmId, operationId) => {
      const result = await migration.query(`
        SELECT
          (SELECT count(*)::INTEGER FROM public.applied_operations WHERE organization_id = $1::uuid AND operation_id = $3::uuid AND outcome = 'applied') AS applied_proofs,
          (SELECT count(*)::INTEGER FROM public.applied_operations WHERE organization_id = $1::uuid AND operation_id = $3::uuid AND outcome = 'rejected') AS rejected_proofs,
          (SELECT count(*)::INTEGER FROM public.change_sets WHERE organization_id = $1::uuid AND farm_id = $2::uuid AND operation_id = $3::uuid) AS changes,
          (SELECT count(*)::INTEGER FROM public.audit_events WHERE organization_id = $1::uuid AND farm_id = $2::uuid AND operation_id = $3::uuid) AS audits,
          (SELECT policy_version::TEXT FROM public.organizations WHERE id = $1::uuid) AS policy_version,
          (SELECT revision::TEXT FROM public.farm_clocks WHERE organization_id = $1::uuid AND farm_id = $2::uuid) AS clock_revision
      `, [orgId, farmId, operationId]);
      return result.rows[0];
    };
    const countDomainRow = async (resourceKey, farmId, id) => {
      const table = DOMAIN_TABLES[resourceKey];
      if (!domainTables.get(table)) return null;
      try {
        const row = await migration.query(
          `SELECT count(*)::INTEGER AS n FROM public.${table} WHERE organization_id = $1::uuid AND farm_id = $2::uuid AND id = $3::uuid`,
          [organizationId, farmId, id],
        );
        return row.rows[0].n;
      } catch { return null; }
    };

    // A rejected write must leave no applied proof, no change set, no audit event,
    // no clock revision bump, no policy-version change, and no domain row.
    const expectNoDomainMutation = async (farmId, operationId, policyBefore, revisionBefore, code) => {
      const counts = await domainCounts(organizationId, farmId, operationId);
      assert(counts.applied_proofs === 0 && counts.changes === 0 && counts.audits === 0, `${code}_PARTIAL_MUTATION`);
      assert(counts.policy_version === policyBefore, `${code}_POLICY_VERSION_CHANGED`);
      assert(counts.clock_revision === null || BigInt(counts.clock_revision) === revisionBefore, `${code}_CLOCK_REVISION_CHANGED`);
    };
    const expectDomainApplied = async (farmId, operationId, policyBefore, code) => {
      const counts = await domainCounts(organizationId, farmId, operationId);
      assert(counts.applied_proofs === 1 && counts.changes === 1 && counts.audits === 1, `${code}_KERNEL_RECORDS_INCOMPLETE`);
      assert(counts.policy_version === policyBefore, `${code}_POLICY_VERSION_CHANGED`);
    };
    const trackRevision = (farmId, revisionText, code) => {
      const actual = BigInt(revisionText);
      const expected = farmRevisions.get(farmId);
      if (expected !== undefined) farmRevisions.set(farmId, actual);
      if (expected !== undefined) assert(actual === expected + 1n, `${code}_REVISION_GAP`);
    };
    const trackRevisionFromClock = async (farmId, code) => {
      const actual = await clockRevision(farmId);
      assert(actual !== null, `${code}_CLOCK_MISSING`);
      const expected = farmRevisions.get(farmId);
      if (expected !== undefined) farmRevisions.set(farmId, actual);
      if (expected !== undefined) assert(actual === expected + 1n, `${code}_REVISION_GAP`);
    };

    // DomainMutationResponse per spec04 §5.1:
    // {data:{operationId, outcome, revision, <resourceView>}, meta:{schemaVersion, asOf, scopePolicyVersion}}
    const applyDomainIntent = async (response, operationId, resourceKey, farmId, code) => {
      const body = await expectJson(response, 200, code);
      const data = body?.data;
      assert(data && typeof data === 'object', `${code}_DATA_MISSING`);
      assert(data.operationId === operationId, `${code}_OPERATION_ID_MISMATCH`);
      assert(data.outcome === 'applied', `${code}_OUTCOME_${data.outcome ?? 'MISSING'}`);
      assert(typeof data.revision === 'string' && REVISION_DECIMAL.test(data.revision), `${code}_REVISION_INVALID`);
      const view = data[resourceKey];
      assert(view && typeof view === 'object' && !Array.isArray(view), `${code}_RESOURCE_VIEW_MISSING`);
      const meta = body?.meta;
      assert(meta && typeof meta === 'object' && typeof meta.schemaVersion === 'string' && meta.schemaVersion.length > 0, `${code}_META_MISSING`);
      assert(typeof meta.asOf === 'string' && ISO_INSTANT.test(meta.asOf), `${code}_AS_OF_INVALID`);
      assert(typeof meta.scopePolicyVersion === 'string' && POSITIVE_DECIMAL.test(meta.scopePolicyVersion), `${code}_SCOPE_POLICY_VERSION_INVALID`);
      trackRevision(farmId, data.revision, code);
      return { body, view };
    };
    const listEntry = async (token, orgId, farmId, slug, pluralKey, id, code) => {
      const response = await domainList(token, orgId, farmId, slug);
      const body = await expectJson(response, 200, code);
      const items = body?.data?.[pluralKey];
      assert(Array.isArray(items), `${code}_LIST_MISSING`);
      return items.find((item) => item.id === id);
    };

    // ---- shared intended IDs and resource configs (spec04 §5.1 payload shapes) ----
    const ids = {};
    const versions = new Map();
    const epoch = farmEpochs.get(farmAId);
    // ---- P07 fixtures: deterministic SQL seed on farm A (read-side suite) ----
    // The write/kernel path is covered by the P06 suite; here the aggregates
    // are the system under test, so fixtures are inserted directly to pin exact
    // dates/statuses. farmly_migration bypasses RLS via *_migration_access.
    stage('p07-seed-domain-fixtures');

    const z1 = randomUUID(); // active crop_plot
    const z2 = randomUUID(); // active water
    const z3 = randomUUID(); // archived livestock_area — excluded from totals
    const sp1 = randomUUID(); // active species (kg)
    const sp2 = randomUUID(); // archived species — excluded
    const pl1 = randomUUID(); // active planting
    const pl2 = randomUUID(); // harvested planting — total but not active
    const herdB = randomUUID(); // batch herd: 20 +5 -3 = 22 head
    const herdT = randomUUID(); // tracked herd: 3 alive + 1 sold
    const tank1 = randomUUID(); // active tank, capacity 5000, stored 3200
    const tank2 = randomUUID(); // archived tank — excluded
    const tmpl1 = randomUUID(); // task template parent
    const harvest1 = randomUUID(); // active, 12.5 kg today
    const harvest2 = randomUUID(); // active, 30.0 kg yesterday
    const harvest3 = randomUUID(); // voided, 99 kg today — excluded from totals
    const rec1 = randomUUID(); const rec2 = randomUUID(); const rec3 = randomUUID();
    const occIds = { doneToday: randomUUID(), skippedOld: randomUUID(), openToday: randomUUID(), openOverdue: randomUUID(), doneOld1: randomUUID(), doneOld2: randomUUID(), doneOld3: randomUUID() };
    const tz = 'Asia/Ho_Chi_Minh';
    const opId = () => randomUUID();

    await migration.query('BEGIN');
    try {
      await migration.query(`
        INSERT INTO public.zones (organization_id, farm_id, id, name, type, geometry, status)
        VALUES
          ($1, $2, $3, 'P07 plot one', 'crop_plot', '{"points":[{"x":"0.1","y":"0.1"},{"x":"0.2","y":"0.1"},{"x":"0.2","y":"0.2"},{"x":"0.1","y":"0.2"}]}', 'active'),
          ($1, $2, $4, 'P07 water zone', 'water', '{"points":[{"x":"0.5","y":"0.5"},{"x":"0.6","y":"0.5"},{"x":"0.6","y":"0.6"},{"x":"0.5","y":"0.6"}]}', 'active'),
          ($1, $2, $5, 'P07 archived zone', 'livestock_area', '{"points":[{"x":"0.7","y":"0.7"},{"x":"0.8","y":"0.7"},{"x":"0.8","y":"0.8"},{"x":"0.7","y":"0.8"}]}', 'archived')
      `, [organizationId, farmAId, z1, z2, z3]);
      await migration.query(`
        INSERT INTO public.crop_species (organization_id, farm_id, id, name, harvest_unit, status)
        VALUES ($1, $2, $3, 'P07 tomato', 'kg', 'active'), ($1, $2, $4, 'P07 retired species', 'pieces', 'archived')
      `, [organizationId, farmAId, sp1, sp2]);
      await migration.query(`
        INSERT INTO public.plantings (organization_id, farm_id, id, crop_species_id, plot_id, status, sowing_date)
        VALUES ($1, $2, $3, $4, $5, 'active', CURRENT_DATE - 40), ($1, $2, $6, $4, $5, 'harvested', CURRENT_DATE - 90)
      `, [organizationId, farmAId, pl1, sp1, z1, pl2]);
      await migration.query(`
        INSERT INTO public.herds (organization_id, farm_id, id, mode, species, status)
        VALUES ($1, $2, $3, 'batch', 'chicken', 'active'), ($1, $2, $4, 'tracked', 'cattle', 'active')
      `, [organizationId, farmAId, herdB, herdT]);
      await migration.query(`
        INSERT INTO public.livestock_movements (organization_id, farm_id, id, herd_id, movement_type, delta, occurred_at, operation_id)
        VALUES
          ($1, $2, $3, $6, 'stock_in', 20, CURRENT_TIMESTAMP - INTERVAL '10 days', $7),
          ($1, $2, $4, $6, 'stock_in', 5, CURRENT_TIMESTAMP - INTERVAL '5 days', $7),
          ($1, $2, $5, $6, 'stock_out', -3, CURRENT_TIMESTAMP - INTERVAL '2 days', $7)
      `, [organizationId, farmAId, randomUUID(), randomUUID(), randomUUID(), herdB, opId()]);
      await migration.query(`
        INSERT INTO public.animals (organization_id, farm_id, id, herd_id, tag, status, archived)
        VALUES
          ($1, $2, $3, $6, 'COW-1', 'alive', false),
          ($1, $2, $4, $6, 'COW-2', 'alive', false),
          ($1, $2, $5, $6, 'COW-3', 'alive', false),
          ($1, $2, $7, $6, 'COW-4', 'sold', false)
      `, [organizationId, farmAId, randomUUID(), randomUUID(), randomUUID(), herdT, randomUUID()]);
      await migration.query(`
        INSERT INTO public.water_tanks (organization_id, farm_id, id, name, zone_id, capacity_litres, stored_litres, status)
        VALUES ($1, $2, $3, 'P07 main tank', $4, 5000, 3200, 'active'), ($1, $2, $5, 'P07 old tank', $4, 2000, 500, 'archived')
      `, [organizationId, farmAId, tank1, z2, tank2]);
      await migration.query(`
        INSERT INTO public.water_readings (organization_id, farm_id, id, tank_id, stored_litres, capacity_snapshot_litres, source, measured_at, operation_id)
        VALUES ($1, $2, $3, $4, 3200, 5000, 'manual', CURRENT_TIMESTAMP - INTERVAL '3 hours', $5)
      `, [organizationId, farmAId, randomUUID(), tank1, opId()]);
      await migration.query(`
        INSERT INTO public.water_usages (organization_id, farm_id, id, tank_id, usage_litres, usage_date, note, operation_id)
        VALUES
          ($1, $2, $3, $4, 450, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'morning irrigation', $6),
          ($1, $2, $7, $4, 300, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 1, 'yesterday', $6)
      `, [organizationId, farmAId, randomUUID(), tank1, tz, opId(), randomUUID()]);
      await migration.query(`
        INSERT INTO public.task_templates (organization_id, farm_id, id, title, kind, recurrence, starts_on)
        VALUES ($1, $2, $3, 'P07 feeding', 'feeding', '{"freq":"daily"}', CURRENT_DATE - 30)
      `, [organizationId, farmAId, tmpl1]);
      // Eligible occurrences for operations-health.v1: 4 done + 1 skipped = 80%.
      // Plus: 1 open today, 1 open overdue (due_at in the past).
      await migration.query(`
        INSERT INTO public.task_occurrences
          (organization_id, farm_id, id, template_id, occurrence_date, slot, status, due_at)
        VALUES
          ($1, $2, $3, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'morning', 'done', CURRENT_TIMESTAMP - INTERVAL '5 hours'),
          ($1, $2, $6, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 1, 'morning', 'done', NULL),
          ($1, $2, $7, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 2, 'morning', 'done', NULL),
          ($1, $2, $8, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 3, 'morning', 'done', NULL),
          ($1, $2, $9, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 4, 'morning', 'skipped', NULL),
          ($1, $2, $10, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'evening', 'open', CURRENT_TIMESTAMP + INTERVAL '4 hours'),
          ($1, $2, $11, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 1, 'noon', 'open', CURRENT_TIMESTAMP - INTERVAL '2 hours')
      `, [organizationId, farmAId, occIds.doneToday, tmpl1, tz, occIds.doneOld1, occIds.doneOld2, occIds.doneOld3, occIds.skippedOld, occIds.openToday, occIds.openOverdue]);
      // Harvests: 12.5 kg today + 30.0 kg yesterday active; 99 kg voided (excluded).
      await migration.query(`
        INSERT INTO public.harvest_heads (organization_id, farm_id, harvest_id, planting_id, effective_record_id, status, void_reason)
        VALUES
          ($1, $2, $3, $6, $7, 'active', NULL),
          ($1, $2, $4, $6, $8, 'active', NULL),
          ($1, $2, $5, $6, $9, 'voided', 'double entry')
      `, [organizationId, farmAId, harvest1, harvest2, harvest3, pl1, rec1, rec2, rec3]);
      await migration.query(`
        INSERT INTO public.harvest_records (organization_id, farm_id, id, harvest_id, planting_id, quantity_kg, harvest_date, operation_id)
        VALUES
          ($1, $2, $3, $6, $7, 12.5, (CURRENT_TIMESTAMP AT TIME ZONE $8)::DATE, $9),
          ($1, $2, $4, $10, $7, 30.0, (CURRENT_TIMESTAMP AT TIME ZONE $8)::DATE - 1, $9),
          ($1, $2, $5, $11, $7, 99.0, (CURRENT_TIMESTAMP AT TIME ZONE $8)::DATE, $9)
      `, [organizationId, farmAId, rec1, rec2, rec3, harvest1, pl1, tz, opId(), harvest2, harvest3]);
      await migration.query(`
        INSERT INTO public.moisture_readings (organization_id, farm_id, id, zone_id, value, method, source, measured_at, operation_id)
        VALUES
          ($1, $2, $3, $4, 41.50, 'vwc_percent', 'manual', CURRENT_TIMESTAMP - INTERVAL '6 hours', $5),
          ($1, $2, $6, $4, 38.00, 'vwc_percent', 'manual', CURRENT_TIMESTAMP - INTERVAL '2 days', $5),
          ($1, $2, $7, $8, 55.25, 'relative_percent', 'manual', CURRENT_TIMESTAMP - INTERVAL '12 hours', $5)
      `, [organizationId, farmAId, randomUUID(), z1, opId(), randomUUID(), randomUUID(), z2]);
      await migration.query(`
        INSERT INTO public.production_records (organization_id, farm_id, id, herd_id, product, quantity, unit, recorded_on, operation_id)
        VALUES
          ($1, $2, $3, $4, 'milk', 12.5, 'litre', (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, $6),
          ($1, $2, $7, $8, 'eggs', 30, 'pieces', (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE - 1, $6)
      `, [organizationId, farmAId, randomUUID(), herdT, tz, opId(), randomUUID(), herdB]);
      await migration.query('COMMIT');
    } catch (error) {
      await migration.query('ROLLBACK').catch(() => {});
      throw error;
    }

    // Farm B gets its own snapshot — cross-scope isolation check later.
    const farmBZone = randomUUID();
    await migration.query(`
      INSERT INTO public.zones (organization_id, farm_id, id, name, type, geometry, status)
      VALUES ($1, $2, $3, 'P07 farm B zone', 'crop_plot', '{"points":[{"x":"0.1","y":"0.1"},{"x":"0.2","y":"0.1"},{"x":"0.2","y":"0.2"},{"x":"0.1","y":"0.2"}]}', 'active')
    `, [organizationId, farmBId, farmBZone]);

    const getJson = (token, path) => fetch(`${origin}${path}`, { headers: httpHeaders(token) });
    const farmScoped = (farmId, suffix) => `/v1/organizations/${organizationId}/farms/${farmId}/${suffix}`;

    // ---- P07 cases ----------------------------------------------------------

    stage('p07-location-kernel');
    await check('FARM_UPDATE_LOCATION_APPLY', async () => {
      const current = await migration.query('SELECT version FROM public.farms WHERE id = $1', [farmAId]);
      const op = intent('farm.update', farmAId, { location: '21.1,105.4' }, '1', { baseVersion: current.rows[0].version });
      const response = await farmPatch(owner.token, organizationId, farmAId, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'farm', farmAId, 'FARM_UPDATE_LOCATION_APPLY');
      assert(view.location === '21.1,105.4', 'FARM_UPDATE_LOCATION_VIEW_MISSING');
    });
    await check('FARM_UPDATE_LOCATION_EXACT_REJECTED', async () => {
      const current = await migration.query('SELECT version FROM public.farms WHERE id = $1', [farmAId]);
      const op = intent('farm.update', farmAId, { location: '21.12345,105.4321' }, '1', { baseVersion: current.rows[0].version });
      const response = await farmPatch(owner.token, organizationId, farmAId, op);
      await expectDomainRejected(response, 'FARM_UPDATE_LOCATION_EXACT_REJECTED', { operationId: op.operationId });
    });
    await check('FARM_CREATE_WITH_LOCATION', async () => {
      const farmIntent = intent('farm.create', randomUUID(), {
        name: `P07 located farm ${s8()}`, timezone: tz, location: '10.8,106.6',
      }, '1');
      const response = await orgFarmCreate(owner.token, organizationId, farmIntent);
      const body = await expectJson(response, 200, 'FARM_CREATE_WITH_LOCATION');
      assert(body?.data?.outcome === 'applied', 'FARM_CREATE_WITH_LOCATION_NOT_APPLIED');
      assert(body?.data?.farm?.location === '10.8,106.6', 'FARM_CREATE_LOCATION_VIEW_MISSING');
      ids.farmWithLocationId = farmIntent.resourceId;
    });

    stage('p07-summary');
    await check('SUMMARY_TOTALS_AND_HEALTH', async () => {
      const response = await getJson(owner.token, farmScoped(farmAId, 'summary'));
      const body = await expectJson(response, 200, 'SUMMARY_TOTALS_AND_HEALTH');
      const data = body?.data;
      assert(data?.farm?.farmId === farmAId && data.farm.location === '21.1,105.4', 'SUMMARY_FARM_VIEW_INVALID');
      assert(data?.zones?.total === 2 && data.zones.byType?.crop_plot === 1 && data.zones.byType?.water === 1, 'SUMMARY_ZONES_INVALID');
      assert(data?.crops?.species === 1 && data.crops.plantings === 2 && data.crops.plantingsActive === 1, 'SUMMARY_CROPS_INVALID');
      assert(data?.livestock?.herds === 2 && data.livestock.headcount === 25 && data.livestock.trackedAnimals === 3, 'SUMMARY_LIVESTOCK_INVALID');
      const tasks = data?.tasks;
      assert(tasks?.openToday === 1 && tasks.doneToday === 1 && tasks.overdue === 1, 'SUMMARY_TASKS_TODAY_INVALID');
      const health = tasks?.health;
      assert(health?.formula === 'operations-health.v1' && health.status === 'ok', 'SUMMARY_HEALTH_STATUS_INVALID');
      assert(health.eligible === 5 && health.done === 4 && health.ratio === '0.8000', 'SUMMARY_HEALTH_RATIO_INVALID');
      assert(data?.harvests?.heads === 3 && data.harvests.voided === 1 && data.harvests.totalKg === '42.5000', 'SUMMARY_HARVESTS_INVALID');
      const water = data?.water;
      assert(water?.tanks === 1 && water.capacityLitres === '5000.0000' && water.storedLitres === '3200.0000'
        && water.usedTodayLitres === '450.0000' && typeof water.levelAsOf === 'string', 'SUMMARY_WATER_INVALID');
      assert(data?.moisture?.zonesWithReading === 2 && typeof data.moisture.latestMeasuredAt === 'string', 'SUMMARY_MOISTURE_INVALID');
      assert(typeof body?.meta?.asOf === 'string' && ISO_INSTANT.test(body.meta.asOf), 'SUMMARY_ASOF_INVALID');
    });
    await check('SUMMARY_HEALTH_UNKNOWN_UNDER_MIN', async () => {
      const response = await getJson(owner.token, farmScoped(farmBId, 'summary'));
      const body = await expectJson(response, 200, 'SUMMARY_HEALTH_UNKNOWN_UNDER_MIN');
      const health = body?.data?.tasks?.health;
      assert(health?.status === 'unknown' && health.eligible === 0 && health.ratio === null, 'SUMMARY_HEALTH_UNKNOWN_INVALID');
    });
    await check('SUMMARY_VIEWER_READ_ONLY_OK', async () => {
      const response = await getJson(viewer.token, farmScoped(farmAId, 'summary'));
      const body = await expectJson(response, 200, 'SUMMARY_VIEWER_READ_ONLY_OK');
      assert(body?.data?.livestock?.headcount === 25, 'SUMMARY_VIEWER_SCOPE_MISMATCH');
    });
    await check('SUMMARY_FOREIGN_DENIED', async () => {
      const response = await getJson(foreignOwner.token, farmScoped(farmAId, 'summary'));
      await expectDenied(response, 'SUMMARY_FOREIGN_DENIED');
    });
    await check('SUMMARY_NO_ACTOR_UNAUTHENTICATED', async () => {
      const response = await fetch(`${origin}${farmScoped(farmAId, 'summary')}`);
      assert(response.status === 401, 'SUMMARY_NO_ACTOR_UNAUTHENTICATED');
    });

    stage('p07-analytics');
    await check('ANALYTICS_SERIES_AND_VOIDED_EXCLUSION', async () => {
      const response = await getJson(owner.token, farmScoped(farmAId, 'analytics') + '?days=30');
      const body = await expectJson(response, 200, 'ANALYTICS_SERIES_AND_VOIDED_EXCLUSION');
      const data = body?.data;
      assert(data?.range?.days === 30 && data.range.timezone === tz, 'ANALYTICS_RANGE_INVALID');
      const harvestSeries = data?.harvests?.series;
      assert(Array.isArray(harvestSeries) && harvestSeries.length === 2, 'ANALYTICS_HARVEST_DAYS_INVALID');
      const totalKg = harvestSeries.reduce((sum, row) => sum + Number(row.quantityKg), 0);
      assert(Math.abs(totalKg - 42.5) < 0.0001, 'ANALYTICS_HARVEST_TOTAL_INCLUDES_VOIDED');
      assert(data.harvests.voidedExcluded === 1, 'ANALYTICS_VOIDED_COUNT_INVALID');
      const production = data?.production?.series;
      assert(Array.isArray(production) && production.length === 2, 'ANALYTICS_PRODUCTION_INVALID');
      const milk = production.find((row) => row.product === 'milk');
      assert(milk?.unit === 'litre' && Number(milk.quantity) === 12.5, 'ANALYTICS_MILK_INVALID');
      const water = data?.waterUsage?.series;
      assert(Array.isArray(water) && water.length === 2, 'ANALYTICS_WATER_INVALID');
      const taskSeries = data?.tasks?.series;
      assert(Array.isArray(taskSeries) && taskSeries.length >= 5, 'ANALYTICS_TASKS_INVALID');
    });
    await check('ANALYTICS_DAYS_VALIDATION', async () => {
      const bad = await getJson(owner.token, farmScoped(farmAId, 'analytics') + '?days=0');
      assert(bad.status === 400, 'ANALYTICS_DAYS_ZERO_ACCEPTED');
      const huge = await getJson(owner.token, farmScoped(farmAId, 'analytics') + '?days=500');
      assert(huge.status === 400, 'ANALYTICS_DAYS_HUGE_ACCEPTED');
      const ok = await getJson(owner.token, farmScoped(farmAId, 'analytics') + '?days=1');
      const body = await expectJson(ok, 200, 'ANALYTICS_DAYS_ONE');
      assert(body?.data?.range?.days === 1, 'ANALYTICS_DAYS_ONE_RANGE');
    });

    stage('p07-weather');
    await check('WEATHER_NO_SNAPSHOT', async () => {
      const response = await getJson(owner.token, farmScoped(farmAId, 'weather'));
      const body = await expectJson(response, 200, 'WEATHER_NO_SNAPSHOT');
      assert(body?.data?.status === 'unavailable' && body.data.reason === 'no_snapshot', 'WEATHER_NO_SNAPSHOT_INVALID');
      assert(body?.data?.provider === undefined && body.data.current === undefined, 'WEATHER_NO_SNAPSHOT_LEAK');
    });
    await check('WEATHER_SNAPSHOT_WRITE_AND_FRESH', async () => {
      const write = await migration.query(
        `SELECT public.farmly_record_weather_snapshot($1, $2, 'open-meteo', '21.1,105.4', CURRENT_TIMESTAMP + INTERVAL '30 minutes', $3::jsonb) AS id`,
        [organizationId, farmAId, JSON.stringify({ temperatureC: 26.8, humidityPercent: 78, windKph: 12.3, weatherCode: 3 })],
      );
      assert(write.rows[0]?.id, 'WEATHER_SNAPSHOT_NOT_WRITTEN');
      const response = await getJson(owner.token, farmScoped(farmAId, 'weather'));
      const body = await expectJson(response, 200, 'WEATHER_SNAPSHOT_WRITE_AND_FRESH');
      const data = body?.data;
      assert(data?.status === 'fresh', 'WEATHER_FRESH_STATUS_INVALID');
      assert(data.provider === 'open-meteo' && data.gridRef === '21.1,105.4', 'WEATHER_PROVENANCE_INVALID');
      assert(typeof data.fetchedAt === 'string' && ISO_INSTANT.test(data.fetchedAt), 'WEATHER_FETCHED_AT_INVALID');
      assert(data.current?.temperatureC === 26.8 && data.current?.weatherCode === 3, 'WEATHER_PAYLOAD_INVALID');
    });
    await check('WEATHER_SNAPSHOT_STALE', async () => {
      await migration.query(
        `UPDATE public.weather_snapshots SET fetched_at = CURRENT_TIMESTAMP - INTERVAL '2 hours'
          WHERE organization_id = $1 AND farm_id = $2`,
        [organizationId, farmAId],
      );
      const response = await getJson(owner.token, farmScoped(farmAId, 'weather'));
      const body = await expectJson(response, 200, 'WEATHER_SNAPSHOT_STALE');
      assert(body?.data?.status === 'stale' && body.data.reason === 'expired', 'WEATHER_STALE_INVALID');
      assert(body?.data?.current?.temperatureC === 26.8, 'WEATHER_STALE_PAYLOAD_MISSING');
      await migration.query(
        `UPDATE public.weather_snapshots SET fetched_at = CURRENT_TIMESTAMP
          WHERE organization_id = $1 AND farm_id = $2`,
        [organizationId, farmAId],
      );
    });
    await check('WEATHER_GRID_MISMATCH_REJECTED', async () => {
      let failed = false;
      try {
        await migration.query(
          `SELECT public.farmly_record_weather_snapshot($1, $2, 'open-meteo', '10.0,106.0', CURRENT_TIMESTAMP, $3::jsonb)`,
          [organizationId, farmAId, JSON.stringify({ temperatureC: 30, weatherCode: 1 })],
        );
      } catch (error) { failed = true; }
      assert(failed, 'WEATHER_GRID_MISMATCH_ACCEPTED');
    });
    await check('WEATHER_NO_LOCATION_REJECTED', async () => {
      let failed = false;
      try {
        await migration.query(
          `SELECT public.farmly_record_weather_snapshot($1, $2, 'open-meteo', '10.0,106.0', CURRENT_TIMESTAMP, $3::jsonb)`,
          [organizationId, farmBId, JSON.stringify({ temperatureC: 30, weatherCode: 1 })],
        );
      } catch (error) { failed = true; }
      assert(failed, 'WEATHER_NO_LOCATION_ACCEPTED');
    });
    await check('WEATHER_FARM_B_CROSS_SCOPE_ISOLATION', async () => {
      const response = await getJson(owner.token, farmScoped(farmBId, 'weather'));
      const body = await expectJson(response, 200, 'WEATHER_FARM_B_CROSS_SCOPE_ISOLATION');
      assert(body?.data?.status === 'unavailable' && body.data.reason === 'no_location', 'WEATHER_FARMB_STATE_INVALID');
    });
    await check('WEATHER_DISABLED_KILL_SWITCH', async () => {
      apiEnvironment.weatherEnabled = false;
      try {
        const response = await getJson(owner.token, farmScoped(farmAId, 'weather'));
        const body = await expectJson(response, 200, 'WEATHER_DISABLED_KILL_SWITCH');
        assert(body?.data?.status === 'unavailable' && body.data.reason === 'disabled', 'WEATHER_DISABLED_INVALID');
      } finally {
        apiEnvironment.weatherEnabled = true;
      }
    });
    await check('WEATHER_LOCATION_CLEARED', async () => {
      const current = await migration.query('SELECT version FROM public.farms WHERE id = $1', [farmAId]);
      const op = intent('farm.update', farmAId, { location: null }, '1', { baseVersion: current.rows[0].version });
      const response = await farmPatch(owner.token, organizationId, farmAId, op);
      await applyDomainIntent(response, op.operationId, 'farm', farmAId, 'WEATHER_LOCATION_CLEARED');
      const weather = await getJson(owner.token, farmScoped(farmAId, 'weather'));
      const body = await expectJson(weather, 200, 'WEATHER_LOCATION_CLEARED');
      assert(body?.data?.status === 'unavailable' && body.data.reason === 'no_location', 'WEATHER_CLEARED_STATE_INVALID');
      // Restore the grid for downstream determinism.
      const restore = await migration.query('SELECT version FROM public.farms WHERE id = $1', [farmAId]);
      const restoreOp = intent('farm.update', farmAId, { location: '21.1,105.4' }, '1', { baseVersion: restore.rows[0].version });
      const restoreResponse = await farmPatch(owner.token, organizationId, farmAId, restoreOp);
      await applyDomainIntent(restoreResponse, restoreOp.operationId, 'farm', farmAId, 'WEATHER_LOCATION_RESTORE');
    });
    await check('WEATHER_REFRESH_TARGETS_FUNCTION', async () => {
      // Fresh farm A snapshot must NOT appear as a refresh target; farm B has
      // no location so it is never eligible.
      const tenantClient = new Client({ connectionString: tenantConnectionString(`farmly-weather-targets-${suffix}`) });
      await tenantClient.connect();
      try {
        const rows = await tenantClient.query('SELECT farm_id FROM public.farmly_weather_refresh_targets(3600)');
        assert(!rows.rows.some((row) => row.farm_id === farmAId), 'WEATHER_TARGETS_FRESH_FARM_LISTED');
        assert(!rows.rows.some((row) => row.farm_id === farmBId), 'WEATHER_TARGETS_NOLOCATION_LISTED');
        assert(rows.rows.some((row) => row.farm_id === ids.farmWithLocationId), 'WEATHER_TARGETS_MISSING_SNAPSHOT_FARM');
      } finally {
        await tenantClient.end();
      }
    });

  } finally {
    if (app) await app.close().catch(() => {});
    if (tenant) await tenant.onModuleDestroy().catch(() => {});
    if (migration) {
      await migration.query('ROLLBACK').catch(() => {});
      // Best-effort domain fixture cleanup before org cascade; domain tables
      // may not exist yet, so every delete is independently tolerated.
      // Leaf-first delete order; harvest_heads.effective_record_id ->
      // harvest_records is DEFERRABLE INITIALLY DEFERRED, so that circular pair
      // is deleted inside one transaction after correction_proposals (whose
      // head FK is immediate) is already gone.
      for (const table of ['task_transitions', 'task_occurrences', 'correction_proposals', 'weather_snapshots']) {
        await migration.query(`DELETE FROM public.${table} WHERE organization_id = ANY($1::uuid[])`, [organizationIds]).catch(() => {});
      }
      await migration.query('BEGIN');
      await migration.query('SET CONSTRAINTS public.harvest_heads_effective_fkey DEFERRED');
      for (const table of ['harvest_records', 'harvest_heads']) {
        await migration.query(`DELETE FROM public.${table} WHERE organization_id = ANY($1::uuid[])`, [organizationIds]).catch(() => {});
      }
      await migration.query('COMMIT').catch(() => migration.query('ROLLBACK').catch(() => {}));
      for (const table of ['task_templates', 'planting_events', 'animal_observations', 'production_records', 'moisture_readings', 'water_readings', 'water_usages', 'livestock_movements', 'animals', 'herds', 'plantings', 'crop_species', 'water_tanks', 'zones']) {
        await migration.query(`DELETE FROM public.${table} WHERE organization_id = ANY($1::uuid[])`, [organizationIds]).catch(() => {});
      }
      await migration.query('DELETE FROM public.organizations WHERE id = ANY($1::uuid[])', [organizationIds]).catch((error) => { cleanupError = error; });
      await migration.query('DELETE FROM auth."user" WHERE id = ANY($1::text[])', [users.map((user) => user.id)]).catch((error) => { cleanupError = error; });
      await migration.end().catch((error) => { cleanupError = cleanupError ?? error; });
    }
  }

  if (operationError) {
    const code = operationError && typeof operationError === 'object' && typeof operationError.code === 'string'
      && SAFE_CODE.test(operationError.code) ? operationError.code : 'UNEXPECTED_FAILURE';
    process.stderr.write(JSON.stringify({ status: 'failed', stage: operationStage, code }) + '\n');
    process.exitCode = 1;
    return;
  }
  if (cleanupError) {
    process.stderr.write(JSON.stringify({ status: 'failed', stage: 'fixture-cleanup', code: 'FIXTURE_CLEANUP_FAILED' }) + '\n');
    process.exitCode = 1;
    return;
  }
  const failed = results.filter((result) => result.status === 'failed');
  const report = {
    status: failed.length === 0 ? 'passed' : 'failed',
    scope: 'P07 home/weather/analytics read surface (spec04 §5.3, spec03 P-05)',
    surface: moduleMode,
    total: results.length,
    passed: results.length - failed.length,
    failed: failed.length,
    firstFailure: failed[0] ?? null,
    failures: failed,
  };
  process.stdout.write(JSON.stringify(report) + '\n');
  if (failed.length > 0) process.exitCode = 1;
}

await main();
