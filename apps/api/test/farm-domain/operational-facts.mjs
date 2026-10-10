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

// P05 step 1 — farm-domain regression suite for the product-owner-approved wire
// contract (decision record 2026-10-08, spec04 §5.1, contracts/openapi/farmly-v1.yaml).
// Every assertion names DESIRED behavior; the suite is expected to fail while the
// farm-scoped domain routes/kernel registry are missing. Setup stages stay fail-fast
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

    // ---- P06 fixtures: master parents on farm A (owner) --------------------
    stage('p06-fixture-parents-farm-a');
    const md5Id = (seed) => {
      const h = createHash('md5').update(seed).digest('hex');
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-5${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
    };
    const occurrenceIdFor = (farmId, templateId, date, slot) =>
      md5Id(`taskocc:${farmId}:${templateId}:${date}:${slot}`);

    // farm-B parents for cross-farm rejection coverage.
    for (const [label, type, slug, payload] of [
      ['zoneB', 'zone.create', 'zones',
        { name: `Farm B ops plot ${s8()}`, type: 'crop_plot', geometry: { points: zonePoints() } }],
      ['speciesB', 'cropSpecies.create', 'crop-species',
        { name: `Farm B ops species ${s8()}`, harvestUnit: 'kg' }],
    ]) {
      ids[`${label}Id`] = randomUUID();
      const op = intent(type, ids[`${label}Id`], payload, farmEpochs.get(farmBId));
      const response = await domainCreate(owner.token, organizationId, farmBId, slug, op);
      await applyDomainIntent(response, op.operationId, type.split('.')[0] === 'zone' ? 'zone' : 'cropSpecies', farmBId, 'P06_FARMB_PARENT');
    }

    const parentSpecs = [
      ['zonePlotA', 'ZONE_PARENT_PLOT', 'zone.create', 'zones', 'zone',
        () => ({ name: `Ops plot ${s8()}`, type: 'crop_plot', geometry: { points: zonePoints() } })],
      ['zoneWaterA', 'ZONE_PARENT_WATER', 'zone.create', 'zones', 'zone',
        () => ({ name: `Ops water zone ${s8()}`, type: 'water', geometry: { points: zonePoints() } })],
      ['speciesA', 'SPECIES_PARENT', 'cropSpecies.create', 'crop-species', 'cropSpecies',
        () => ({ name: `Ops species ${s8()}`, harvestUnit: 'kg' })],
      ['herdBatchA', 'HERD_PARENT_BATCH', 'herd.create', 'herds', 'herd',
        () => ({ mode: 'batch', species: 'chicken' })],
      ['herdTrackedA', 'HERD_PARENT_TRACKED', 'herd.create', 'herds', 'herd',
        () => ({ mode: 'tracked', species: 'cattle' })],
    ];
    for (const [label, tag, type, slug, view, payload] of parentSpecs) {
      ids[`${label}Id`] = randomUUID();
      await check(`${tag}_CREATE`, async () => {
        const op = intent(type, ids[`${label}Id`], payload(), epoch);
        const policyBefore = await policyVersion();
        const response = await domainCreate(owner.token, organizationId, farmAId, slug, op);
        await applyDomainIntent(response, op.operationId, view, farmAId, tag);
        await expectDomainApplied(farmAId, op.operationId, policyBefore, tag);
        versions.set(ids[`${label}Id`], 1);
      });
    }

    // Planting + tank parents (owner-managed master data).
    ids.plantingAId = randomUUID();
    await check('PLANTING_PARENT_CREATE', async () => {
      const op = intent('planting.create', ids.plantingAId, {
        cropSpeciesId: ids.speciesAId, plotId: ids.zonePlotAId, sowingDate: '2026-09-01',
      }, epoch);
      const response = await domainCreate(owner.token, organizationId, farmAId, 'plantings', op);
      await applyDomainIntent(response, op.operationId, 'planting', farmAId, 'PLANTING_PARENT_CREATE');
    });
    ids.tankAId = randomUUID();
    await check('TANK_PARENT_CREATE', async () => {
      const op = intent('waterTank.create', ids.tankAId, {
        name: `Ops tank ${s8()}`, zoneId: ids.zoneWaterAId, capacityLitres: '5000',
      }, epoch);
      const response = await domainCreate(owner.token, organizationId, farmAId, 'water-tanks', op);
      await applyDomainIntent(response, op.operationId, 'waterTank', farmAId, 'TANK_PARENT_CREATE');
    });
    // Batch herd starts at 20 head (movement write is manager+).
    ids.movementSeedId = randomUUID();
    await check('MOVEMENT_SEED_STOCK_IN', async () => {
      const op = intent('livestockMovement.create', ids.movementSeedId, {
        herdId: ids.herdBatchAId, movementType: 'stock_in', delta: 20,
      }, epoch);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'livestock-movements', op);
      await applyDomainIntent(response, op.operationId, 'livestockMovement', farmAId, 'MOVEMENT_SEED_STOCK_IN');
      const listed = await listEntry(manager.token, organizationId, farmAId, 'herds', 'herds', ids.herdBatchAId, 'MOVEMENT_SEED_STOCK_IN');
      assert(listed?.headcount === 20, 'MOVEMENT_SEED_STOCK_IN_HEADCOUNT');
    });

    // Task templates: assigned feeding template + unassigned irrigation template.
    ids.templateFeedId = randomUUID();
    await check('TEMPLATE_FEED_CREATE', async () => {
      const op = intent('taskTemplate.create', ids.templateFeedId, {
        title: `Feed chickens ${s8()}`, kind: 'feeding',
        recurrence: { freq: 'daily', timeOfDay: '06:00' },
        startsOn: '2026-01-01', assigneeMembershipId: memberships.worker,
      }, epoch);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'task-templates', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'taskTemplate', farmAId, 'TEMPLATE_FEED_CREATE');
      assert(view.kind === 'feeding' && view.assigneeMembershipId === memberships.worker, 'TEMPLATE_FEED_VIEW_INVALID');
    });
    ids.templateIrrigationId = randomUUID();
    await check('TEMPLATE_IRRIGATION_CREATE', async () => {
      const op = intent('taskTemplate.create', ids.templateIrrigationId, {
        title: `Water zone ${s8()}`, kind: 'irrigation', zoneId: ids.zoneWaterAId,
        recurrence: { freq: 'weekly', timeOfDay: '17:30', daysOfWeek: [1, 4] },
        startsOn: '2026-01-01',
      }, epoch);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'task-templates', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'taskTemplate', farmAId, 'TEMPLATE_IRRIGATION_CREATE');
      assert(view.kind === 'irrigation' && view.recurrence?.freq === 'weekly', 'TEMPLATE_IRRIGATION_VIEW_INVALID');
    });

    // ---- P06 cases -----------------------------------------------------------

    stage('p06-worker-operational-writes');
    ids.observationId = randomUUID();
    await check('OBSERVATION_WORKER_CREATE', async () => {
      const op = intent('animalObservation.create', ids.observationId, {
        herdId: ids.herdTrackedAId, note: 'Herd looks calm', kind: 'note', observedOn: '2026-10-08',
      }, epoch);
      const policyBefore = await policyVersion();
      const response = await domainCreate(worker.token, organizationId, farmAId, 'observations', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'animalObservation', farmAId, 'OBSERVATION_WORKER_CREATE');
      assert(view.herdId === ids.herdTrackedAId && view.kind === 'note', 'OBSERVATION_VIEW_INVALID');
      await expectDomainApplied(farmAId, op.operationId, policyBefore, 'OBSERVATION_WORKER_CREATE');
    });
    await check('OBSERVATION_BOTH_SUBJECTS_REJECTED', async () => {
      const op = intent('animalObservation.create', randomUUID(), {
        herdId: ids.herdTrackedAId, animalId: randomUUID(), note: 'ambiguous',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'observations', op);
      await expectDomainRejected(response, 'OBSERVATION_BOTH_SUBJECTS_REJECTED');
    });
    ids.productionId = randomUUID();
    await check('PRODUCTION_WORKER_CREATE', async () => {
      const op = intent('productionRecord.create', ids.productionId, {
        herdId: ids.herdBatchAId, product: 'eggs', quantity: '42', recordedOn: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'production-records', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'productionRecord', farmAId, 'PRODUCTION_WORKER_CREATE');
      assert(view.unit === 'pieces' && view.quantity === '42.0000', 'PRODUCTION_UNIT_INVALID');
    });
    await check('PRODUCTION_EGGS_FRACTIONAL_REJECTED', async () => {
      const op = intent('productionRecord.create', randomUUID(), {
        herdId: ids.herdBatchAId, product: 'eggs', quantity: '12.5', recordedOn: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'production-records', op);
      await expectDomainRejected(response, 'PRODUCTION_EGGS_FRACTIONAL_REJECTED');
    });
    ids.plantingEventId = randomUUID();
    await check('PLANTING_EVENT_WORKER_CREATE', async () => {
      const op = intent('plantingEvent.create', ids.plantingEventId, {
        plantingId: ids.plantingAId, eventType: 'scouting', note: 'No pests', occurredOn: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'planting-events', op);
      await applyDomainIntent(response, op.operationId, 'plantingEvent', farmAId, 'PLANTING_EVENT_WORKER_CREATE');
    });

    stage('p06-authorization-matrix');
    await check('WORKER_TASK_TEMPLATE_DENIED', async () => {
      const op = intent('taskTemplate.create', randomUUID(), {
        title: 'Worker attempt', recurrence: { freq: 'daily', timeOfDay: '07:00' },
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'task-templates', op);
      await expectDenied(response, 'WORKER_TASK_TEMPLATE_DENIED');
    });
    await check('WORKER_MOVEMENT_DENIED', async () => {
      const op = intent('livestockMovement.create', randomUUID(), {
        herdId: ids.herdBatchAId, movementType: 'sold', delta: -1,
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'livestock-movements', op);
      await expectDenied(response, 'WORKER_MOVEMENT_DENIED');
    });
    await check('VIEWER_FACT_DENIED', async () => {
      const op = intent('animalObservation.create', randomUUID(), {
        herdId: ids.herdTrackedAId, note: 'viewer write',
      }, epoch);
      const response = await domainCreate(viewer.token, organizationId, farmAId, 'observations', op);
      await expectDenied(response, 'VIEWER_FACT_DENIED');
    });
    await check('ORG_VIEWER_STALE_GRANT_DENIED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '40', method: 'vwc_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const response = await domainCreate(orgViewer.token, organizationId, farmAId, 'moisture-readings', op);
      await expectDenied(response, 'ORG_VIEWER_STALE_GRANT_DENIED');
    });
    await check('NO_GRANT_MEMBER_DENIED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '40', method: 'vwc_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const response = await domainCreate(member.token, organizationId, farmAId, 'moisture-readings', op);
      await expectDenied(response, 'NO_GRANT_MEMBER_DENIED');
    });
    await check('WORKER_MASTER_DATA_DENIED', async () => {
      const op = intent('zone.create', randomUUID(), {
        name: 'Worker zone', type: 'other', geometry: { points: zonePoints() },
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'zones', op);
      await expectDenied(response, 'WORKER_MASTER_DATA_DENIED');
    });
    await check('UNKNOWN_TYPE_REJECTED', async () => {
      const op = intent('telemetry.create', randomUUID(), { herdId: ids.herdBatchAId }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'production-records', op);
      // Type/route mismatch is a safe 4xx; if the route tolerated it the kernel
      // would reject MUTATION_NOT_SUPPORTED.
      await expectDomainRejected(response, 'UNKNOWN_TYPE_REJECTED');
    });

    stage('p06-movement-guard');
    await check('MOVEMENT_TRACKED_HERD_REJECTED', async () => {
      const op = intent('livestockMovement.create', randomUUID(), {
        herdId: ids.herdTrackedAId, movementType: 'adjustment', delta: 3,
      }, epoch);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'livestock-movements', op);
      await expectDomainRejected(response, 'MOVEMENT_TRACKED_HERD_REJECTED');
    });
    await check('MOVEMENT_NEGATIVE_BALANCE_REJECTED', async () => {
      const op = intent('livestockMovement.create', randomUUID(), {
        herdId: ids.herdBatchAId, movementType: 'sold', delta: -25,
      }, epoch);
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmAId);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'livestock-movements', op);
      await expectDomainRejected(response, 'MOVEMENT_NEGATIVE_BALANCE_REJECTED');
      await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, 'MOVEMENT_NEGATIVE_BALANCE_REJECTED');
    });
    ids.movementSellId = randomUUID();
    await check('MOVEMENT_SELL_APPLIES', async () => {
      const op = intent('livestockMovement.create', ids.movementSellId, {
        herdId: ids.herdBatchAId, movementType: 'sold', delta: -4, occurredOn: '2026-10-08',
      }, epoch);
      const response = await domainCreate(manager.token, organizationId, farmAId, 'livestock-movements', op);
      await applyDomainIntent(response, op.operationId, 'livestockMovement', farmAId, 'MOVEMENT_SELL_APPLIES');
      const listed = await listEntry(manager.token, organizationId, farmAId, 'herds', 'herds', ids.herdBatchAId, 'MOVEMENT_SELL_APPLIES');
      assert(listed?.headcount === 16, 'MOVEMENT_SELL_APPLIES_HEADCOUNT');
    });

    stage('p06-task-occurrence-transitions');
    const feedDate = '2026-10-09';
    const feedSlot = 'morning';
    const feedOccurrenceId = occurrenceIdFor(farmAId, ids.templateFeedId, feedDate, feedSlot);
    ids.feedTransitionOp = randomUUID();
    await check('OCCURRENCE_DETERMINISTIC_ID_ENFORCED', async () => {
      const badId = randomUUID();
      const op = intent('taskOccurrence.transition', badId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'complete',
      }, epoch);
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_DETERMINISTIC_ID_ENFORCED');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'rejected', 'OCCURRENCE_DETERMINISTIC_ID_ENFORCED_APPLIED');
    });
    await check('OCCURRENCE_MATERIALIZE_AND_COMPLETE_WORKER', async () => {
      const op = intent('taskOccurrence.transition', feedOccurrenceId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'complete',
      }, epoch);
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_MATERIALIZE_AND_COMPLETE_WORKER');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'applied', 'OCCURRENCE_MATERIALIZE_OUTCOME');
      const listed = await listEntry(worker.token, organizationId, farmAId, 'task-occurrences', 'taskOccurrences', feedOccurrenceId, 'OCCURRENCE_MATERIALIZE_AND_COMPLETE_WORKER');
      assert(listed?.status === 'done' && listed?.version === 2, 'OCCURRENCE_STATE_INVALID');
    });
    await check('OCCURRENCE_DOUBLE_MATERIALIZE_CONFLICT', async () => {
      // A second op on the now-existing row without a baseVersion is a CAS lie.
      const dup = intent('taskOccurrence.transition', feedOccurrenceId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'complete',
      }, epoch);
      const response = await farmBatch(manager.token, organizationId, farmAId, [dup], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_DOUBLE_MATERIALIZE_CONFLICT');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === dup.operationId);
      assert(entry?.outcome === 'conflict' && entry?.code === 'VERSION_CONFLICT', 'OCCURRENCE_DOUBLE_MATERIALIZE_OUTCOME');
    });
    await check('OCCURRENCE_DONE_ALREADY_REJECTED', async () => {
      // done -> complete is not a legal transition.
      const op = intent('taskOccurrence.transition', feedOccurrenceId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'complete',
      }, epoch, { baseVersion: 2 });
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_DONE_ALREADY_REJECTED');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'rejected', 'OCCURRENCE_DONE_ALREADY_OUTCOME');
    });
    await check('OCCURRENCE_WORKER_REOPEN_DENIED', async () => {
      const op = intent('taskOccurrence.transition', feedOccurrenceId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'reopen',
      }, epoch, { baseVersion: 2 });
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      // reopen is manager-only: the kernel raises permission denied for the
      // batch item -> HTTP-level denial for the whole request.
      await expectDenied(response, 'OCCURRENCE_WORKER_REOPEN_DENIED');
    });
    await check('OCCURRENCE_MANAGER_REOPEN', async () => {
      const op = intent('taskOccurrence.transition', feedOccurrenceId, {
        templateId: ids.templateFeedId, occurrenceDate: feedDate, slot: feedSlot, transition: 'reopen', reason: 'counted wrong',
      }, epoch, { baseVersion: 2 });
      const response = await farmBatch(manager.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_MANAGER_REOPEN');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'applied', 'OCCURRENCE_MANAGER_REOPEN_OUTCOME');
      const listed = await listEntry(manager.token, organizationId, farmAId, 'task-occurrences', 'taskOccurrences', feedOccurrenceId, 'OCCURRENCE_MANAGER_REOPEN');
      assert(listed?.status === 'open' && listed?.version === 3, 'OCCURRENCE_REOPEN_STATE');
    });
    await check('OCCURRENCE_NON_ASSIGNEE_WORKER_DENIED', async () => {
      // workerB holds a farm-A worker grant but is not the template assignee —
      // the assignee check denies the write (not the generic grant gate).
      const occId = occurrenceIdFor(farmAId, ids.templateFeedId, '2026-10-10', 'morning');
      const op = intent('taskOccurrence.transition', occId, {
        templateId: ids.templateFeedId, occurrenceDate: '2026-10-10', slot: 'morning', transition: 'complete',
      }, epoch);
      const response = await farmBatch(workerB.token, organizationId, farmAId, [op], epoch);
      await expectDenied(response, 'OCCURRENCE_NON_ASSIGNEE_WORKER_DENIED');
    });
    await check('OCCURRENCE_UNASSIGNED_WORKER_DENIED', async () => {
      // irrigation template has no assignee; a worker grant holder completes it.
      const occId = occurrenceIdFor(farmAId, ids.templateIrrigationId, '2026-10-12', 'evening');
      const op = intent('irrigationTask.transition', occId, {
        templateId: ids.templateIrrigationId, occurrenceDate: '2026-10-12', slot: 'evening', transition: 'complete',
      }, epoch);
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_UNASSIGNED_WORKER_DENIED');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'applied', 'IRRIGATION_TRANSITION_OUTCOME');
    });
    await check('IRRIGATION_ROUTE_KIND_GUARD', async () => {
      // irrigationTask.transition on a non-irrigation template is a field error.
      const occId = occurrenceIdFor(farmAId, ids.templateFeedId, '2026-10-11', 'morning');
      const op = intent('irrigationTask.transition', occId, {
        templateId: ids.templateFeedId, occurrenceDate: '2026-10-11', slot: 'morning', transition: 'complete',
      }, epoch);
      const response = await farmBatch(manager.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'IRRIGATION_ROUTE_KIND_GUARD');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'rejected', 'IRRIGATION_KIND_OUTCOME');
    });
    await check('OCCURRENCE_WINDOW_REJECTED', async () => {
      // occurrenceDate before template startsOn.
      const occId = occurrenceIdFor(farmAId, ids.templateFeedId, '2025-12-31', 'morning');
      const op = intent('taskOccurrence.transition', occId, {
        templateId: ids.templateFeedId, occurrenceDate: '2025-12-31', slot: 'morning', transition: 'complete',
      }, epoch);
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'OCCURRENCE_WINDOW_REJECTED');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome !== 'applied', 'OCCURRENCE_WINDOW_OUTCOME');
    });
    await check('TRANSITION_ROUTE_CAS', async () => {
      // The dedicated route composes the envelope server-side.
      const occId = occurrenceIdFor(farmAId, ids.templateIrrigationId, '2026-10-13', 'evening');
      const seed = intent('irrigationTask.transition', occId, {
        templateId: ids.templateIrrigationId, occurrenceDate: '2026-10-13', slot: 'evening', transition: 'skip', reason: 'rain',
      }, epoch);
      const seedResponse = await farmBatch(manager.token, organizationId, farmAId, [seed], epoch);
      await expectJson(seedResponse, 200, 'TRANSITION_ROUTE_CAS');
      // Reopen via the dedicated route with correct CAS (row is skipped v2).
      const reopen = await fetch(`${farmBase(organizationId, farmAId)}/irrigation-tasks/${occId}/transitions`, {
        method: 'POST',
        headers: httpHeaders(manager.token, { 'content-type': 'application/json', 'idempotency-key': randomUUID() }),
        body: JSON.stringify({ operationId: randomUUID(), expectedVersion: 2, transition: 'reopen' }),
      });
      // operationId must equal Idempotency-Key — resend correctly.
      const opId = randomUUID();
      const proper = await fetch(`${farmBase(organizationId, farmAId)}/irrigation-tasks/${occId}/transitions`, {
        method: 'POST',
        headers: httpHeaders(manager.token, { 'content-type': 'application/json', 'idempotency-key': opId }),
        body: JSON.stringify({ operationId: opId, expectedVersion: 2, transition: 'reopen' }),
      });
      await readBody(reopen); // mismatched key -> 400
      const properBody = await expectJson(proper, 200, 'TRANSITION_ROUTE_CAS');
      assert(properBody?.data?.outcome === 'applied', 'TRANSITION_ROUTE_OUTCOME');
      // Stale expectedVersion now conflicts.
      const staleId = randomUUID();
      const stale = await fetch(`${farmBase(organizationId, farmAId)}/irrigation-tasks/${occId}/transitions`, {
        method: 'POST',
        headers: httpHeaders(manager.token, { 'content-type': 'application/json', 'idempotency-key': staleId }),
        body: JSON.stringify({ operationId: staleId, expectedVersion: 2, transition: 'cancel' }),
      });
      const staleBody = await readBody(stale);
      assert(stale.status === 409
        || (stale.status === 200 && staleBody?.data?.outcome === 'conflict'),
        'TRANSITION_ROUTE_STALE_CAS');
    });

    stage('p06-harvest-lifecycle');
    // Batch/route ops above apply revisions without the tracked single-op
    // response path; resync the local map before the next tracked assertion.
    farmRevisions.set(farmAId, await clockRevision(farmAId));
    ids.harvestId = randomUUID();
    await check('HARVEST_CREATE', async () => {
      const op = intent('harvest.create', ids.harvestId, {
        plantingId: ids.plantingAId, quantityKg: '120.5', harvestDate: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'harvest', farmAId, 'HARVEST_CREATE');
      assert(view.quantityKg === '120.5000' && view.status === 'active' && view.version === 1, 'HARVEST_VIEW_INVALID');
      const listed = await listEntry(owner.token, organizationId, farmAId, 'harvests', 'harvests', ids.harvestId, 'HARVEST_CREATE');
      assert(listed?.quantityKg === '120.5000' && listed?.pendingProposals === 0, 'HARVEST_LIST_INVALID');
    });
    await check('HARVEST_REPLAY_NO_DOUBLE_COUNT', async () => {
      // Lost-ACK replay: same operationId + identical body returns the cached
      // outcome; no second record is created.
      const op = intent('harvest.create', randomUUID(), {
        plantingId: ids.plantingAId, quantityKg: '30', harvestDate: '2026-10-08',
      }, epoch);
      const first = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      await applyDomainIntent(first, op.operationId, 'harvest', farmAId, 'HARVEST_REPLAY_NO_DOUBLE_COUNT');
      const replay = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      const replayBody = await expectJson(replay, 200, 'HARVEST_REPLAY_NO_DOUBLE_COUNT');
      assert(replayBody?.data?.outcome === 'applied', 'HARVEST_REPLAY_OUTCOME');
      const count = await migration.query(
        'SELECT count(*)::INTEGER AS n FROM public.harvest_records WHERE organization_id=$1::uuid AND farm_id=$2::uuid AND harvest_id=$3::uuid',
        [organizationId, farmAId, op.resourceId],
      );
      assert(count.rows[0].n === 1, 'HARVEST_REPLAY_DUPLICATED');
    });
    await check('HARVEST_PROPOSE_WORKER', async () => {
      const op = intent('harvest.correction.propose', ids.harvestId, {
        proposedQuantityKg: '98', reason: 'wet weight loss after drying',
      }, epoch);
      const response = await mutationPost(worker.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/correction-proposals`, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'correctionProposal', farmAId, 'HARVEST_PROPOSE_WORKER');
      assert(view.status === 'pending' && view.harvestId === ids.harvestId, 'PROPOSAL_VIEW_INVALID');
      ids.proposalId = view.id;
      // Proposal alone must not change the confirmed head.
      const listed = await listEntry(owner.token, organizationId, farmAId, 'harvests', 'harvests', ids.harvestId, 'HARVEST_PROPOSE_WORKER');
      assert(listed?.quantityKg === '120.5000' && listed?.pendingProposals === 1, 'PROPOSAL_CHANGED_HEAD');
    });
    await check('HARVEST_CORRECTION_WORKER_DENIED', async () => {
      const op = intent('harvest.correction.apply', ids.harvestId, {
        proposedQuantityKg: '98',
      }, epoch, { baseVersion: 1 });
      const response = await mutationPost(worker.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/corrections`, op);
      await expectDenied(response, 'HARVEST_CORRECTION_WORKER_DENIED');
    });
    await check('HARVEST_CORRECTION_CAS', async () => {
      const op = intent('harvest.correction.apply', ids.harvestId, {
        proposedQuantityKg: '98', proposalId: ids.proposalId,
      }, epoch, { baseVersion: 99 });
      const response = await mutationPost(manager.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/corrections`, op);
      await expectVersionConflict(response, 'HARVEST_CORRECTION_CAS');
    });
    await check('HARVEST_CORRECTION_APPLY', async () => {
      const op = intent('harvest.correction.apply', ids.harvestId, {
        proposedQuantityKg: '98', reason: 'drying loss', proposalId: ids.proposalId,
      }, epoch, { baseVersion: 1 });
      const response = await mutationPost(manager.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/corrections`, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'harvest', farmAId, 'HARVEST_CORRECTION_APPLY');
      assert(view.quantityKg === '98.0000' && view.version === 2, 'CORRECTION_VIEW_INVALID');
      const listed = await listEntry(owner.token, organizationId, farmAId, 'harvests', 'harvests', ids.harvestId, 'HARVEST_CORRECTION_APPLY');
      assert(listed?.quantityKg === '98.0000' && listed?.pendingProposals === 0, 'CORRECTION_HEAD_INVALID');
      // Original record preserved as superseded audit fact.
      const rows = await migration.query(
        `SELECT count(*)::INTEGER AS n, count(*) FILTER (WHERE supersedes_record_id IS NOT NULL)::INTEGER AS superseded
           FROM public.harvest_records WHERE organization_id=$1::uuid AND farm_id=$2::uuid AND harvest_id=$3::uuid`,
        [organizationId, farmAId, ids.harvestId],
      );
      assert(rows.rows[0].n === 2 && rows.rows[0].superseded === 1, 'CORRECTION_APPEND_INVALID');
    });
    await check('HARVEST_VOID_WORKER_DENIED', async () => {
      const op = intent('harvest.void', ids.harvestId, { reason: 'mistake' }, epoch, { baseVersion: 2 });
      const response = await mutationPost(worker.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/void`, op);
      await expectDenied(response, 'HARVEST_VOID_WORKER_DENIED');
    });
    await check('HARVEST_VOID', async () => {
      const op = intent('harvest.void', ids.harvestId, { reason: 'entered twice' }, epoch, { baseVersion: 2 });
      const response = await mutationPost(manager.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/void`, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'harvest', farmAId, 'HARVEST_VOID');
      assert(view.status === 'voided' && view.version === 3, 'VOID_VIEW_INVALID');
    });
    await check('HARVEST_PROPOSE_ON_VOIDED_REJECTED', async () => {
      const op = intent('harvest.correction.propose', ids.harvestId, {
        proposedQuantityKg: '50', reason: 'late proposal',
      }, epoch);
      const response = await mutationPost(worker.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/correction-proposals`, op);
      await expectDomainRejected(response, 'HARVEST_PROPOSE_ON_VOIDED_REJECTED');
    });
    await check('HARVEST_BAD_PLANTING_REJECTED', async () => {
      const op = intent('harvest.create', randomUUID(), {
        plantingId: randomUUID(), quantityKg: '10', harvestDate: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      await expectDomainRejected(response, 'HARVEST_BAD_PLANTING_REJECTED');
    });
    await check('HARVEST_ZERO_QUANTITY_REJECTED', async () => {
      const op = intent('harvest.create', randomUUID(), {
        plantingId: ids.plantingAId, quantityKg: '0', harvestDate: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      await expectDomainRejected(response, 'HARVEST_ZERO_QUANTITY_REJECTED');
    });
    await check('HARVEST_CROSS_FARM_PLANTING_REJECTED', async () => {
      // Seed a planting on farm B, then attempt a harvest on farm A referencing it.
      const plantingBId = randomUUID();
      const seed = intent('planting.create', plantingBId, {
        cropSpeciesId: ids.speciesBId, plotId: ids.zoneBId, sowingDate: '2026-09-01',
      }, farmEpochs.get(farmBId));
      const seeded = await domainCreate(owner.token, organizationId, farmBId, 'plantings', seed);
      await applyDomainIntent(seeded, seed.operationId, 'planting', farmBId, 'HARVEST_CROSS_FARM_SEED');
      const op = intent('harvest.create', randomUUID(), {
        plantingId: plantingBId, quantityKg: '10', harvestDate: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'harvests', op);
      await expectDomainRejected(response, 'HARVEST_CROSS_FARM_PLANTING_REJECTED');
    });

    stage('p06-readings');
    ids.moistureId = randomUUID();
    await check('MOISTURE_CREATE', async () => {
      const op = intent('moistureReading.create', ids.moistureId, {
        zoneId: ids.zonePlotAId, value: '37.25', method: 'vwc_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'moistureReading', farmAId, 'MOISTURE_CREATE');
      assert(view.method === 'vwc_percent' && view.value === '37.25', 'MOISTURE_VIEW_INVALID');
      const listed = await listEntry(viewer.token, organizationId, farmAId, 'moisture-readings', 'moistureReadings', ids.moistureId, 'MOISTURE_CREATE');
      assert(listed?.method === 'vwc_percent', 'MOISTURE_LIST_INVALID');
    });
    await check('MOISTURE_OVER_100_REJECTED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '150', method: 'relative_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', op);
      await expectDomainRejected(response, 'MOISTURE_OVER_100_REJECTED');
    });
    await check('MOISTURE_BAD_METHOD_REJECTED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '40', method: 'sensor_probe', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', op);
      await expectDomainRejected(response, 'MOISTURE_BAD_METHOD_REJECTED');
    });
    await check('MOISTURE_FUTURE_REJECTED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '40', method: 'vwc_percent', measuredAt: '2999-01-01T00:00:00Z',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', op);
      await expectDomainRejected(response, 'MOISTURE_FUTURE_REJECTED');
    });
    ids.waterReadingId = randomUUID();
    await check('WATER_READING_CREATE', async () => {
      const op = intent('waterReading.create', ids.waterReadingId, {
        tankId: ids.tankAId, storedLitres: '4300', source: 'staff_gauge',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'water-readings', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'waterReading', farmAId, 'WATER_READING_CREATE');
      assert(view.capacityLitres === '5000.0000' && view.storedLitres === '4300.0000', 'WATER_READING_SNAPSHOT_INVALID');
      const tank = await listEntry(owner.token, organizationId, farmAId, 'water-tanks', 'waterTanks', ids.tankAId, 'WATER_READING_CREATE');
      assert(tank?.storedLitres === '4300.0000', 'WATER_READING_TANK_NOT_UPDATED');
    });
    await check('WATER_USAGE_CREATE', async () => {
      const op = intent('waterUsage.create', randomUUID(), {
        tankId: ids.tankAId, usageLitres: '250', usageDate: '2026-10-08', note: 'drip line A',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'water-usages', op);
      await applyDomainIntent(response, op.operationId, 'waterUsage', farmAId, 'WATER_USAGE_CREATE');
    });
    await check('WATER_USAGE_NEGATIVE_REJECTED', async () => {
      const op = intent('waterUsage.create', randomUUID(), {
        tankId: ids.tankAId, usageLitres: '-5', usageDate: '2026-10-08',
      }, epoch);
      const response = await domainCreate(worker.token, organizationId, farmAId, 'water-usages', op);
      await expectDomainRejected(response, 'WATER_USAGE_NEGATIVE_REJECTED');
    });

    stage('p06-envelope-discipline');
    await check('APPLY_WITHOUT_BASEVERSION_REJECTED', async () => {
      const op = intent('harvest.correction.apply', ids.harvestId, { proposedQuantityKg: '90' }, epoch);
      const response = await mutationPost(manager.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/corrections`, op);
      await expectDomainRejected(response, 'APPLY_WITHOUT_BASEVERSION_REJECTED');
    });
    await check('PROPOSE_WITH_BASEVERSION_REJECTED', async () => {
      const op = intent('harvest.correction.propose', ids.harvestId, {
        proposedQuantityKg: '90', reason: 'x',
      }, epoch, { baseVersion: 1 });
      const response = await mutationPost(worker.token, `${farmBase(organizationId, farmAId)}/harvests/${ids.harvestId}/correction-proposals`, op);
      await expectDomainRejected(response, 'PROPOSE_WITH_BASEVERSION_REJECTED');
    });
    await check('DEPENDENCY_MISSING_REJECTED', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '10', method: 'vwc_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch, { dependsOn: [randomUUID()] });
      const response = await farmBatch(worker.token, organizationId, farmAId, [op], epoch);
      const body = await expectJson(response, 200, 'DEPENDENCY_MISSING_REJECTED');
      const entry = body?.data?.outcomes?.find((item) => item.operationId === op.operationId);
      assert(entry?.outcome === 'rejected' && entry?.code === 'DEPENDENCY_NOT_APPLIED', 'DEPENDENCY_MISSING_OUTCOME');
    });
    await check('OPERATION_ID_REUSED_CONFLICT', async () => {
      const op = intent('moistureReading.create', randomUUID(), {
        zoneId: ids.zonePlotAId, value: '11', method: 'vwc_percent', measuredAt: '2026-10-08T06:00:00Z',
      }, epoch);
      const first = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', op);
      await applyDomainIntent(first, op.operationId, 'moistureReading', farmAId, 'OPERATION_ID_REUSED_CONFLICT');
      const tampered = { ...op, resourceId: randomUUID() };
      const replay = await domainCreate(worker.token, organizationId, farmAId, 'moisture-readings', tampered);
      const replayBody = await readBody(replay);
      assert(replay.status === 409
        || (replay.status === 200 && replayBody?.data?.outcome === 'conflict'),
        'OPERATION_ID_REUSED_OUTCOME');
    });
    await check('LIST_READS_VIEWER_OK', async () => {
      const response = await domainList(viewer.token, organizationId, farmAId, 'harvests');
      const body = await expectJson(response, 200, 'LIST_READS_VIEWER_OK');
      assert(Array.isArray(body?.data?.harvests), 'LIST_READS_VIEWER_OK_SHAPE');
    });
    await check('LIST_READS_NO_GRANT_DENIED', async () => {
      const response = await domainList(member.token, organizationId, farmAId, 'harvests');
      await expectDenied(response, 'LIST_READS_NO_GRANT_DENIED');
    });
    await check('UNKNOWN_COLLECTION_404', async () => {
      const response = await domainList(owner.token, organizationId, farmAId, 'telemetry-streams');
      const body = await readBody(response);
      assert(response.status === 404, 'UNKNOWN_COLLECTION_404_STATUS');
      void body;
    });
    stage('complete');
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
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
      for (const table of ['task_transitions', 'task_occurrences', 'correction_proposals']) {
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
    scope: 'P06 operational facts wire contract (spec04 §5.2)',
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
