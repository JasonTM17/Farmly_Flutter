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
    // ---- P08 fixtures: deterministic SQL seed on farm A -------------------
    // Read-side fixtures are direct SQL (the kernel write path is covered by
    // the mutation-kernel and operational-facts suites); every entity in the
    // bootstrap registry gets at least one row so coverage is assertable.
    stage('p08-seed-domain-fixtures');
    const z1 = randomUUID();
    const z2 = randomUUID();
    const sp1 = randomUUID();
    const pl1 = randomUUID();
    const herdB = randomUUID(); // batch: 20 - 3 = 17 head
    const herdT = randomUUID(); // tracked: 2 alive animals
    const tank1 = randomUUID();
    const tmpl1 = randomUUID();
    const tz = 'Asia/Ho_Chi_Minh';
    const opId = () => randomUUID();

    await migration.query('BEGIN');
    try {
      await migration.query(`
        INSERT INTO public.zones (organization_id, farm_id, id, name, type, geometry, status)
        VALUES
          ($1, $2, $3, 'P08 plot one', 'crop_plot', '{"points":[{"x":"0.1","y":"0.1"},{"x":"0.2","y":"0.1"},{"x":"0.2","y":"0.2"},{"x":"0.1","y":"0.2"}]}', 'active'),
          ($1, $2, $4, 'P08 water zone', 'water', '{"points":[{"x":"0.5","y":"0.5"},{"x":"0.6","y":"0.5"},{"x":"0.6","y":"0.6"},{"x":"0.5","y":"0.6"}]}', 'active')
      `, [organizationId, farmAId, z1, z2]);
      await migration.query(`
        INSERT INTO public.crop_species (organization_id, farm_id, id, name, harvest_unit, status)
        VALUES ($1, $2, $3, 'P08 tomato', 'kg', 'active')
      `, [organizationId, farmAId, sp1]);
      await migration.query(`
        INSERT INTO public.plantings (organization_id, farm_id, id, crop_species_id, plot_id, status, sowing_date)
        VALUES ($1, $2, $3, $4, $5, 'active', CURRENT_DATE - 40)
      `, [organizationId, farmAId, pl1, sp1, z1]);
      await migration.query(`
        INSERT INTO public.herds (organization_id, farm_id, id, mode, species, status)
        VALUES ($1, $2, $3, 'batch', 'chicken', 'active'), ($1, $2, $4, 'tracked', 'cattle', 'active')
      `, [organizationId, farmAId, herdB, herdT]);
      await migration.query(`
        INSERT INTO public.livestock_movements (organization_id, farm_id, id, herd_id, movement_type, delta, occurred_at, operation_id)
        VALUES
          ($1, $2, $3, $5, 'stock_in', 20, CURRENT_TIMESTAMP - INTERVAL '10 days', $6),
          ($1, $2, $4, $5, 'stock_out', -3, CURRENT_TIMESTAMP - INTERVAL '2 days', $6)
      `, [organizationId, farmAId, randomUUID(), randomUUID(), herdB, opId()]);
      await migration.query(`
        INSERT INTO public.animals (organization_id, farm_id, id, herd_id, tag, status, archived)
        VALUES
          ($1, $2, $3, $5, 'COW-1', 'alive', false),
          ($1, $2, $4, $5, 'COW-2', 'alive', false)
      `, [organizationId, farmAId, randomUUID(), randomUUID(), herdT]);
      await migration.query(`
        INSERT INTO public.water_tanks (organization_id, farm_id, id, name, zone_id, capacity_litres, stored_litres, status)
        VALUES ($1, $2, $3, 'P08 main tank', $4, 5000, 3200, 'active')
      `, [organizationId, farmAId, tank1, z2]);
      await migration.query(`
        INSERT INTO public.water_readings (organization_id, farm_id, id, tank_id, stored_litres, capacity_snapshot_litres, source, measured_at, operation_id)
        VALUES ($1, $2, $3, $4, 3200, 5000, 'manual', CURRENT_TIMESTAMP - INTERVAL '3 hours', $5)
      `, [organizationId, farmAId, randomUUID(), tank1, opId()]);
      await migration.query(`
        INSERT INTO public.water_usages (organization_id, farm_id, id, tank_id, usage_litres, usage_date, note, operation_id)
        VALUES ($1, $2, $3, $4, 450, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'morning irrigation', $6)
      `, [organizationId, farmAId, randomUUID(), tank1, tz, opId()]);
      await migration.query(`
        INSERT INTO public.task_templates (organization_id, farm_id, id, title, kind, recurrence, starts_on)
        VALUES ($1, $2, $3, 'P08 feeding', 'feeding', '{"freq":"daily"}', CURRENT_DATE - 30)
      `, [organizationId, farmAId, tmpl1]);
      await migration.query(`
        INSERT INTO public.task_occurrences
          (organization_id, farm_id, id, template_id, occurrence_date, slot, status, due_at)
        VALUES
          ($1, $2, $3, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'morning', 'done', CURRENT_TIMESTAMP - INTERVAL '5 hours'),
          ($1, $2, $6, $4, (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, 'evening', 'open', CURRENT_TIMESTAMP + INTERVAL '4 hours')
      `, [organizationId, farmAId, randomUUID(), tmpl1, tz, randomUUID()]);
      await migration.query(`
        INSERT INTO public.moisture_readings (organization_id, farm_id, id, zone_id, value, method, source, measured_at, operation_id)
        VALUES ($1, $2, $3, $4, 41.50, 'vwc_percent', 'manual', CURRENT_TIMESTAMP - INTERVAL '6 hours', $5)
      `, [organizationId, farmAId, randomUUID(), z1, opId()]);
      await migration.query(`
        INSERT INTO public.production_records (organization_id, farm_id, id, herd_id, product, quantity, unit, recorded_on, operation_id)
        VALUES ($1, $2, $3, $4, 'milk', 12.5, 'litre', (CURRENT_TIMESTAMP AT TIME ZONE $5)::DATE, $6)
      `, [organizationId, farmAId, randomUUID(), herdT, tz, opId()]);
      await migration.query('COMMIT');
    } catch (error) {
      await migration.query('ROLLBACK').catch(() => {});
      throw error;
    }

    // Farm B marker row for cross-scope assertions.
    await migration.query(`
      INSERT INTO public.zones (organization_id, farm_id, id, name, type, geometry, status)
      VALUES ($1, $2, $3, 'P08 farm B zone', 'crop_plot', '{"points":[{"x":"0.1","y":"0.1"},{"x":"0.2","y":"0.1"},{"x":"0.2","y":"0.2"},{"x":"0.1","y":"0.2"}]}', 'active')
    `, [organizationId, farmBId, randomUUID()]);

    const getJson = (token, path) => fetch(`${origin}${path}`, { headers: httpHeaders(token) });
    const farmScoped = (farmId, suffix) => `/v1/organizations/${organizationId}/farms/${farmId}/${suffix}`;
    const bootstrapCreate = (token, farmId, operationId) => fetch(
      `${origin}${farmScoped(farmId, 'sync/bootstrap')}`,
      {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json', 'idempotency-key': operationId }),
        body: JSON.stringify({ operationId, payload: {} }),
      },
    );
    const bootstrapPage = (token, farmId, snapshotId, pageCursor) => getJson(
      token,
      `${farmScoped(farmId, `sync/bootstrap/${snapshotId}`)}${pageCursor === undefined ? '' : `?pageCursor=${encodeURIComponent(pageCursor)}`}`,
    );
    const changesGet = (token, farmId, cursor) => getJson(
      token, `${farmScoped(farmId, 'sync/changes')}${cursor === undefined ? '' : `?cursor=${encodeURIComponent(cursor)}`}`,
    );
    const collectBlocks = async (token, farmId, snapshotId, code) => {
      const blocks = [];
      let rows = 0;
      let pageCursor;
      let pages = 0;
      for (;;) {
        const response = await bootstrapPage(token, farmId, snapshotId, pageCursor);
        const body = await expectJson(response, 200, code);
        assert(Number.isInteger(body?.data?.pageIndex), `${code}_PAGE_INDEX_MISSING`);
        assert(Array.isArray(body?.data?.blocks), `${code}_BLOCKS_MISSING`);
        blocks.push(...body.data.blocks);
        rows += Number(body.data.rowCount);
        pages += 1;
        if (body?.page?.hasMore) {
          assert(typeof body.page.nextPageCursor === 'string', `${code}_NEXT_CURSOR_MISSING`);
          pageCursor = body.page.nextPageCursor;
        } else {
          assert(body?.page?.nextPageCursor === null, `${code}_NEXT_CURSOR_STALE`);
          break;
        }
      }
      return { blocks, rows, pages };
    };
    const entitiesIn = (blocks) => {
      const byEntity = new Map();
      for (const block of blocks) {
        assert(typeof block?.entity === 'string', 'BOOTSTRAP_BLOCK_ENTITY_MISSING');
        assert(Array.isArray(block?.records), 'BOOTSTRAP_BLOCK_RECORDS_MISSING');
        if (!byEntity.has(block.entity)) byEntity.set(block.entity, []);
        byEntity.get(block.entity).push(...block.records);
      }
      return byEntity;
    };

    // ---- P08 cases ----------------------------------------------------------

    stage('p08-bootstrap-create');
    let snapshotA;
    let snapshotACursor;
    await check('BOOTSTRAP_CREATE', async () => {
      const operationId = randomUUID();
      const response = await bootstrapCreate(owner.token, farmAId, operationId);
      const body = await expectJson(response, 200, 'BOOTSTRAP_CREATE');
      const data = body?.data;
      assert(data?.snapshotId === operationId, 'BOOTSTRAP_SNAPSHOT_ID_MISMATCH');
      snapshotA = operationId;
      snapshotACursor = data.changesCursor;
      assert(Number.isInteger(data?.chunkCount) && data.chunkCount >= 1, 'BOOTSTRAP_CHUNK_COUNT_INVALID');
      assert(Number.isInteger(data?.totalRows) && data.totalRows === 19, 'BOOTSTRAP_TOTAL_ROWS_INVALID');
      assert(Number.isInteger(data?.byteCount) && data.byteCount > 0, 'BOOTSTRAP_BYTES_INVALID');
      assert(data?.maxRows === 25000 && data?.maxBytes === 8388608, 'BOOTSTRAP_CAPS_MISSING');
      assert(data?.continuityEpoch === '1', 'BOOTSTRAP_EPOCH_INVALID');
      assert(typeof data?.scopePolicyVersion === 'string' && POSITIVE_DECIMAL.test(data.scopePolicyVersion), 'BOOTSTRAP_POLICY_INVALID');
      assert(data?.highWatermark === '1', 'BOOTSTRAP_WATERMARK_INVALID');
      assert(data?.prunedThroughRevision === '0', 'BOOTSTRAP_FLOOR_INVALID');
      assert(typeof data?.expiresAt === 'string' && Date.parse(data.expiresAt) > Date.now(), 'BOOTSTRAP_EXPIRY_INVALID');
      assert(typeof data?.changesCursor === 'string' && data.changesCursor.length > 20, 'BOOTSTRAP_CURSOR_MISSING');
      assert(body?.meta?.schemaVersion === 'farm-bootstrap.v1', 'BOOTSTRAP_SCHEMA_INVALID');
    });

    await check('BOOTSTRAP_IDEMPOTENT_REPLAY', async () => {
      const response = await bootstrapCreate(owner.token, farmAId, snapshotA);
      const body = await expectJson(response, 200, 'BOOTSTRAP_IDEMPOTENT');
      assert(body?.data?.snapshotId === snapshotA, 'BOOTSTRAP_IDEMPOTENT_ID_MISMATCH');
      const chunks = await migration.query(
        'SELECT count(*)::INTEGER AS n, max(chunk_count) AS cc FROM public.bootstrap_snapshot_chunks AS c JOIN public.bootstrap_snapshots AS s ON s.organization_id = c.organization_id AND s.farm_id = c.farm_id AND s.id = c.snapshot_id WHERE c.snapshot_id = $1::uuid',
        [snapshotA],
      );
      // Replay must not duplicate chunk rows.
      assert(chunks.rows[0].n === chunks.rows[0].cc, 'BOOTSTRAP_IDEMPOTENT_DUPLICATED');
    });

    await check('BOOTSTRAP_PAGE_WALK', async () => {
      const { blocks, rows, pages } = await collectBlocks(owner.token, farmAId, snapshotA, 'BOOTSTRAP_PAGE_WALK');
      const snap = await migration.query(
        'SELECT row_count::INTEGER AS rc, chunk_count::INTEGER AS cc FROM public.bootstrap_snapshots WHERE id = $1::uuid',
        [snapshotA],
      );
      assert(rows === snap.rows[0].rc, 'BOOTSTRAP_WALK_ROWS_MISMATCH');
      assert(pages === snap.rows[0].cc, 'BOOTSTRAP_WALK_PAGES_MISMATCH');
      const byEntity = entitiesIn(blocks);
      for (const entity of ['farm', 'zone', 'cropSpecies', 'planting', 'herd', 'animal', 'livestockMovement',
        'taskTemplate', 'taskOccurrence', 'waterTank', 'waterReading', 'waterUsage', 'moistureReading', 'productionRecord']) {
        assert((byEntity.get(entity) ?? []).length >= 1, `BOOTSTRAP_ENTITY_${entity.toUpperCase()}_MISSING`);
      }
      const farmRecord = byEntity.get('farm')[0];
      assert(farmRecord.farmId === farmAId && 'location' in farmRecord && farmRecord.version === 1, 'BOOTSTRAP_FARM_SHAPE_INVALID');
      const batchHerd = byEntity.get('herd').find((h) => h.id === herdB);
      assert(batchHerd?.headcount === 17, 'BOOTSTRAP_HEADCOUNT_INVALID');
      const zone = byEntity.get('zone')[0];
      assert('areaM2' in zone && typeof zone.geometry === 'object', 'BOOTSTRAP_ZONE_WIRE_SHAPE');
      const planting = byEntity.get('planting')[0];
      assert(planting.cropSpeciesId === sp1 && typeof planting.sowingDate === 'string', 'BOOTSTRAP_PLANTING_WIRE_SHAPE');
    });

    await check('BOOTSTRAP_EMPTY_FARM', async () => {
      const operationId = randomUUID();
      const response = await bootstrapCreate(owner.token, farmCId, operationId);
      const body = await expectJson(response, 200, 'BOOTSTRAP_EMPTY_FARM');
      assert(body?.data?.totalRows === 1 && body?.data?.chunkCount === 1, 'BOOTSTRAP_EMPTY_FARM_SHAPE');
      const { blocks } = await collectBlocks(owner.token, farmCId, operationId, 'BOOTSTRAP_EMPTY_FARM');
      const byEntity = entitiesIn(blocks);
      assert(byEntity.get('farm')[0]?.farmId === farmCId, 'BOOTSTRAP_EMPTY_FARM_ID');
    });

    await check('BOOTSTRAP_FOREIGN_ACTOR_DENIED', async () => {
      // Manager has a farm-A grant but did not create the snapshot — same 404
      // as an unknown id (no cross-actor enumeration, spec04 §204).
      const response = await bootstrapPage(manager.token, farmAId, snapshotA, '1');
      await expectDenied(response, 'BOOTSTRAP_FOREIGN_ACTOR');
    });

    await check('BOOTSTRAP_UNKNOWN_SNAPSHOT', async () => {
      const response = await bootstrapPage(owner.token, farmAId, randomUUID(), '1');
      await expectDenied(response, 'BOOTSTRAP_UNKNOWN_SNAPSHOT');
    });

    await check('BOOTSTRAP_CROSS_SCOPE_DENIED', async () => {
      // crossFarm holds only a farm-B grant: the farm-A scope itself is denied.
      const denied = await bootstrapPage(crossFarm.token, farmAId, snapshotA, '1');
      await expectDenied(denied, 'BOOTSTRAP_CROSS_SCOPE');
      // And the farm-A snapshot id is invisible under the farm-B path even
      // for an actor who can read both scopes.
      const wrongScope = await bootstrapPage(owner.token, farmBId, snapshotA, '1');
      await expectDenied(wrongScope, 'BOOTSTRAP_WRONG_SCOPE_PATH');
    });

    await check('BOOTSTRAP_PAGE_CURSOR_VALIDATION', async () => {
      // The exception filter sanitizes 400 payloads to VALIDATION_FAILED.
      const bad = await bootstrapPage(owner.token, farmAId, snapshotA, 'abc');
      const badBody = await readBody(bad);
      assert(bad.status === 400 && badBody?.error?.code === 'VALIDATION_FAILED', 'BOOTSTRAP_PAGE_ALPHA_INVALID');
      const far = await bootstrapPage(owner.token, farmAId, snapshotA, '999');
      const farBody = await readBody(far);
      assert(far.status === 400 && farBody?.error?.code === 'VALIDATION_FAILED', 'BOOTSTRAP_PAGE_RANGE_INVALID');
    });

    await check('BOOTSTRAP_UNAUTHENTICATED', async () => {
      const response = await fetch(`${origin}${farmScoped(farmAId, 'sync/bootstrap')}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ operationId: randomUUID(), payload: {} }),
      });
      assert(response.status === 401 || response.status === 403, 'BOOTSTRAP_UNAUTH_STATUS');
    });

    await check('BOOTSTRAP_EXPIRY_AND_EPOCH_INVALIDATION', async () => {
      // TTL expiry: rewind expires_at -> reads are 410 CURSOR_EXPIRED.
      const expiredOp = randomUUID();
      await bootstrapCreate(owner.token, farmAId, expiredOp);
      await migration.query(
        "UPDATE public.bootstrap_snapshots SET created_at = CURRENT_TIMESTAMP - INTERVAL '20 minutes', expires_at = CURRENT_TIMESTAMP - INTERVAL '1 second' WHERE id = $1::uuid",
        [expiredOp],
      );
      const expired = await bootstrapPage(owner.token, farmAId, expiredOp, '1');
      const expiredBody = await readBody(expired);
      assert(expired.status === 410 && expiredBody?.error?.code === 'CURSOR_EXPIRED', 'BOOTSTRAP_EXPIRED_STATUS');

      // Continuity-epoch bump invalidates both snapshot reads and change cursors.
      const epochOp = randomUUID();
      const epochSnap = await bootstrapCreate(owner.token, farmAId, epochOp);
      const epochBody = await expectJson(epochSnap, 200, 'BOOTSTRAP_EPOCH_SETUP');
      await migration.query(
        'UPDATE public.farm_clocks SET continuity_epoch = continuity_epoch + 1 WHERE farm_id = $1::uuid AND organization_id = $2::uuid',
        [farmAId, organizationId],
      );
      try {
        const stale = await bootstrapPage(owner.token, farmAId, epochOp, '1');
        const staleBody = await readBody(stale);
        assert(stale.status === 410 && staleBody?.error?.code === 'CURSOR_EXPIRED', 'BOOTSTRAP_EPOCH_STATUS');
        const staleChanges = await changesGet(owner.token, farmAId, epochBody.data.changesCursor);
        const staleChangesBody = await readBody(staleChanges);
        assert(staleChanges.status === 410 && staleChangesBody?.error?.code === 'CURSOR_EXPIRED', 'CHANGES_EPOCH_STATUS');
      } finally {
        await migration.query(
          'UPDATE public.farm_clocks SET continuity_epoch = continuity_epoch - 1 WHERE farm_id = $1::uuid AND organization_id = $2::uuid',
          [farmAId, organizationId],
        );
      }
    });

    await check('BOOTSTRAP_POLICY_VERSION_INVALIDATION', async () => {
      const op = randomUUID();
      const snapBody = await expectJson(await bootstrapCreate(owner.token, farmAId, op), 200, 'BOOTSTRAP_POLICY_SETUP');
      await migration.query('UPDATE public.organizations SET policy_version = policy_version + 1 WHERE id = $1::uuid', [organizationId]);
      try {
        const stale = await bootstrapPage(owner.token, farmAId, op, '1');
        const staleBody = await readBody(stale);
        assert(stale.status === 410 && staleBody?.error?.code === 'CURSOR_EXPIRED', 'BOOTSTRAP_POLICY_STATUS');
        const staleChanges = await changesGet(owner.token, farmAId, snapBody.data.changesCursor);
        const staleChangesBody = await readBody(staleChanges);
        assert(staleChanges.status === 410, 'CHANGES_POLICY_STATUS');
      } finally {
        await migration.query('UPDATE public.organizations SET policy_version = policy_version - 1 WHERE id = $1::uuid', [organizationId]);
      }
    });

    stage('p08-change-feed');
    let feedCursor;
    let changeZoneId;
    await check('CHANGES_CATCH_UP_AFTER_MUTATION', async () => {
      // Apply one real kernel op after the snapshot — the feed must surface it.
      changeZoneId = randomUUID();
      const op = intent('zone.create', changeZoneId, {
        name: `P08 feed zone ${s8()}`, type: 'crop_plot', geometry: { points: zonePoints() },
      }, epoch);
      const batch = await farmBatch(owner.token, organizationId, farmAId, [op], epoch);
      const batchBody = await expectJson(batch, 200, 'CHANGES_SETUP_BATCH');
      const outcome = batchBody?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(outcome?.outcome === 'applied', 'CHANGES_SETUP_OUTCOME');
      await trackRevisionFromClock(farmAId, 'CHANGES_SETUP');

      const feed = await changesGet(owner.token, farmAId, snapshotACursor);
      const body = await expectJson(feed, 200, 'CHANGES_CATCH_UP');
      const sets = body?.data?.changeSets;
      assert(Array.isArray(sets) && sets.length === 1, 'CHANGES_SETS_LENGTH');
      const [set] = sets;
      assert(set.revision === '2' && set.continuityEpoch === '1', 'CHANGES_REVISION_INVALID');
      assert(set.operationId === op.operationId, 'CHANGES_OPERATION_MISMATCH');
      assert(typeof set.schemaVersion === 'string' && ISO_INSTANT.test(set.createdAt), 'CHANGES_SET_META_INVALID');
      const entry = (set.changes ?? []).find((c) => c.entity === 'zone' && c.change === 'upsert');
      assert(entry?.record?.id === changeZoneId && 'areaM2' in entry.record, 'CHANGES_RECORD_SHAPE');
      assert(body?.data?.highWatermark === '2', 'CHANGES_WATERMARK_INVALID');
      assert(body?.page?.hasMore === false, 'CHANGES_HASMORE_INVALID');
      assert(typeof body?.page?.nextCursor === 'string', 'CHANGES_NEXT_CURSOR_MISSING');
      feedCursor = body.page.nextCursor;
    });

    await check('CHANGES_FOLLOW_TO_TAIL', async () => {
      const feed = await changesGet(owner.token, farmAId, feedCursor);
      const body = await expectJson(feed, 200, 'CHANGES_FOLLOW');
      assert(Array.isArray(body?.data?.changeSets) && body.data.changeSets.length === 0, 'CHANGES_TAIL_NOT_EMPTY');
      assert(body?.page?.hasMore === false, 'CHANGES_TAIL_HASMORE');
    });

    await check('CHANGES_CURSOR_TAMPERED', async () => {
      const tampered = `${snapshotACursor.slice(0, -2)}${snapshotACursor.endsWith('AA') ? 'BB' : 'AA'}`;
      const response = await changesGet(owner.token, farmAId, tampered);
      const body = await readBody(response);
      assert(response.status === 410 && body?.error?.code === 'CURSOR_EXPIRED', 'CHANGES_TAMPERED_STATUS');
    });

    await check('CHANGES_CURSOR_MALFORMED', async () => {
      for (const token of ['not-a-cursor', 'x'.repeat(5000), `${snapshotACursor}.extra`]) {
        const response = await changesGet(owner.token, farmAId, token);
        const body = await readBody(response);
        assert(response.status === 410 && body?.error?.code === 'CURSOR_EXPIRED', 'CHANGES_MALFORMED_STATUS');
      }
    });

    await check('CHANGES_CURSOR_ACTOR_BOUND', async () => {
      // Manager can read farm A but the cursor is bound to its creator.
      const response = await changesGet(manager.token, farmAId, snapshotACursor);
      const body = await readBody(response);
      assert(response.status === 410 && body?.error?.code === 'CURSOR_EXPIRED', 'CHANGES_ACTOR_BINDING_STATUS');
    });

    await check('CHANGES_CURSOR_SCOPE_BOUND', async () => {
      const wrongFarm = await changesGet(owner.token, farmBId, snapshotACursor);
      const wrongFarmBody = await readBody(wrongFarm);
      assert(wrongFarm.status === 410, 'CHANGES_FARM_BINDING_STATUS');
      const denied = await changesGet(crossFarm.token, farmAId, snapshotACursor);
      const deniedBody = await readBody(denied);
      assert(denied.status === 410, 'CHANGES_FOREIGN_ACTOR_STATUS');
    });

    await check('CHANGES_CURSOR_REQUIRED', async () => {
      const response = await changesGet(owner.token, farmAId);
      const body = await readBody(response);
      assert(response.status === 400 && body?.error?.code === 'VALIDATION_FAILED', 'CHANGES_CURSOR_REQUIRED_STATUS');
    });

    await check('CHANGES_UNAUTHENTICATED', async () => {
      const response = await fetch(`${origin}${farmScoped(farmAId, `sync/changes?cursor=${encodeURIComponent(snapshotACursor)}`)}`);
      assert(response.status === 401 || response.status === 403, 'CHANGES_UNAUTH_STATUS');
    });

    stage('p08-pruning-and-rls');
    await check('CHANGES_PRUNED_FLOOR', async () => {
      // Control-plane prune to the current watermark: cursors below the floor
      // must fail loudly with CURSOR_EXPIRED (spec04 §208 recovery path).
      const pruned = await migration.query(
        'SELECT public.farmly_prune_change_sets($1::uuid, $2::uuid, 2)::TEXT AS floor',
        [organizationId, farmAId],
      );
      assert(pruned.rows[0]?.floor === '2', 'PRUNE_FLOOR_NOT_ADVANCED');
      const remaining = await migration.query(
        'SELECT count(*)::INTEGER AS n FROM public.change_sets WHERE organization_id = $1::uuid AND farm_id = $2::uuid',
        [organizationId, farmAId],
      );
      assert(remaining.rows[0].n === 0, 'PRUNE_SETS_NOT_DELETED');
      const response = await changesGet(owner.token, farmAId, snapshotACursor);
      const body = await readBody(response);
      assert(response.status === 410 && body?.error?.code === 'CURSOR_EXPIRED', 'CHANGES_PRUNED_STATUS');

      // A fresh bootstrap lands at the new floor — the feed is a clean 200 tail.
      const newOp = randomUUID();
      const newSnap = await expectJson(await bootstrapCreate(owner.token, farmAId, newOp), 200, 'PRUNE_NEW_BOOTSTRAP');
      assert(newSnap.data.highWatermark === '2' && newSnap.data.prunedThroughRevision === '2', 'PRUNE_MANIFEST_FLOOR');
      const feed = await changesGet(owner.token, farmAId, newSnap.data.changesCursor);
      const feedBody = await expectJson(feed, 200, 'PRUNE_FEED');
      assert(feedBody.data.changeSets.length === 0 && feedBody.page.hasMore === false, 'PRUNE_FEED_NOT_EMPTY');
    });

    await check('BOOTSTRAP_TENANT_WRITE_DENIED', async () => {
      // The tenant role may not bypass the definer writer: a direct INSERT
      // must be refused by RLS even with a readable farm scope.
      const tenantClient = new Client({ connectionString: tenantConnectionString(`farmly-bootstrap-rls-${suffix}`) });
      await tenantClient.connect();
      try {
        await tenantClient.query(`SELECT set_config('app.actor_id', $1, TRUE)`, [owner.id]);
        let writeDenied = false;
        try {
          await tenantClient.query(
            `INSERT INTO public.bootstrap_snapshots
               (organization_id, farm_id, id, actor_pseudonym, scope_policy_version,
                continuity_epoch, high_watermark, row_count, byte_count, chunk_count, expires_at)
             VALUES ($1, $2, $3, repeat('0', 64), 1, 1, 1, 0, 0, 1, CURRENT_TIMESTAMP + INTERVAL '5 minutes')`,
            [organizationId, farmAId, randomUUID()],
          );
        } catch (error) {
          writeDenied = /row-level security|permission denied|new row violates/i.test(String(error?.message ?? error));
        }
        assert(writeDenied, 'BOOTSTRAP_TENANT_WRITE_NOT_DENIED');
        // And tenant reads through RLS see only their own granted scope.
        const foreign = await tenantClient.query(
          `SELECT count(*)::INTEGER AS n FROM public.bootstrap_snapshots WHERE organization_id = $1::uuid AND farm_id = $2::uuid`,
          [organizationId, farmBId],
        );
        assert(foreign.rows[0].n === 0, 'BOOTSTRAP_RLS_FOREIGN_VISIBLE');
      } finally {
        await tenantClient.end().catch(() => {});
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
      for (const table of ['bootstrap_snapshot_chunks', 'bootstrap_snapshots', 'task_transitions', 'task_occurrences', 'correction_proposals', 'weather_snapshots']) {
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
    scope: 'P08 sync bootstrap + change feed (spec04 §7, §200-208)',
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
