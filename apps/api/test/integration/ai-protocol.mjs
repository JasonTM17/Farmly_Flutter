import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { createHash, randomUUID } from 'node:crypto';
import { Client } from 'pg';

// P09 AI protocol suite — spec05 §§2-6 / spec06 C-01..C-10. Deterministic
// PG-fault cases run against the durable functions directly; end-to-end cases
// run the real Nest surface with the simulated provider seam. No assertion
// names live-provider behavior.

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const configuredDatabaseName = process.env.FARMLY_TEST_DATABASE_NAME;
const cursorSigningKey = process.env.CURSOR_SIGNING_KEY;
const authDatabaseUrl = process.env.DATABASE_URL_AUTH;

const SAFE_CODE = /^[A-Z0-9_]{1,140}$/;
const ACTOR_DOMAIN = 'farmly-operation-actor:v1:';
const PRICE_ID = 'ai-price-test-v1';

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
    const message = error instanceof Error ? String(error.message ?? error).slice(0, 200) : undefined;
    results.push({ stage: currentStage, case: caseCode, status: 'failed', detail, ...(message ? { message } : {}) });
  }
}

function actorPseudonym(actorId) {
  return createHash('sha256').update(ACTOR_DOMAIN).update(actorId, 'utf8').digest('hex');
}

function fixtureUser(suffix, label) {
  return {
    id: `ai-${label}-${suffix}`,
    email: `${label}-${suffix}@farmly.test`,
    token: `ai-${label}-${suffix}`,
    name: `AI ${label}`,
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
  const wireCode = typeof body?.error?.code === 'string' && SAFE_CODE.test(body.error.code)
    ? `_${body.error.code}` : '';
  assert(response.status === status, `${code}_STATUS_${response.status}${wireCode}`);
  return body;
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

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function main() {
  assert(migrationUrl && configuredDatabaseName === expectedDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assert(cursorSigningKey, 'CURSOR_SIGNING_KEY_REQUIRED');
  assertTarget(migrationUrl, 'farmly_migration');
  assertTarget(tenantConnectionString('farmly-ai-preflight'), 'farmly_tenant_app');

  const suffix = randomUUID().replaceAll('-', '');
  const httpApplicationName = `farmly-ai-http-${suffix}`;
  assert(Buffer.byteLength(httpApplicationName, 'utf8') <= 63, 'POSTGRES_APPLICATION_NAME_TOO_LONG');

  const owner = fixtureUser(suffix, 'owner');
  const member = fixtureUser(suffix, 'member');
  const foreign = fixtureUser(suffix, 'foreign');
  const users = [owner, member, foreign];
  const userByToken = new Map(users.map((user) => [user.token, user]));

  const organizationId = randomUUID();
  const foreignOrganizationId = randomUUID();
  const farmId = randomUUID();
  const membershipIds = { owner: randomUUID(), member: randomUUID(), foreign: randomUUID() };

  const migration = new Client({ connectionString: withApplicationName(migrationUrl, `farmly-ai-migration-${suffix}`) });
  // A raw tenant-role connection for deterministic definer calls with GUCs.
  const tenantPg = new Client({
    connectionString: withApplicationName(tenantConnectionString(`farmly-ai-tenant-${suffix}`), `farmly-ai-tenant-${suffix}`),
  });
  let app;
  let tenant;
  let operationError;
  let operationStage;
  let cleanupError;

  // Simulated provider control: the seam reads this per stream call so cases
  // can inject delay/usage faults deterministically. capturedRecords keeps the
  // serialized provider payload for egress assertions (spec05 §2 FAI-28).
  const providerControl = { delayMs: 0, emitUsage: true, finishReason: 'stop', captured: [] };

  const setup = async () => {
    stage('setup-connect-and-check-ai-schema');
    await migration.connect();
    await tenantPg.connect();
    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'MIGRATION_DATABASE_IDENTITY_INVALID');
    const schema = await migration.query(`
      SELECT to_regclass('public.ai_requests') IS NOT NULL AS requests,
             to_regclass('public.ai_events') IS NOT NULL AS events,
             to_regclass('public.ai_consents') IS NOT NULL AS consents,
             to_regclass('public.ai_snapshots') IS NOT NULL AS snapshots,
             to_regclass('public.ai_conversations') IS NOT NULL AS conversations,
             to_regclass('public.ai_messages') IS NOT NULL AS messages,
             to_regclass('public.ai_org_counters') IS NOT NULL AS org_counters,
             to_regclass('public.ai_price_snapshots') IS NOT NULL AS prices,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_ai_create_request') AS create_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_ai_dispatch_fence') AS fence_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_ai_terminalize') AS terminal_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_ai_recover_interrupted') AS recover_fn
    `);
    assert(Object.values(schema.rows[0]).every(Boolean), 'AI_SCHEMA_NOT_READY');

    stage('setup-seed-actors-organizations-farm-consent-price');
    await insertVerifiedUsers(migration, users);
    await migration.query(`
      INSERT INTO public.organizations (id, name, continuity_epoch)
      VALUES ($1::uuid, 'AI fixture org', 1), ($2::uuid, 'Foreign fixture org', 1)
    `, [organizationId, foreignOrganizationId]);
    await migration.query(`
      INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status)
      VALUES
        ($1::uuid, $2::uuid, $3, 'owner', 'active'),
        ($4::uuid, $2::uuid, $5, 'member', 'active'),
        ($6::uuid, $7::uuid, $8, 'owner', 'active')
    `, [membershipIds.owner, organizationId, owner.id, membershipIds.member, member.id,
        membershipIds.foreign, foreignOrganizationId, foreign.id]);
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone, status, version, created_at, updated_at)
      VALUES ($1::uuid, $2::uuid, 'AI Fixture Farm', 'Asia/Ho_Chi_Minh', 'active', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `, [farmId, organizationId]);
    await migration.query(`
      INSERT INTO public.farm_clocks (organization_id, farm_id, continuity_epoch, revision, pruned_through_revision, created_at, updated_at)
      VALUES ($1::uuid, $2::uuid, 1, 1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `, [organizationId, farmId]);
    await migration.query(`
      INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
      VALUES ($1::uuid, $2::uuid, $3::uuid, 'viewer')
    `, [organizationId, membershipIds.member, farmId]);
    await migration.query(`
      INSERT INTO public.ai_consents (organization_id, user_id, actor_pseudonym, revision, granted,
                                      ai_safe_summary_opted_in, granted_at, updated_at)
      VALUES ($1::uuid, $2, $3, 1, TRUE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `, [organizationId, owner.id, actorPseudonym(owner.id)]);
    await migration.query(`
      INSERT INTO public.ai_price_snapshots (id, model, input_micros_per_mtok, output_micros_per_mtok, currency, captured_at)
      VALUES ($1, 'deepseek-flash', 70, 140, 'USD', CURRENT_TIMESTAMP)
      ON CONFLICT (id) DO NOTHING
    `, [PRICE_ID]);
  };

  const buildApp = async (controllers, providers) => {
    class AiHttpTestModule {}
    Module({ controllers, providers })(AiHttpTestModule);
    const instance = await NestFactory.create(AiHttpTestModule, new ExpressAdapter(), { logger: false });
    const filterModule = await import(new URL('../../dist/common/farmly-http-exception.filter.js', import.meta.url));
    instance.useGlobalFilters(new filterModule.FarmlyHttpExceptionFilter());
    await instance.listen(0, '127.0.0.1');
    return instance;
  };

  try {
    await setup();

    stage('setup-load-http-surface');
    const [
      { TenantDatabaseService },
      { FarmlyAiService },
      { FarmlyAiConsentController, FarmlyAiController },
      { AiDispatcherService },
      { VerifiedSessionGuard },
      { FARMLY_AUTH },
      { API_ENVIRONMENT },
      { AI_PROVIDER, SimulatedAiProvider },
    ] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/ai/ai.service.js', import.meta.url)),
      import(new URL('../../dist/ai/ai.controller.js', import.meta.url)),
      import(new URL('../../dist/ai/ai-dispatcher.service.js', import.meta.url)),
      import(new URL('../../dist/auth/verified-session.guard.js', import.meta.url)),
      import(new URL('../../dist/auth/auth.module.js', import.meta.url)),
      import(new URL('../../dist/config/environment.js', import.meta.url)),
      import(new URL('../../dist/ai/ai-provider.js', import.meta.url)),
    ]);

    const apiEnvironment = {
      nodeEnv: 'test',
      port: 0,
      databaseUrlTenant: tenantConnectionString(httpApplicationName),
      databaseUrlAuth: authDatabaseUrl ?? 'postgresql://farmly_auth_app:unused@postgres:5432/farmly_test_261005',
      betterAuthSecret: process.env.BETTER_AUTH_SECRET ?? 'farmly-ai-test-secret-0000000000000000',
      betterAuthUrl: 'http://127.0.0.1:3000',
      smtpHost: process.env.SMTP_HOST ?? 'mailpit',
      smtpPort: 1025,
      smtpSecure: false,
      smtpRequireTls: false,
      smtpFrom: 'Farmly <no-reply@farmly.test>',
      cursorSigningKey,
      aiEnabled: true,
      deepSeekBaseUrl: 'https://api.deepseek.com',
      deepSeekModel: 'deepseek-flash',
      aiProjectCostCap: '5.00',
      aiOrgTokenCap: 1_000_000,
      aiUserRateLimit: 8,
      aiMaxOutputTokens: 256,
      aiMaxInputBytes: 65536,
      aiPriceSnapshotId: PRICE_ID,
      aiRequestTimeoutMs: 15000,
      weatherEnabled: false,
      weatherFreshTtlSeconds: 3600,
    };
    const configStub = { get: (key) => (key === 'farmlyEnvironment' ? apiEnvironment : undefined) };
    tenant = new TenantDatabaseService(configStub);
    const auth = {
      api: {
        getSession: async ({ headers }) => {
          const authorization = headers.get('authorization') ?? '';
          const user = authorization.startsWith('Bearer ') ? userByToken.get(authorization.slice(7)) : undefined;
          return user ? sessionFor(user) : null;
        },
      },
    };

    // The simulated provider captures the serialized request so the suite can
    // inspect actual egress bytes (spec05 §2 — FAI-28 oracle).
    const controlledProvider = {
      name: 'simulated-controlled',
      stream: (request) => {
        providerControl.captured.push(JSON.stringify(request.messages));
        return (async function* () {
          const source = new SimulatedAiProvider({
            delayMs: providerControl.delayMs,
            emitUsage: providerControl.emitUsage,
            finishReason: providerControl.finishReason,
          });
          yield* source.stream(request);
        })();
      },
    };

    const aiService = new FarmlyAiService(tenant, configStub);
    const dispatcher = new AiDispatcherService(tenant, controlledProvider, configStub);

    app = await buildApp(
      [FarmlyAiController, FarmlyAiConsentController],
      [
        VerifiedSessionGuard,
        { provide: FARMLY_AUTH, useValue: auth },
        { provide: API_ENVIRONMENT, useValue: apiEnvironment },
        { provide: ConfigService, useValue: configStub },
        { provide: TenantDatabaseService, useValue: tenant },
        { provide: FarmlyAiService, useValue: aiService },
        { provide: AiDispatcherService, useValue: dispatcher },
        { provide: AI_PROVIDER, useValue: controlledProvider },
      ],
    );
    await tenant.onModuleInit().catch(() => {});
    const address = app.getHttpServer().address();
    assert(address && typeof address !== 'string', 'AI_HTTP_LISTENER_UNAVAILABLE');
    const origin = `http://127.0.0.1:${address.port}`;
    const aiBase = (farm = farmId) => `${origin}/v1/organizations/${organizationId}/farms/${farm}/ai`;

    const createRequest = (token, body, key = body.clientRequestId) => fetch(`${aiBase()}/requests`, {
      method: 'POST',
      headers: httpHeaders(token, { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) }),
      body: JSON.stringify(body),
    });
    const getRequest = (token, requestId, farm = farmId) =>
      fetch(`${aiBase(farm)}/requests/${requestId}`, { headers: httpHeaders(token) });
    const cancelRequest = (token, requestId) =>
      fetch(`${aiBase()}/requests/${requestId}/cancel`, {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify({}),
      });
    const listConversations = (token, farm = farmId) =>
      fetch(`${aiBase(farm)}/conversations`, { headers: httpHeaders(token) });
    const listMessages = (token, conversationId) =>
      fetch(`${aiBase()}/conversations/${conversationId}/messages`, { headers: httpHeaders(token) });
    const setConsent = (token, body, org = organizationId) =>
      fetch(`${origin}/v1/organizations/${org}/ai/consent`, {
        method: 'PUT',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify(body),
      });

    const requestBody = (overrides = {}) => ({
      schemaVersion: 'farmly-ai-request.v1',
      clientRequestId: randomUUID(),
      prompt: 'Cây lúa của tôi cần gì trong tuần này?',
      consentRevision: 1,
      contextMode: 'authorized-summary',
      ...overrides,
    });

    const waitTerminal = async (requestId, timeoutMs = 12000) => {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const response = await getRequest(owner.token, requestId);
        const body = await readBody(response);
        const status = body?.data?.status;
        if (status && !['queued', 'dispatching', 'generating', 'stopping'].includes(status)) {
          return body.data;
        }
        await sleep(120);
      }
      return null;
    };

    // Consume the SSE stream with an AbortController; returns parsed frames.
    const consumeEvents = async (token, requestId, { lastEventId, untilTypes = [], timeoutMs = 12000 } = {}) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      const response = await fetch(`${aiBase()}/requests/${requestId}/events`, {
        headers: httpHeaders(token, lastEventId ? { 'last-event-id': lastEventId } : {}),
        signal: controller.signal,
      });
      if (!response.ok) {
        clearTimeout(timer);
        return { status: response.status, frames: [], body: await readBody(response) };
      }
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      const frames = [];
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          let boundary;
          while ((boundary = buffer.indexOf('\n\n')) >= 0) {
            const block = buffer.slice(0, boundary);
            buffer = buffer.slice(boundary + 2);
            if (block.startsWith(':')) continue;
            const frame = {};
            for (const line of block.split('\n')) {
              if (line.startsWith('id:')) frame.id = line.slice(3).trim();
              else if (line.startsWith('event:')) frame.event = line.slice(6).trim();
              else if (line.startsWith('data:')) frame.data = JSON.parse(line.slice(5).trim());
            }
            if (frame.id) frames.push(frame);
            if (frame.event && untilTypes.includes(frame.event)) {
              controller.abort();
            }
          }
        }
      } catch { /* aborted */ }
      clearTimeout(timer);
      reader.releaseLock();
      return { status: 200, frames };
    };

    const grantConsent = (userId, revision = 1, granted = true) => migration.query(`
      INSERT INTO public.ai_consents (organization_id, user_id, actor_pseudonym, revision, granted, granted_at, withdrawn_at, updated_at)
      VALUES ($1::uuid, $2, $3, $4, $5, CASE WHEN $5 THEN CURRENT_TIMESTAMP END,
              CASE WHEN $5 THEN NULL ELSE CURRENT_TIMESTAMP END, CURRENT_TIMESTAMP)
      ON CONFLICT (organization_id, user_id) DO UPDATE
        SET revision = $4, granted = $5,
            granted_at = CASE WHEN $5 THEN CURRENT_TIMESTAMP END,
            withdrawn_at = CASE WHEN $5 THEN NULL ELSE CURRENT_TIMESTAMP END,
            updated_at = CURRENT_TIMESTAMP
    `, [organizationId, userId, actorPseudonym(userId), revision, granted]);

    const counters = async () => {
      const rows = await migration.query(
        'SELECT reserved_output_tokens::TEXT AS reserved, reported_tokens::TEXT AS reported, in_flight FROM public.ai_org_counters WHERE organization_id = $1::uuid',
        [organizationId]);
      const project = await migration.query(
        'SELECT reserved_cost_micros::TEXT AS reserved, reported_cost_micros::TEXT AS reported FROM public.ai_project_counters WHERE singleton');
      return { org: rows.rows[0] ?? {}, project: project.rows[0] ?? {} };
    };

    const requestRows = (where = 'TRUE') =>
      migration.query(`SELECT * FROM public.ai_requests WHERE ${where}`);

    const tenantCall = async (user, sql, params = []) => {
      const client = tenantPg;
      await client.query('BEGIN');
      try {
        await client.query(`SELECT set_config('app.actor_id', $1, TRUE)`, [user.id]);
        await client.query(`SELECT set_config('app.actor_pseudonym', $1, TRUE)`, [actorPseudonym(user.id)]);
        const result = await client.query(sql, params);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
      }
    };

    // ============================================================ C-01 create
    stage('C-01-idempotent-create-single-attempt');
    let requestA;
    await check('C-01', async () => {
      const body = requestBody();
      const first = await expectJson(await createRequest(owner.token, body), 202, 'C01_CREATE');
      requestA = first.data.requestId;
      assert(first.data.state === 'queued', 'C01_STATE_QUEUED');
      assert(typeof first.data.eventsUrl === 'string' && first.data.eventsUrl.includes(requestA), 'C01_EVENTS_URL');
      assert(typeof first.data.statusUrl === 'string' && first.data.statusUrl.endsWith(requestA), 'C01_STATUS_URL');

      // DoubleTap / retry: same key + same payload replays the same request.
      const replay = await expectJson(await createRequest(owner.token, body), 202, 'C01_REPLAY');
      assert(replay.data.requestId === requestA, 'C01_REPLAY_ID_MISMATCH');
      assert(replay.data.replayed === true, 'C01_REPLAY_FLAG');

      // Same key + changed payload is a hard 409 — never a second attempt.
      const changed = await createRequest(owner.token, { ...body, prompt: 'different prompt' });
      assert(changed.status === 409, 'C01_CHANGED_STATUS');
      const rows = await requestRows(`client_request_id = '${body.clientRequestId}'::uuid`);
      assert(rows.rowCount === 1, 'C01_ROW_COUNT');

      const terminal = await waitTerminal(requestA);
      assert(terminal?.status === 'completed', `C01_TERMINAL_${terminal?.status ?? 'TIMEOUT'}`);
      assert(terminal.usageState === 'reported', `C01_USAGE_${terminal.usageState}`);
      assert(terminal.finalMessageId && terminal.finalBody, 'C01_FINAL_MESSAGE');
    });

    // ============================================ C-02 crash after marker
    stage('C-02-stale-attempt-recovery');
    await check('C-02', async () => {
      // A request whose attempt marker is stale belongs to a dead executor:
      // recovery marks it interrupted + usage unknown and never re-dispatches.
      const staleId = randomUUID();
      const conversation = await migration.query(`
        INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
        VALUES ($1::uuid, $2::uuid, $3, $4) RETURNING id`, [organizationId, farmId, owner.id, actorPseudonym(owner.id)]);
      const conversationId = conversation.rows[0].id;
      await migration.query(`
        INSERT INTO public.ai_requests (
          id, organization_id, farm_id, conversation_id, user_id, actor_pseudonym,
          client_request_id, request_hash, consent_revision, context_mode, prompt,
          prompt_bytes, status, attempt_id, upstream_started_at, reserved_output_tokens,
          reserved_input_bytes, reserved_cost_micros)
        VALUES ($7::uuid, $1::uuid, $2::uuid, $3::uuid, $4, $5,
          $6::uuid, repeat('a', 64), 1, 'none', 'stale attempt', 12,
          'generating', gen_random_uuid(), CURRENT_TIMESTAMP - INTERVAL '10 minutes', 256, 65536, 50)
      `, [organizationId, farmId, conversationId, owner.id, actorPseudonym(owner.id), randomUUID(), staleId]);
      await migration.query(`
        INSERT INTO public.ai_org_counters (organization_id, in_flight)
        VALUES ($1::uuid, 1)
        ON CONFLICT (organization_id) DO UPDATE SET in_flight = ai_org_counters.in_flight + 1`,
        [organizationId]);
      const before = await counters();
      const recovered = await tenantCall(owner,
        'SELECT public.farmly_ai_recover_interrupted($1, $2, 120) AS count',
        [owner.id, actorPseudonym(owner.id)]);
      assert(Number(recovered.rows[0].count) >= 1, 'C02_RECOVER_COUNT');
      const row = await migration.query('SELECT status, usage_state, terminal_at FROM public.ai_requests WHERE id = $1::uuid', [staleId]);
      assert(row.rows[0].status === 'interrupted', 'C02_STATUS');
      assert(row.rows[0].usage_state === 'unknown', 'C02_USAGE');
      assert(row.rows[0].terminal_at !== null, 'C02_TERMINAL_AT');
      const events = await migration.query('SELECT type FROM public.ai_events WHERE request_id = $1::uuid', [staleId]);
      assert(events.rowCount === 1 && events.rows[0].type === 'request.status', 'C02_TERMINAL_EVENT');
      const after = await counters();
      assert(Number(after.org.in_flight) === Number(before.org.in_flight) - 1, 'C02_IN_FLIGHT_DECREMENTED');
      // Reservation stays held — unknown usage is never auto-refunded.
      assert(after.org.reserved === before.org.reserved, 'C02_RESERVATION_HELD');
    });

    // ============================================ C-03 duplicate terminal
    stage('C-03-terminal-cas-uniqueness');
    await check('C-03', async () => {
      const raceId = randomUUID();
      const conversation = await migration.query(`
        INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
        VALUES ($1::uuid, $2::uuid, $3, $4) RETURNING id`, [organizationId, farmId, owner.id, actorPseudonym(owner.id)]);
      await migration.query(`
        INSERT INTO public.ai_requests (
          id, organization_id, farm_id, conversation_id, user_id, actor_pseudonym,
          client_request_id, request_hash, consent_revision, context_mode, prompt,
          prompt_bytes, status, attempt_id, upstream_started_at, reserved_output_tokens,
          reserved_input_bytes, reserved_cost_micros)
        VALUES ($7::uuid, $1::uuid, $2::uuid, $3::uuid, $4, $5,
          $6::uuid, repeat('b', 64), 1, 'none', 'race', 4,
          'generating', gen_random_uuid(), CURRENT_TIMESTAMP, 256, 65536, 50)
      `, [organizationId, farmId, conversation.rows[0].id, owner.id, actorPseudonym(owner.id), randomUUID(), raceId]);
      // Keep the counter ledger consistent with a real reservation so the
      // settle-once invariant is measurable.
      await migration.query(`
        INSERT INTO public.ai_org_counters (organization_id, in_flight)
        VALUES ($1::uuid, 1)
        ON CONFLICT (organization_id) DO UPDATE SET in_flight = ai_org_counters.in_flight + 1`,
        [organizationId]);
      const before = await counters();
      const first = await tenantCall(owner, `
        SELECT public.farmly_ai_terminalize(
          $1::uuid, 'cancelled'::public.ai_request_status, 'unknown'::public.ai_usage_state,
          'response.cancelled'::public.ai_event_type, '{"partial":true,"usageState":"unknown"}'::jsonb) AS won
      `, [raceId]);
      assert(first.rows[0].won === true, 'C03_FIRST_TERMINAL');
      const second = await tenantCall(owner, `
        SELECT public.farmly_ai_terminalize(
          $1::uuid, 'completed'::public.ai_request_status, 'reported'::public.ai_usage_state,
          'response.completed'::public.ai_event_type, '{"usageState":"reported"}'::jsonb,
          10, 10, 20, 5) AS won
      `, [raceId]);
      assert(second.rows[0].won === false, 'C03_SECOND_TERMINAL_LOST');
      const events = await migration.query('SELECT count(*)::INT AS n FROM public.ai_events WHERE request_id = $1::uuid', [raceId]);
      assert(events.rows[0].n === 1, 'C03_ONE_TERMINAL_EVENT');
      const after = await counters();
      assert(Number(after.org.in_flight) === Number(before.org.in_flight) - 1, 'C03_SETTLED_ONCE');
    });

    // ============================================ C-04 quota conservation
    stage('C-04-rate-and-quota-gates');
    await check('C-04', async () => {
      // Rate gate (deterministic): seed 8 non-terminal requests owned by the
      // caller; aiUserRateLimit=8, so the next create must be refused. The
      // seeded rows are then deleted — they never touched the counters.
      const convo = await migration.query(`
        INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
        VALUES ($1::uuid, $2::uuid, $3, $4) RETURNING id`,
        [organizationId, farmId, owner.id, actorPseudonym(owner.id)]);
      const seeded = [];
      for (let index = 0; index < 8; index += 1) {
        const id = randomUUID();
        seeded.push(id);
        await migration.query(`
          INSERT INTO public.ai_requests (
            id, organization_id, farm_id, conversation_id, user_id, actor_pseudonym,
            client_request_id, request_hash, consent_revision, context_mode, prompt,
            prompt_bytes, status, attempt_id, upstream_started_at,
            reserved_output_tokens, reserved_input_bytes, reserved_cost_micros)
          VALUES ($7::uuid, $1::uuid, $2::uuid, $3::uuid, $4, $5,
            $6::uuid, repeat('d', 64), 1, 'none', 'seeded in-flight', 16,
            'generating', gen_random_uuid(), CURRENT_TIMESTAMP, 256, 65536, 50)
        `, [organizationId, farmId, convo.rows[0].id, owner.id, actorPseudonym(owner.id), randomUUID(), id]);
      }
      const over = await createRequest(owner.token, requestBody());
      // Contract: 429 for "rate or AI quota limit reached before dispatch".
      assert(over.status === 429, `C04_RATE_STATUS_${over.status}`);
      await migration.query('DELETE FROM public.ai_requests WHERE id = ANY($1::uuid[])', [seeded]);

      // Org token cap: report nearly all of the 1,000,000 budget so the next
      // reservation must fail closed without any upstream attempt.
      const snapshotCounters = await counters();
      await migration.query(`
        UPDATE public.ai_org_counters
           SET reported_tokens = 1000000
         WHERE organization_id = $1::uuid`, [organizationId]);
      const capped = await createRequest(owner.token, requestBody());
      assert(capped.status === 429, `C04_CAP_STATUS_${capped.status}`);
      const capBody = await readBody(capped);
      assert(capBody?.error?.code === 'AI_QUOTA_EXCEEDED', `C04_CAP_CODE_${capBody?.error?.code}`);
      await migration.query(`
        UPDATE public.ai_org_counters
           SET reported_tokens = $2::bigint, reserved_output_tokens = $3::bigint
         WHERE organization_id = $1::uuid`,
        [organizationId, snapshotCounters.org.reported ?? '0', snapshotCounters.org.reserved ?? '0']);
    });

    // ============================================ C-05 scope and consent
    stage('C-05-scope-consent-gates');
    await check('C-05', async () => {
      // Foreign actor: no org membership → denied, no existence oracle.
      const foreignCreate = await createRequest(foreign.token, requestBody());
      assert([403, 404].includes(foreignCreate.status), `C05_FOREIGN_${foreignCreate.status}`);
      // Member without consent: grant + membership exist but ai_consent does not.
      const memberCreate = await createRequest(member.token, requestBody());
      assert(memberCreate.status === 403, `C05_NOCONSENT_${memberCreate.status}`);
      const memberBody = await readBody(memberCreate);
      assert(memberBody?.error?.code === 'AI_CONSENT_REQUIRED' || memberBody?.error?.code === 'PERMISSION_DENIED', `C05_CODE_${memberBody?.error?.code}`);
      // Withdrawn consent (revision bump) blocks new creates.
      await grantConsent(member.id, 1, false);
      const withdrawn = await createRequest(member.token, requestBody());
      assert(withdrawn.status === 403, `C05_WITHDRAWN_${withdrawn.status}`);
      // Member's own request cannot be read by another owner.
      const own = await expectJson(await createRequest(owner.token, requestBody()), 202, 'C05_OWN');
      const memberRead = await getRequest(member.token, own.data.requestId);
      assert(memberRead.status === 404, `C05_CROSS_READ_${memberRead.status}`);
      await waitTerminal(own.data.requestId);
    });

    // ============================================ C-06 typed events only
    stage('C-06-safe-typed-events');
    await check('C-06', async () => {
      const created = await expectJson(await createRequest(owner.token, requestBody({ prompt: 'ký tự unicode ứ đ 🌾' })), 202, 'C06_CREATE');
      const terminal = await waitTerminal(created.data.requestId);
      assert(terminal?.status === 'completed', `C06_TERMINAL_${terminal?.status}`);
      const events = await migration.query(
        'SELECT type, data FROM public.ai_events WHERE request_id = $1::uuid ORDER BY seq',
        [created.data.requestId]);
      const allowed = new Set(['request.started', 'response.delta', 'request.status',
        'response.references', 'usage.reported', 'response.completed', 'response.cancelled', 'response.error']);
      for (const event of events.rows) {
        assert(allowed.has(event.type), `C06_EVENT_TYPE_${event.type}`);
        const serialized = JSON.stringify(event.data);
        assert(!serialized.includes('reasoning'), 'C06_REASONING_LEAK');
        // The approved model alias is legitimate provenance (spec05 §5); what
        // must never appear is the credential material.
        assert(!serialized.includes('apiKey') && !serialized.includes('Bearer '), 'C06_SECRET_LEAK');
      }
      // UTF-8 deltas round-trip intact (no replacement characters).
      const deltas = events.rows.filter((e) => e.type === 'response.delta').map((e) => e.data.textDelta).join('');
      assert(!deltas.includes('�'), 'C06_UTF8_LOSS');
    });

    // ============================================ C-07 replay semantics
    stage('C-07-disconnect-replay');
    await check('C-07', async () => {
      const created = await expectJson(await createRequest(owner.token, requestBody()), 202, 'C07_CREATE');
      const requestId = created.data.requestId;
      // Disconnect mid-stream, then replay from the persisted log.
      const firstPass = await consumeEvents(owner.token, requestId, { timeoutMs: 15000 });
      assert(firstPass.status === 200, `C07_STREAM_${firstPass.status}`);
      const terminal = await waitTerminal(requestId);
      assert(terminal?.status === 'completed', `C07_TERMINAL_${terminal?.status}`);
      const all = await consumeEvents(owner.token, requestId, { timeoutMs: 8000 });
      const seqs = all.frames.map((frame) => Number.parseInt(frame.id.split(':')[1], 10));
      for (let index = 1; index < seqs.length; index += 1) {
        assert(seqs[index] === seqs[index - 1] + 1, 'C07_SEQ_GAP');
      }
      // Replay from a middle id returns only newer persisted events — the
      // disconnect never caused a second provider attempt.
      const mid = all.frames[Math.floor(all.frames.length / 2)];
      const replayed = await consumeEvents(owner.token, requestId, { lastEventId: mid.id, timeoutMs: 8000 });
      const replaySeqs = replayed.frames.map((frame) => Number.parseInt(frame.id.split(':')[1], 10));
      const midSeq = Number.parseInt(mid.id.split(':')[1], 10);
      assert(replaySeqs.every((seq) => seq > midSeq), 'C07_REPLAY_BOUNDARY');
      assert(providerControl.captured.length >= 1, 'C07_CAPTURE');
      // Wrong-request and future-seq cursors are rejected, not replayed.
      const wrong = await fetch(`${aiBase()}/requests/${requestId}/events`, {
        headers: httpHeaders(owner.token, { 'last-event-id': `${randomUUID()}:1` }),
      });
      assert(wrong.status === 400, `C07_WRONG_ID_${wrong.status}`);
      const future = await fetch(`${aiBase()}/requests/${requestId}/events`, {
        headers: httpHeaders(owner.token, { 'last-event-id': `${requestId}:999999` }),
      });
      assert(future.status === 400, `C07_FUTURE_${future.status}`);
      const foreignStream = await fetch(`${aiBase()}/requests/${requestId}/events`, {
        headers: httpHeaders(member.token),
      });
      assert(foreignStream.status === 404, `C07_FOREIGN_STREAM_${foreignStream.status}`);
    });

    // ============================================ C-08 usage settlement
    stage('C-08-usage-settlement');
    await check('C-08', async () => {
      const before = await counters();
      providerControl.emitUsage = false;
      const created = await expectJson(await createRequest(owner.token, requestBody()), 202, 'C08_CREATE');
      const terminal = await waitTerminal(created.data.requestId);
      providerControl.emitUsage = true;
      assert(terminal?.status === 'completed', `C08_TERMINAL_${terminal?.status}`);
      assert(terminal.usageState === 'unknown', `C08_USAGE_${terminal.usageState}`);
      assert(terminal.reportedCostMicros === null || terminal.reportedCostMicros === undefined, 'C08_COST_STATE');
      const after = await counters();
      // Unknown usage: reservation is conservatively held, never refunded.
      assert(BigInt(after.org.reserved) > BigInt(before.org.reserved), 'C08_RESERVATION_HELD');
      const requestRow = await migration.query(
        'SELECT reported_cost_micros FROM public.ai_requests WHERE id = $1::uuid', [created.data.requestId]);
      assert(requestRow.rows[0].reported_cost_micros === null, 'C08_ACTUAL_COST_NULL');
    });

    // ============================================ C-09 consent withdraw pre-dispatch
    stage('C-09-queued-withdrawal-fence');
    await check('C-09', async () => {
      // Deterministic fence check: seed a queued request, withdraw consent,
      // then run the fence — cancelled + notDispatched + reservation released.
      await grantConsent(member.id, 2, true);
      const conversation = await migration.query(`
        INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
        VALUES ($1::uuid, $2::uuid, $3, $4) RETURNING id`, [organizationId, farmId, member.id, actorPseudonym(member.id)]);
      const queuedId = randomUUID();
      await migration.query(`
        INSERT INTO public.ai_requests (
          id, organization_id, farm_id, conversation_id, user_id, actor_pseudonym,
          client_request_id, request_hash, consent_revision, context_mode, prompt,
          prompt_bytes, reserved_output_tokens, reserved_input_bytes, reserved_cost_micros)
        VALUES ($7::uuid, $1::uuid, $2::uuid, $3::uuid, $4, $5,
          $6::uuid, repeat('c', 64), 2, 'none', 'queued work', 11, 256, 65536, 50)
      `, [organizationId, farmId, conversation.rows[0].id, member.id, actorPseudonym(member.id), randomUUID(), queuedId]);
      await migration.query(`
        INSERT INTO public.ai_org_counters (organization_id, reserved_output_tokens, in_flight)
        VALUES ($1::uuid, 256, 1)
        ON CONFLICT (organization_id) DO UPDATE
          SET reserved_output_tokens = ai_org_counters.reserved_output_tokens + 256,
              in_flight = ai_org_counters.in_flight + 1`, [organizationId]);
      await migration.query(`
        UPDATE public.ai_project_counters SET reserved_cost_micros = reserved_cost_micros + 50 WHERE singleton`);
      const before = await counters();
      // Withdraw consent — queued row is cancelled by the fence, never sent.
      await grantConsent(member.id, 3, false);
      const fence = await tenantCall(member, `
        SELECT public.farmly_ai_dispatch_fence($1, $2, $3::uuid, $4::uuid) AS result
      `, [member.id, actorPseudonym(member.id), queuedId, randomUUID()]);
      const fenceResult = fence.rows[0].result;
      assert(fenceResult.dispatched === false && fenceResult.status === 'cancelled', 'C09_FENCE_RESULT');
      const row = await migration.query(
        'SELECT status, usage_state, attempt_id, upstream_started_at FROM public.ai_requests WHERE id = $1::uuid', [queuedId]);
      assert(row.rows[0].status === 'cancelled' && row.rows[0].usage_state === 'notDispatched', 'C09_STATE');
      assert(row.rows[0].attempt_id === null && row.rows[0].upstream_started_at === null, 'C09_NO_MARKER');
      const after = await counters();
      assert(BigInt(after.org.reserved) === BigInt(before.org.reserved) - 256n, 'C09_TOKENS_RELEASED');
      assert(Number(after.org.in_flight) === Number(before.org.in_flight) - 1, 'C09_IN_FLIGHT');
    });

    // ============================================ C-10 purge + retry proof
    stage('C-10-content-purge-retry');
    await check('C-10', async () => {
      const body = requestBody();
      const created = await expectJson(await createRequest(owner.token, body), 202, 'C10_CREATE');
      const requestId = created.data.requestId;
      const terminal = await waitTerminal(requestId);
      assert(terminal?.status === 'completed', `C10_TERMINAL_${terminal?.status}`);
      // Force content expiry, run the TTL purge, then retry the same key.
      await migration.query(
        'UPDATE public.ai_requests SET content_expires_at = CURRENT_TIMESTAMP - INTERVAL \'1 second\' WHERE id = $1::uuid',
        [requestId]);
      const purged = await migration.query('SELECT public.farmly_ai_purge_expired_content() AS n');
      assert(Number(purged.rows[0].n) >= 1, 'C10_PURGE_COUNT');
      const retry = await expectJson(await createRequest(owner.token, body), 202, 'C10_RETRY');
      assert(retry.data.requestId === requestId, 'C10_SAME_REQUEST');
      const status = await expectJson(await getRequest(owner.token, requestId), 200, 'C10_STATUS');
      assert(status.data.contentExpired === true, 'C10_EXPIRED_FLAG');
      // Changed hash under the same key is a 409, not a new paid attempt.
      const changed = await createRequest(owner.token, { ...body, prompt: 'new intent' });
      assert(changed.status === 409, `C10_CHANGED_${changed.status}`);
      const rows = await requestRows(`client_request_id = '${body.clientRequestId}'::uuid`);
      assert(rows.rowCount === 1, 'C10_SINGLE_PROOF');
      const promptRow = await migration.query('SELECT prompt FROM public.ai_requests WHERE id = $1::uuid', [requestId]);
      assert(promptRow.rows[0].prompt === null, 'C10_PROMPT_PURGED');
    });

    // ============================================ FAI-28 serialized-prompt oracle
    // Seed PII/vet-note markers into columns the snapshot allowlist never
    // selects, then prove none serialize into the provider prompt while the
    // legitimate farm name does (spec05 §8 FAI-28).
    stage('fai28-serialized-prompt');
    await check('FAI-28', async () => {
      const zoneId = randomUUID();
      const herdId = randomUUID();
      const animalId = randomUUID();
      const templateId = randomUUID();
      await migration.query(
        `INSERT INTO public.zones (organization_id, farm_id, id, name, type, geometry)
         VALUES ($1::uuid, $2::uuid, $3::uuid, 'FAI28-ZONE-SECRET-MARKER', 'crop_plot', '{}'::jsonb)`,
        [organizationId, farmId, zoneId]);
      await migration.query(
        `INSERT INTO public.herds (organization_id, farm_id, id, species, mode)
         VALUES ($1::uuid, $2::uuid, $3::uuid, 'FAI28-HERD-MARKER', 'tracked')`,
        [organizationId, farmId, herdId]);
      await migration.query(
        `INSERT INTO public.animals (organization_id, farm_id, id, herd_id, tag, name)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid,
                 'FAI28-TAG-0901234567', 'FAI28-VET-NOTE-MARKER')`,
        [organizationId, farmId, animalId, herdId]);
      await migration.query(
        `INSERT INTO public.task_templates (organization_id, farm_id, id, title, kind, recurrence, starts_on)
         VALUES ($1::uuid, $2::uuid, $3::uuid, 'FAI28-VET-TASK-MARKER', 'general', '{}'::jsonb, CURRENT_DATE)`,
        [organizationId, farmId, templateId]);
      try {
        const body = requestBody();
        const created = await expectJson(await createRequest(owner.token, body), 202, 'F28_CREATE');
        const requestId = created.data.requestId;
        const terminal = await waitTerminal(requestId);
        assert(terminal?.status === 'completed', `F28_TERMINAL_${terminal?.status ?? 'TIMEOUT'}`);
        const captured = providerControl.captured.slice(-1)[0] ?? '';
        assert(captured.length > 0, 'F28_NO_CAPTURE');
        // Legitimate context must serialize — otherwise "absence" proves nothing.
        assert(captured.includes('AI Fixture Farm'), 'F28_CONTEXT_MISSING');
        assert(!captured.includes('FAI28-'), 'F28_FORBIDDEN_FIELD_EGRESS');
      } finally {
        await migration.query(`DELETE FROM public.animals WHERE id = $1::uuid`, [animalId]);
        await migration.query(`DELETE FROM public.herds WHERE id = $1::uuid`, [herdId]);
        await migration.query(`DELETE FROM public.zones WHERE id = $1::uuid`, [zoneId]);
        await migration.query(`DELETE FROM public.task_templates WHERE id = $1::uuid`, [templateId]);
      }
    });

    // ============================================ contract surface checks
    stage('surface-validation-privacy');
    await check('SURFACE', async () => {
      // Prompt serialization must not contain personal contact material or
      // teammate private data (spec05 §2 — serialized-byte oracle).
      const captured = providerControl.captured.join('\n');
      assert(captured.length > 0, 'SURFACE_CAPTURE_EMPTY');
      assert(!captured.includes('@farmly.test'), 'SURFACE_EMAIL_EGRESS');
      assert(!captured.includes('Bearer '), 'SURFACE_TOKEN_EGRESS');
      // Idempotency-Key must equal clientRequestId.
      const mismatch = await createRequest(owner.token, requestBody(), randomUUID());
      assert(mismatch.status === 400, `SURFACE_KEY_${mismatch.status}`);
      // Missing key is refused.
      const noKey = await fetch(`${aiBase()}/requests`, {
        method: 'POST',
        headers: httpHeaders(owner.token, { 'content-type': 'application/json' }),
        body: JSON.stringify(requestBody()),
      });
      assert(noKey.status === 400, `SURFACE_NOKEY_${noKey.status}`);
      // Conversations list is private-owner; consent state is exposed for UX.
      const conversations = await expectJson(await listConversations(owner.token), 200, 'SURFACE_CONV');
      assert(Array.isArray(conversations.data.conversations), 'SURFACE_CONV_LIST');
      assert(conversations.data.consent?.granted === true && conversations.data.consent.revision === 1, 'SURFACE_CONSENT');
      const conversationId = conversations.data.conversations[0]?.conversationId;
      assert(conversationId, 'SURFACE_CONV_ID');
      const messages = await expectJson(await listMessages(owner.token, conversationId), 200, 'SURFACE_MSG');
      assert(Array.isArray(messages.data.messages) && messages.data.messages.length >= 2, 'SURFACE_MSG_LIST');
      const memberConv = await getRequest(member.token, requestA ?? randomUUID());
      assert(memberConv.status === 404, `SURFACE_MEMBER_${memberConv.status}`);
    });

    // ============================================ C-11 consent grant route
    // PUT /ai/consent: unchanged decisions return the same revision (no
    // in-flight invalidation), real changes bump it through the definer, and
    // foreign organizations stay invisible (spec05 §2 consent lifecycle).
    stage('C-11-consent-grant');
    await check('C-11', async () => {
      const repeat = await expectJson(
        await setConsent(owner.token, { granted: true, aiSafeSummaryOptedIn: false }),
        200, 'C11_REPEAT');
      assert(repeat.data.revision === 1 && repeat.data.unchanged === true,
        `C11_UNCHANGED_${JSON.stringify(repeat.data)}`);
      const changed = await expectJson(
        await setConsent(owner.token, { granted: true, aiSafeSummaryOptedIn: true }),
        200, 'C11_CHANGE');
      assert(changed.data.revision === 2, `C11_REV_${changed.data.revision}`);
      const withdrawn = await expectJson(
        await setConsent(owner.token, { granted: false }), 200, 'C11_WITHDRAW');
      assert(withdrawn.data.granted === false && withdrawn.data.revision === 3,
        `C11_WITHDRAW_${JSON.stringify(withdrawn.data)}`);
      // Consent-required now blocks creation (revision moved past request's).
      const denied = await createRequest(owner.token, requestBody());
      assert(denied.status === 403, `C11_DENIED_${denied.status}`);
      const regrant = await expectJson(
        await setConsent(owner.token, { granted: true }), 200, 'C11_REGRANT');
      assert(regrant.data.granted === true && regrant.data.revision === 4
        && regrant.data.summaryOptedIn === false, `C11_REGRANT_${JSON.stringify(regrant.data)}`);
      // Foreign organization is invisible to consent writes too.
      const foreign = await setConsent(member.token, { granted: true }, foreignOrganizationId);
      assert(foreign.status === 404, `C11_FOREIGN_${foreign.status}`);
      // Restore the owner fixture the other cases rely on (rev 1, granted).
      await grantConsent(owner.id, 1, true);
    });
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
  } finally {
    stage('cleanup');
    try {
      if (app) await app.close();
      if (tenant) await tenant.onModuleDestroy().catch(() => {});
      await migration.query(
        `DELETE FROM public.ai_events WHERE request_id IN (SELECT id FROM public.ai_requests WHERE organization_id = ANY($1::uuid[]))`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_requests WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_messages WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_conversations WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_snapshots WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_consents WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM public.ai_org_counters WHERE organization_id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      // Organization delete cascades memberships/grants/farms — deleting
      // memberships explicitly would trip the active-owner trigger.
      await migration.query(
        `DELETE FROM public.organizations WHERE id = ANY($1::uuid[])`, [[organizationId, foreignOrganizationId]]);
      await migration.query(
        `DELETE FROM auth."user" WHERE id = ANY($1::text[])`, [users.map((user) => user.id)]);
    } catch (error) {
      cleanupError = error;
    }
    await migration.end().catch(() => {});
    await tenantPg.end().catch(() => {});
  }

  const passed = results.filter((entry) => entry.status === 'passed').length;
  const failed = results.filter((entry) => entry.status === 'failed');
  const summary = {
    suite: 'ai-protocol',
    stage: operationStage ?? currentStage,
    passed,
    failed: failed.length,
    cases: results,
  };
  if (operationError) summary.operationError = { stage: operationStage, message: operationError.message };
  if (cleanupError) summary.cleanupError = cleanupError.message;
  console.log(JSON.stringify(summary, null, 2));
  if (operationError || failed.length > 0 || cleanupError) process.exit(1);
}

main();
