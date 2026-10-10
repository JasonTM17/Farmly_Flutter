import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { randomUUID } from 'node:crypto';
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
  const crossFarm = fixtureUser(suffix, 'crossfarm');
  const foreignOwner = fixtureUser(suffix, 'foreign-owner');
  const users = [owner, admin, member, manager, worker, viewer, orgViewer, suspended, crossFarm, foreignOwner];
  const userByToken = new Map(users.map((user) => [user.token, user]));

  const organizationId = randomUUID();
  const foreignOrganizationId = randomUUID();
  const organizationIds = [organizationId, foreignOrganizationId];
  const memberships = Object.fromEntries(
    ['owner', 'admin', 'member', 'manager', 'worker', 'viewer', 'orgviewer', 'suspended', 'crossfarm', 'foreign']
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
        ($13::uuid, $2::uuid, $14::uuid, $15::uuid, 'manager')
    `, [
      randomUUID(), organizationId, memberships.manager, farmAId,
      randomUUID(), memberships.worker,
      randomUUID(), memberships.viewer,
      randomUUID(), memberships.orgviewer,
      randomUUID(), memberships.suspended,
      randomUUID(), memberships.crossfarm, farmBId,
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

    stage('domain-fixture-parents-farm-a');
    const parentSpecs = [
      ['zonePlotA', 'ZONE_PARENT_PLOT', 'zone.create', 'zones', 'zone',
        () => ({ name: `Fixture plot ${s8()}`, type: 'crop_plot', geometry: { points: zonePoints() } })],
      ['zoneWaterA', 'ZONE_PARENT_WATER', 'zone.create', 'zones', 'zone',
        () => ({ name: `Fixture water zone ${s8()}`, type: 'water', geometry: { points: zonePoints() } })],
      ['speciesA', 'SPECIES_PARENT', 'cropSpecies.create', 'crop-species', 'cropSpecies',
        () => ({ name: `Fixture species ${s8()}`, harvestUnit: 'kg' })],
      ['herdTrackedA', 'HERD_PARENT_TRACKED', 'herd.create', 'herds', 'herd',
        () => ({ mode: 'tracked', species: 'cattle' })],
      ['herdBatchA', 'HERD_PARENT_BATCH', 'herd.create', 'herds', 'herd',
        () => ({ mode: 'batch', species: 'pigs' })],
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
        ids[`${label}Op`] = op.operationId;
      });
    }

    stage('domain-fixture-parents-farm-b');
    const foreignParentSpecs = [
      ['zoneB', 'ZONE_FOREIGN_PLOT', 'zone.create', 'zones', 'zone',
        () => ({ name: `Farm B plot ${s8()}`, type: 'crop_plot', geometry: { points: zonePoints() } })],
      ['speciesB', 'SPECIES_FOREIGN', 'cropSpecies.create', 'crop-species', 'cropSpecies',
        () => ({ name: `Farm B species ${s8()}`, harvestUnit: 'litre' })],
      ['herdB', 'HERD_FOREIGN', 'herd.create', 'herds', 'herd', () => ({ mode: 'tracked', species: 'goat' })],
    ];
    for (const [label, tag, type, slug, view, payload] of foreignParentSpecs) {
      ids[`${label}Id`] = randomUUID();
      await check(`${tag}_CREATE`, async () => {
        const op = intent(type, ids[`${label}Id`], payload(), farmEpochs.get(farmBId));
        const policyBefore = await policyVersion();
        const response = await domainCreate(owner.token, organizationId, farmBId, slug, op);
        await applyDomainIntent(response, op.operationId, view, farmBId, tag);
        await expectDomainApplied(farmBId, op.operationId, policyBefore, tag);
        versions.set(ids[`${label}Id`], 1);
      });
    }

    const resources = [
      {
        key: 'zone', tag: 'ZONE', slug: 'zones', plural: 'zones', view: 'zone', hasArchiveRoute: true,
        createType: 'zone.create', updateType: 'zone.update', archiveType: 'zone.archive',
        createPayload: () => ({ name: `Zone ${s8()}`, type: 'storage', geometry: { points: zonePoints() } }),
        createMissingField: () => ({ name: `Zone ${s8()}`, type: 'storage' }),
        createInvalid: () => ({ name: `Zone ${s8()}`, type: 'swamp', geometry: { points: zonePoints() } }),
        updatePayload: () => ({ name: `Zone renamed ${s8()}` }),
        updateInvalid: () => ({ type: 'swamp' }),
      },
      {
        key: 'cropSpecies', tag: 'CROPSPECIES', slug: 'crop-species', plural: 'cropSpecies', view: 'cropSpecies', hasArchiveRoute: true,
        createType: 'cropSpecies.create', updateType: 'cropSpecies.update', archiveType: 'cropSpecies.archive',
        createPayload: () => ({ name: `Species ${s8()}`, harvestUnit: 'kg' }),
        createMissingField: () => ({ name: `Species ${s8()}` }),
        createInvalid: () => ({ name: `Species ${s8()}`, harvestUnit: 'tonne' }),
        updatePayload: () => ({ harvestUnit: 'litre' }),
        updateInvalid: () => ({ harvestUnit: 'tonne' }),
      },
      {
        key: 'planting', tag: 'PLANTING', slug: 'plantings', plural: 'plantings', view: 'planting', hasArchiveRoute: true,
        createType: 'planting.create', updateType: 'planting.update', archiveType: 'planting.archive',
        createPayload: () => ({ cropSpeciesId: ids.speciesAId, plotId: ids.zonePlotAId, sowingDate: '2026-10-08' }),
        createMissingField: () => ({ cropSpeciesId: ids.speciesAId, plotId: ids.zonePlotAId }),
        createInvalid: () => ({ cropSpeciesId: ids.speciesAId, plotId: ids.zonePlotAId, sowingDate: '2026-10-08', status: 'germinated' }),
        updatePayload: () => ({ status: 'active' }),
        updateInvalid: () => ({ status: 'germinated' }),
        dependsOn: () => [ids.speciesAOp, ids.zonePlotAOp].filter(Boolean),
      },
      {
        key: 'herd', tag: 'HERD', slug: 'herds', plural: 'herds', view: 'herd', hasArchiveRoute: true,
        createType: 'herd.create', updateType: 'herd.update', archiveType: 'herd.archive',
        createPayload: () => ({ mode: 'batch', species: 'broilers' }),
        createMissingField: () => ({ species: 'broilers' }),
        createInvalid: () => ({ mode: 'mixed' }),
        updatePayload: () => ({ species: 'layers' }),
        updateInvalid: () => ({ status: 'retired' }),
      },
      {
        key: 'animal', tag: 'ANIMAL', slug: 'animals', plural: 'animals', view: 'animal', hasArchiveRoute: true,
        createType: 'animal.create', updateType: 'animal.update', archiveType: 'animal.archive',
        createPayload: () => ({ herdId: ids.herdTrackedAId, tag: `TAG-${s8()}` }),
        createMissingField: () => ({ herdId: ids.herdTrackedAId }),
        createInvalid: () => ({ herdId: ids.herdTrackedAId, tag: `TAG-${s8()}`, status: 'quarantined' }),
        updatePayload: () => ({ name: `Animal ${s8()}` }),
        updateInvalid: () => ({ status: 'quarantined' }),
        dependsOn: () => [ids.herdTrackedAOp].filter(Boolean),
      },
      {
        key: 'waterTank', tag: 'WATERTANK', slug: 'water-tanks', plural: 'waterTanks', view: 'waterTank', hasArchiveRoute: false,
        createType: 'waterTank.create', updateType: 'waterTank.update', archiveType: 'waterTank.archive',
        createPayload: () => ({ name: `Tank ${s8()}`, zoneId: ids.zoneWaterAId, capacityLitres: '5000' }),
        createMissingField: () => ({ name: `Tank ${s8()}`, zoneId: ids.zoneWaterAId }),
        createInvalid: () => ({ name: `Tank ${s8()}`, zoneId: ids.zoneWaterAId, capacityLitres: '5,000' }),
        updatePayload: () => ({ capacityLitres: '6000.5' }),
        updateInvalid: () => ({ capacityLitres: '12,5' }),
        dependsOn: () => [ids.zoneWaterAOp].filter(Boolean),
      },
    ];

    // ---- per-resource CRUD/CAS/archive matrix (spec04 §5.1 + openapi FarmMutation) ----
    for (const cfg of resources) {
      stage(`domain-${cfg.key}-crud`);
      const tag = cfg.tag;
      const subjectId = randomUUID();
      const subjectDeps = () => (cfg.dependsOn ? cfg.dependsOn() : []);

      await check(`${tag}_CREATE_APPLIES_DOMAIN_ENVELOPE`, async () => {
        const op = intent(cfg.createType, subjectId, cfg.createPayload(), epoch, { dependsOn: subjectDeps() });
        const policyBefore = await policyVersion();
        const response = await domainCreate(owner.token, organizationId, farmAId, cfg.slug, op);
        const { view } = await applyDomainIntent(response, op.operationId, cfg.view, farmAId, `${tag}_CREATE`);
        assert(view.id === subjectId, `${tag}_CREATE_VIEW_ID_MISMATCH`);
        assert(view.version === 1, `${tag}_CREATE_VERSION_${view.version}`);
        await expectDomainApplied(farmAId, op.operationId, policyBefore, `${tag}_CREATE`);
        const rowCount = await countDomainRow(cfg.key, farmAId, subjectId);
        if (rowCount !== null) assert(rowCount === 1, `${tag}_CREATE_ROW_MISSING`);
        versions.set(subjectId, 1);
      });

      await check(`${tag}_CREATE_VIA_FARM_BATCH_APPLIES`, async () => {
        const batchResourceId = randomUUID();
        const op = intent(cfg.createType, batchResourceId, cfg.createPayload(), epoch, { dependsOn: subjectDeps() });
        const policyBefore = await policyVersion();
        const response = await farmBatch(owner.token, organizationId, farmAId, [op], epoch);
        const body = await expectJson(response, 200, `${tag}_BATCH_CREATE`);
        assertBatchOutcome(body, op.operationId, 'applied', `${tag}_BATCH_CREATE`);
        await trackRevisionFromClock(farmAId, `${tag}_BATCH_CREATE`);
        await expectDomainApplied(farmAId, op.operationId, policyBefore, `${tag}_BATCH_CREATE`);
      });

      const createRejections = [
        ['MISSING_REQUIRED_FIELD', () => cfg.createMissingField()],
        ['INVALID_ENUM_OR_VALUE', () => cfg.createInvalid()],
        ['UNKNOWN_PAYLOAD_KEY', () => ({ ...cfg.createPayload(), unsupportedField: 'x' })],
      ];
      for (const [label, payload] of createRejections) {
        await check(`${tag}_CREATE_${label}_REJECTED`, async () => {
          const op = intent(cfg.createType, randomUUID(), payload(), epoch, { dependsOn: subjectDeps() });
          const policyBefore = await policyVersion();
          const revisionBefore = farmRevisions.get(farmAId);
          const response = await domainCreate(owner.token, organizationId, farmAId, cfg.slug, op);
          await expectDomainRejected(response, `${tag}_CREATE_${label}`);
          await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_CREATE_${label}`);
        });
      }

      await check(`${tag}_CREATE_NUMERIC_BASE_VERSION_REJECTED`, async () => {
        const op = intent(cfg.createType, randomUUID(), cfg.createPayload(), epoch, { baseVersion: 1 });
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainCreate(owner.token, organizationId, farmAId, cfg.slug, op);
        await expectDomainRejected(response, `${tag}_CREATE_NUMERIC_BASE_VERSION`);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_CREATE_NUMERIC_BASE_VERSION`);
      });

      await check(`${tag}_UPDATE_MISSING_BASE_VERSION_REJECTED`, async () => {
        const op = intent(cfg.updateType, subjectId, cfg.updatePayload(), epoch);
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainUpdate(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
        await expectDomainRejected(response, `${tag}_UPDATE_MISSING_BASE_VERSION`);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_UPDATE_MISSING_BASE_VERSION`);
      });

      await check(`${tag}_UPDATE_STALE_BASE_VERSION_CONFLICT`, async () => {
        const stale = (versions.get(subjectId) ?? 1) + 99;
        const op = intent(cfg.updateType, subjectId, cfg.updatePayload(), epoch, { baseVersion: stale });
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainUpdate(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
        await expectVersionConflict(response, `${tag}_UPDATE_STALE_BASE_VERSION`);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_UPDATE_STALE_BASE_VERSION`);
      });

      const updateRejections = [
        ['EMPTY_PAYLOAD', {}],
        ['UNKNOWN_PAYLOAD_KEY', { unsupportedField: 'x' }],
        ['INVALID_ENUM_OR_VALUE', null], // resolved per-resource below
      ];
      for (const [label, payload] of updateRejections) {
        await check(`${tag}_UPDATE_${label}_REJECTED`, async () => {
          const body = payload ?? cfg.updateInvalid();
          const op = intent(cfg.updateType, subjectId, body, epoch, { baseVersion: versions.get(subjectId) ?? 1 });
          const policyBefore = await policyVersion();
          const revisionBefore = farmRevisions.get(farmAId);
          const response = await domainUpdate(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
          await expectDomainRejected(response, `${tag}_UPDATE_${label}`);
          await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_UPDATE_${label}`);
        });
      }

      await check(`${tag}_UPDATE_APPLIES_AND_BUMPS_VERSION`, async () => {
        const baseVersion = versions.get(subjectId) ?? 1;
        const op = intent(cfg.updateType, subjectId, cfg.updatePayload(), epoch, { baseVersion });
        const policyBefore = await policyVersion();
        const response = await domainUpdate(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
        const { view } = await applyDomainIntent(response, op.operationId, cfg.view, farmAId, `${tag}_UPDATE`);
        assert(view.id === subjectId && view.version === baseVersion + 1, `${tag}_UPDATE_VERSION_${view.version}`);
        await expectDomainApplied(farmAId, op.operationId, policyBefore, `${tag}_UPDATE`);
        versions.set(subjectId, baseVersion + 1);
      });

      await check(`${tag}_ARCHIVE_APPLIES_AND_MAKES_RESOURCE_INACTIVE`, async () => {
        const baseVersion = versions.get(subjectId) ?? 1;
        const op = intent(cfg.archiveType, subjectId, {}, epoch, { baseVersion });
        const policyBefore = await policyVersion();
        if (cfg.hasArchiveRoute) {
          const response = await domainArchive(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
          const { view } = await applyDomainIntent(response, op.operationId, cfg.view, farmAId, `${tag}_ARCHIVE`);
          if (cfg.key === 'animal') assert(view.archived === true, 'ANIMAL_ARCHIVE_FLAG_MISSING');
          else assert(view.status === 'archived', `${tag}_ARCHIVE_STATUS_${view.status ?? 'MISSING'}`);
        } else {
          // waterTank.archive is kernel-registry-only per the approved decision:
          // no dedicated HTTP route, so the typed intent goes through POST
          // F/sync/mutations — the farm-scoped kernel entry point.
          const response = await farmBatch(owner.token, organizationId, farmAId, [op], epoch);
          const body = await expectJson(response, 200, `${tag}_ARCHIVE`);
          assertBatchOutcome(body, op.operationId, 'applied', `${tag}_ARCHIVE`);
          await trackRevisionFromClock(farmAId, `${tag}_ARCHIVE`);
        }
        await expectDomainApplied(farmAId, op.operationId, policyBefore, `${tag}_ARCHIVE`);
        const entry = await listEntry(owner.token, organizationId, farmAId, cfg.slug, cfg.plural, subjectId, `${tag}_ARCHIVED_LIST`);
        assert(
          !entry || entry.status === 'archived' || entry.archived === true,
          `${tag}_ARCHIVE_NOT_VISIBLE_AS_INACTIVE`,
        );
      });

      await check(`${tag}_WRITE_AFTER_ARCHIVE_REJECTED`, async () => {
        const op = intent(cfg.updateType, subjectId, cfg.updatePayload(), epoch, { baseVersion: versions.get(subjectId) ?? 1 });
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainUpdate(owner.token, organizationId, farmAId, cfg.slug, subjectId, op);
        await expectDomainNotApplied(response, `${tag}_WRITE_AFTER_ARCHIVE`);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `${tag}_WRITE_AFTER_ARCHIVE`);
      });
    }

    // ---- effective-role matrix on zone writes (spec01 §3/§7 allowlist) ----
    stage('domain-write-role-matrix');
    const roleCases = [
      ['ADMIN', admin, 'apply'],
      ['MANAGER', manager, 'apply'],   // org member + farmA manager grant
      ['MEMBER', member, 'deny'],      // org member, no farm grant
      ['WORKER', worker, 'deny'],      // org member + worker grant: no master writes per spec01 role table
      ['VIEWER', viewer, 'deny'],      // org member + viewer grant
      ['ORGVIEWER', orgViewer, 'deny'],// org-role viewer with stale elevated grant: read-only per spec01 §3
      ['SUSPENDED', suspended, 'deny'],
      ['CROSSFARM', crossFarm, 'deny'],// manager grant on farmB only; writing farmA denied
      ['FOREIGN', foreignOwner, 'deny'],// owner of a different organization
    ];
    for (const [label, user, mode] of roleCases) {
      await check(`ZONE_CREATE_${label}_${mode === 'apply' ? 'APPLIES' : 'DENIED'}`, async () => {
        const resourceId = randomUUID();
        const op = intent('zone.create', resourceId, {
          name: `Role matrix zone ${s8()}`, type: 'other', geometry: { points: zonePoints() },
        }, epoch);
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainCreate(user.token, organizationId, farmAId, 'zones', op);
        if (mode === 'apply') {
          const { view } = await applyDomainIntent(response, op.operationId, 'zone', farmAId, `ZONE_${label}`);
          assert(view.id === resourceId && view.version === 1, `ZONE_${label}_VIEW_INVALID`);
          await expectDomainApplied(farmAId, op.operationId, policyBefore, `ZONE_${label}`);
          versions.set(resourceId, 1);
        } else {
          await expectDenied(response, `ZONE_${label}_DENY`);
          await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `ZONE_${label}_DENY`);
        }
      });
    }
    await check('ZONE_CREATE_MANAGER_CROSS_FARM_DENIED', async () => {
      const op = intent('zone.create', randomUUID(), {
        name: `Cross-farm zone ${s8()}`, type: 'other', geometry: { points: zonePoints() },
      }, farmEpochs.get(farmBId));
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmBId);
      const response = await domainCreate(manager.token, organizationId, farmBId, 'zones', op);
      await expectDenied(response, 'ZONE_CROSS_FARM_DENY');
      await expectNoDomainMutation(farmBId, op.operationId, policyBefore, revisionBefore, 'ZONE_CROSS_FARM_DENY');
    });
    await check('ZONE_CREATE_MEMBER_VIA_FARM_BATCH_DENIED', async () => {
      const op = intent('zone.create', randomUUID(), {
        name: `Batch denied zone ${s8()}`, type: 'other', geometry: { points: zonePoints() },
      }, epoch);
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmAId);
      const response = await farmBatch(member.token, organizationId, farmAId, [op], epoch);
      await expectDenied(response, 'ZONE_MEMBER_BATCH_DENY');
      await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, 'ZONE_MEMBER_BATCH_DENY');
    });
    await check('ZONE_CREATE_FOREIGN_ORG_SCOPE_DENIED', async () => {
      const op = intent('zone.create', randomUUID(), {
        name: `Foreign scope zone ${s8()}`, type: 'other', geometry: { points: zonePoints() },
      }, '1');
      const response = await domainCreate(owner.token, foreignOrganizationId, farmAId, 'zones', op);
      await expectDenied(response, 'ZONE_FOREIGN_ORG_DENY');
    });

    // ---- composite same-scope parent FKs: references into another farm never resolve ----
    stage('cross-farm-parent-fk-rejections');
    const crossFkCases = [
      ['PLANTING_CROSS_FARM_CROP_SPECIES_REJECTED', 'planting.create', 'plantings',
        () => ({ cropSpeciesId: ids.speciesBId, plotId: ids.zonePlotAId, sowingDate: '2026-10-08' })],
      ['PLANTING_CROSS_FARM_PLOT_REJECTED', 'planting.create', 'plantings',
        () => ({ cropSpeciesId: ids.speciesAId, plotId: ids.zoneBId, sowingDate: '2026-10-08' })],
      ['ANIMAL_CROSS_FARM_HERD_REJECTED', 'animal.create', 'animals',
        () => ({ herdId: ids.herdBId, tag: `XF-${s8()}` })],
      ['WATERTANK_CROSS_FARM_ZONE_REJECTED', 'waterTank.create', 'water-tanks',
        () => ({ name: `Cross-farm tank ${s8()}`, zoneId: ids.zoneBId, capacityLitres: '1000' })],
    ];
    for (const [tag, type, slug, payload] of crossFkCases) {
      await check(tag, async () => {
        const op = intent(type, randomUUID(), payload(), epoch);
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainCreate(owner.token, organizationId, farmAId, slug, op);
        await expectDomainNotApplied(response, tag);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, tag);
      });
    }

    // ---- zone geometry: canonical [0,1] decimal-string scene polygons only ----
    stage('zone-geometry-validation');
    const geometryRejections = [
      ['TWO_POINTS', { points: zonePoints().slice(0, 2) }],
      ['POINT_OUT_OF_RANGE', { points: zonePoints([{ x: '1.5' }]) }],
      ['NON_STRING_COORDINATE', { points: [{ x: 0, y: '0' }, { x: '1', y: '0' }, { x: '0.5', y: '1' }] }],
      ['NONCANONICAL_DECIMAL', { points: zonePoints([{ x: '.5' }]) }],
      ['TOO_MANY_POINTS', { points: Array.from({ length: 129 }, (_, i) => ({ x: '0', y: `${(i % 2) ? '1' : '0'}` })) }],
    ];
    for (const [label, geometry] of geometryRejections) {
      await check(`ZONE_CREATE_GEOMETRY_${label}_REJECTED`, async () => {
        const op = intent('zone.create', randomUUID(), {
          name: `Geometry ${label} ${s8()}`, type: 'crop_plot', geometry,
        }, epoch);
        const policyBefore = await policyVersion();
        const revisionBefore = farmRevisions.get(farmAId);
        const response = await domainCreate(owner.token, organizationId, farmAId, 'zones', op);
        await expectDomainRejected(response, `ZONE_GEOMETRY_${label}`);
        await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, `ZONE_GEOMETRY_${label}`);
      });
    }
    await check('ZONE_CREATE_CANONICAL_POLYGON_APPLIES', async () => {
      const resourceId = randomUUID();
      const op = intent('zone.create', resourceId, {
        name: `Canonical zone ${s8()}`, type: 'crop_plot',
        geometry: { points: [{ x: '0.0', y: '0' }, { x: '1.0', y: '0.25' }, { x: '0.5', y: '1.00' }, { x: '0.125', y: '0.5' }] },
      }, epoch);
      const policyBefore = await policyVersion();
      const response = await domainCreate(owner.token, organizationId, farmAId, 'zones', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'zone', farmAId, 'ZONE_GEOMETRY_CANONICAL');
      assert(view.id === resourceId && view.version === 1, 'ZONE_GEOMETRY_CANONICAL_VIEW_INVALID');
      await expectDomainApplied(farmAId, op.operationId, policyBefore, 'ZONE_GEOMETRY_CANONICAL');
      versions.set(resourceId, 1);
    });

    // ---- livestock semantics: batch headcount from net movements, tracked from
    // alive animals only; herd mode immutable once livestock events exist ----
    stage('herd-mode-and-headcount');
    const seedLivestockMovement = async (farmId, herdId, delta) => {
      if (!domainTables.get('livestock_movements')) return 'table-absent';
      const variants = [
        { herd: 'herd_id', type: 'movement_type', delta: 'delta' },
        { herd: 'herd_id', type: 'type', delta: 'delta' },
        { herd: 'group_id', type: 'type', delta: 'delta' },
      ];
      for (const variant of variants) {
        try {
          await migration.query(
            `INSERT INTO public.livestock_movements (id, organization_id, farm_id, ${variant.herd}, ${variant.type}, ${variant.delta}, occurred_at, operation_id)
             VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'adjustment', $5, clock_timestamp(), $6::uuid)`,
            [randomUUID(), organizationId, farmId, herdId, delta, randomUUID()],
          );
          return 'seeded';
        } catch { /* try the next column variant */ }
      }
      return 'unmapped';
    };
    const herdHeadcount = async (herdId, code) => {
      const entry = await listEntry(owner.token, organizationId, farmAId, 'herds', 'herds', herdId, code);
      assert(entry && typeof entry.headcount === 'number', `${code}_HEADCOUNT_MISSING`);
      return entry.headcount;
    };
    const headcountIds = { batch: null, tracked: null };

    await check('HERD_MODE_IMMUTABLE_AFTER_EVENTS_REJECTED', async () => {
      // P06 owns movement facts; without the livestock_movements table there is
      // no event fixture to make the post-event mode boundary reachable.
      assert(domainTables.get('livestock_movements') === true, 'HERD_MODE_EVENT_FIXTURE_PENDING_P06');
      const herdId = randomUUID();
      const createOp = intent('herd.create', herdId, { mode: 'batch', species: 'cattle' }, epoch);
      const createResponse = await domainCreate(owner.token, organizationId, farmAId, 'herds', createOp);
      await applyDomainIntent(createResponse, createOp.operationId, 'herd', farmAId, 'HERD_MODE_SUBJECT');
      versions.set(herdId, 1);
      const seeded = await seedLivestockMovement(farmAId, herdId, 1);
      assert(seeded === 'seeded', `HERD_MODE_EVENT_SEED_${seeded.toUpperCase()}`);
      const updateOp = intent('herd.update', herdId, { mode: 'tracked' }, epoch, { baseVersion: 1 });
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmAId);
      const response = await domainUpdate(owner.token, organizationId, farmAId, 'herds', herdId, updateOp);
      await expectDomainRejected(response, 'HERD_MODE_IMMUTABLE', { allowConflict: true });
      await expectNoDomainMutation(farmAId, updateOp.operationId, policyBefore, revisionBefore, 'HERD_MODE_IMMUTABLE');
    });

    await check('HERD_HEADCOUNT_BATCH_NET_MOVEMENTS_FOUR', async () => {
      // Batch herd headcount = net sum of immutable movement deltas (spec01 §5,
      // spec04 §5.1 HerdDto.headcount). Movement facts are P06 scope, so when
      // the table is absent the oracle fails closed instead of skipping.
      assert(domainTables.get('livestock_movements') === true, 'HERD_HEADCOUNT_FIXTURE_PENDING_P06');
      const herdId = randomUUID();
      headcountIds.batch = herdId;
      const createOp = intent('herd.create', herdId, { mode: 'batch', species: 'cattle' }, epoch);
      const createResponse = await domainCreate(owner.token, organizationId, farmAId, 'herds', createOp);
      await applyDomainIntent(createResponse, createOp.operationId, 'herd', farmAId, 'HERD_HEADCOUNT_BATCH_SUBJECT');
      assert(await seedLivestockMovement(farmAId, herdId, 5) === 'seeded', 'HERD_HEADCOUNT_MOVEMENT_PLUS_SEED_FAILED');
      assert(await seedLivestockMovement(farmAId, herdId, -1) === 'seeded', 'HERD_HEADCOUNT_MOVEMENT_MINUS_SEED_FAILED');
      assert(await herdHeadcount(herdId, 'HERD_HEADCOUNT_BATCH') === 4, 'HERD_HEADCOUNT_BATCH_NOT_FOUR');
    });

    await check('HERD_HEADCOUNT_TRACKED_ALIVE_ONLY', async () => {
      // Tracked herd headcount counts animals whose status stays alive only
      // (sold/deceased excluded) — no double counting with batch herds.
      const herdId = randomUUID();
      headcountIds.tracked = herdId;
      const createOp = intent('herd.create', herdId, { mode: 'tracked', species: 'goat' }, epoch);
      const createResponse = await domainCreate(owner.token, organizationId, farmAId, 'herds', createOp);
      await applyDomainIntent(createResponse, createOp.operationId, 'herd', farmAId, 'HERD_HEADCOUNT_TRACKED_SUBJECT');
      const statuses = ['alive', 'sold', 'deceased'];
      for (const [index, status] of statuses.entries()) {
        const animalId = randomUUID();
        const animalOp = intent('animal.create', animalId, { herdId, tag: `HC-${index}-${s8()}`, status }, epoch);
        const animalResponse = await domainCreate(owner.token, organizationId, farmAId, 'animals', animalOp);
        const { view } = await applyDomainIntent(animalResponse, animalOp.operationId, 'animal', farmAId, `HERD_HEADCOUNT_ANIMAL_${status.toUpperCase()}`);
        assert(view.id === animalId && view.version === 1, 'HERD_HEADCOUNT_ANIMAL_VIEW_INVALID');
      }
      assert(await herdHeadcount(herdId, 'HERD_HEADCOUNT_TRACKED') === 1, 'HERD_HEADCOUNT_TRACKED_NOT_ONE');
    });

    await check('HERD_HEADCOUNT_COMBINED_FIVE', async () => {
      assert(
        domainTables.get('livestock_movements') === true && domainTables.get('animals') === true,
        'HERD_HEADCOUNT_FIXTURE_PENDING_P06',
      );
      assert(headcountIds.batch && headcountIds.tracked, 'HERD_HEADCOUNT_FIXTURE_UNAVAILABLE');
      const batch = await herdHeadcount(headcountIds.batch, 'HERD_HEADCOUNT_COMBINED');
      const tracked = await herdHeadcount(headcountIds.tracked, 'HERD_HEADCOUNT_COMBINED');
      assert(batch + tracked === 5, 'HERD_HEADCOUNT_COMBINED_NOT_FIVE');
    });

    // ---- animal archive flag is distinct from lifecycle status (decision §5) ----
    stage('animal-archive-distinct-from-status');
    await check('ANIMAL_LIVE_STATUS_NOT_ARCHIVED', async () => {
      const animalId = randomUUID();
      const op = intent('animal.create', animalId, { herdId: ids.herdTrackedAId, tag: `AL-${s8()}`, status: 'alive' }, epoch);
      const response = await domainCreate(owner.token, organizationId, farmAId, 'animals', op);
      const { view } = await applyDomainIntent(response, op.operationId, 'animal', farmAId, 'ANIMAL_LIVE_STATUS');
      assert(view.archived === false && view.status === 'alive', 'ANIMAL_ARCHIVE_FLAG_DEFAULT_INVALID');
    });
    await check('ANIMAL_ARCHIVE_PRESERVES_SOLD_STATUS', async () => {
      const animalId = randomUUID();
      const createOp = intent('animal.create', animalId, { herdId: ids.herdTrackedAId, tag: `SL-${s8()}`, status: 'sold' }, epoch);
      const createResponse = await domainCreate(owner.token, organizationId, farmAId, 'animals', createOp);
      await applyDomainIntent(createResponse, createOp.operationId, 'animal', farmAId, 'ANIMAL_SOLD_SUBJECT');
      const archiveOp = intent('animal.archive', animalId, {}, epoch, { baseVersion: 1 });
      const archiveResponse = await domainArchive(owner.token, organizationId, farmAId, 'animals', animalId, archiveOp);
      const { view } = await applyDomainIntent(archiveResponse, archiveOp.operationId, 'animal', farmAId, 'ANIMAL_SOLD_ARCHIVE');
      assert(view.archived === true && view.status === 'sold', 'ANIMAL_ARCHIVE_DID_NOT_PRESERVE_STATUS');
      const listed = await listEntry(owner.token, organizationId, farmAId, 'animals', 'animals', animalId, 'ANIMAL_SOLD_LIST');
      assert(!listed || (listed.archived === true && listed.status === 'sold'), 'ANIMAL_ARCHIVE_LIST_STATE_INVALID');
    });

    // ---- scope entry-point boundaries (spec04 §2/§3 transport rules) ----
    stage('scope-entry-point-boundaries');
    await check('ORG_BATCH_FARM_SCOPED_INTENT_REJECTED', async () => {
      // Org-scope ingress admits typed farm.create only; farm-scoped domain
      // intents on POST O/sync/mutations must reject without applying.
      const op = intent('zone.create', randomUUID(), {
        name: `Org-scope misroute ${s8()}`, type: 'other', geometry: { points: zonePoints() },
      }, '1');
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmAId);
      const response = await orgBatch(owner.token, organizationId, [op]);
      const body = await expectJson(response, 200, 'ORG_BATCH_DOMAIN_INTENT');
      assertBatchOutcome(body, op.operationId, 'rejected', 'ORG_BATCH_DOMAIN_INTENT');
      await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, 'ORG_BATCH_DOMAIN_INTENT');
    });
    await check('FARM_BATCH_FARM_CREATE_REJECTED', async () => {
      // farm.create is org-scoped only; replaying it into the farm-scoped
      // kernel entry point must reject (spec04 §3 scope binding).
      const op = intent('farm.create', randomUUID(), { name: `Misscoped farm ${s8()}`, timezone: 'Asia/Ho_Chi_Minh' }, epoch);
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmAId);
      const response = await farmBatch(owner.token, organizationId, farmAId, [op], epoch);
      await expectDomainRejected(response, 'FARM_BATCH_ORG_SCOPED_CREATE', { operationId: op.operationId });
      await expectNoDomainMutation(farmAId, op.operationId, policyBefore, revisionBefore, 'FARM_BATCH_ORG_SCOPED_CREATE');
    });

    // ---- farm profile/archive lifecycle on a dedicated fixture farm (farmC) ----
    stage('farm-archive-lifecycle');
    await check('FARM_UPDATE_APPLIES_AND_BUMPS_VERSION', async () => {
      const op = intent('farm.update', farmCId, { name: `Farm C renamed ${s8()}` }, farmEpochs.get(farmCId), { baseVersion: 1 });
      const policyBefore = await policyVersion();
      const response = await farmPatch(owner.token, organizationId, farmCId, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'farm', farmCId, 'FARM_UPDATE');
      assert(view.version === 2, `FARM_UPDATE_VERSION_${view.version}`);
      await expectDomainApplied(farmCId, op.operationId, policyBefore, 'FARM_UPDATE');
      const row = await migration.query('SELECT version::INTEGER AS v FROM public.farms WHERE organization_id = $1::uuid AND id = $2::uuid', [organizationId, farmCId]);
      assert(row.rows[0]?.v === 2, 'FARM_UPDATE_ROW_VERSION_NOT_TWO');
    });
    await check('FARM_ARCHIVE_BUMPS_POLICY_AND_MARKS_ARCHIVED', async () => {
      const op = intent('farm.archive', farmCId, {}, farmEpochs.get(farmCId), { baseVersion: 2 });
      const policyBefore = await policyVersion();
      const response = await farmArchivePost(owner.token, organizationId, farmCId, op);
      const { view } = await applyDomainIntent(response, op.operationId, 'farm', farmCId, 'FARM_ARCHIVE');
      assert(view.status === 'archived', `FARM_ARCHIVE_STATUS_${view.status ?? 'MISSING'}`);
      const counts = await domainCounts(organizationId, farmCId, op.operationId);
      assert(counts.applied_proofs === 1 && counts.changes === 1 && counts.audits === 1, 'FARM_ARCHIVE_KERNEL_RECORDS_INCOMPLETE');
      assert(BigInt(counts.policy_version) === BigInt(policyBefore) + 1n, 'FARM_ARCHIVE_POLICY_NOT_BUMPED');
      const row = await migration.query('SELECT status::TEXT AS s FROM public.farms WHERE organization_id = $1::uuid AND id = $2::uuid', [organizationId, farmCId]);
      assert(row.rows[0]?.s === 'archived', 'FARM_ARCHIVE_ROW_STATUS_INVALID');
    });
    await check('WRITE_AFTER_FARM_ARCHIVE_REJECTED', async () => {
      // S-07/S-18: an archived farm refuses every operational write; the attempt
      // leaves no applied proof, no revision bump and no policy change.
      const op = intent('zone.create', randomUUID(), {
        name: `Post-archive zone ${s8()}`, type: 'other', geometry: { points: zonePoints() },
      }, farmEpochs.get(farmCId));
      const policyBefore = await policyVersion();
      const revisionBefore = farmRevisions.get(farmCId);
      const response = await domainCreate(owner.token, organizationId, farmCId, 'zones', op);
      await expectDomainNotApplied(response, 'WRITE_AFTER_FARM_ARCHIVE');
      await expectNoDomainMutation(farmCId, op.operationId, policyBefore, revisionBefore, 'WRITE_AFTER_FARM_ARCHIVE');
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
      for (const table of ['livestock_movements', 'animals', 'herds', 'plantings', 'crop_species', 'water_tanks', 'zones']) {
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
    scope: 'P05 farm-domain wire contract (spec04 §5.1, decision 2026-10-08)',
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
