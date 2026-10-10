import 'reflect-metadata';
import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExpressAdapter } from '@nestjs/platform-express';
import { NestFactory } from '@nestjs/core';
import { createHash, randomUUID } from 'node:crypto';
import { Client } from 'pg';

// P10 notifications + privacy suite — phase-10 N-01..05 / P-01..05.
// Notification dedup/reminder fan-out, installation-bound device bindings
// and audited privacy requests run the real Nest surface + definers.

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const authDatabaseUrl = process.env.DATABASE_URL_AUTH;

const SAFE_CODE = /^[A-Z0-9_]{1,140}$/;
const ACTOR_DOMAIN = 'farmly-operation-actor:v1:';

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
  return `postgresql://farmly_tenant_app:${encodeURIComponent(tenantPassword)}@postgres:5432/${expectedDatabaseName}?application_name=${encodeURIComponent(applicationName)}`;
}

function withApplicationName(connectionString, applicationName) {
  const url = new URL(connectionString);
  url.searchParams.set('application_name', applicationName);
  return url.toString();
}

function stage(name) { currentStage = name; }

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
    id: `pn-${label}-${suffix}`,
    email: `${label}-${suffix}@farmly.test`,
    token: `pn-${label}-${suffix}`,
    name: `PN ${label}`,
    sessionId: randomUUID(),
  };
}

function sessionFor(user) {
  return {
    user: { id: user.id, email: user.email, name: user.name, emailVerified: true },
    session: { id: user.sessionId, expiresAt: new Date(Date.now() + 60_000) },
  };
}

const httpHeaders = (token, extra = {}) => ({ authorization: `Bearer ${token}`, ...extra });

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

async function main() {
  assert(migrationUrl, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assertTarget(migrationUrl, 'farmly_migration');

  const suffix = randomUUID().replaceAll('-', '');
  const owner = fixtureUser(suffix, 'owner');
  const member = fixtureUser(suffix, 'member');
  const foreign = fixtureUser(suffix, 'foreign');
  const users = [owner, member, foreign];
  const userByToken = new Map(users.map((user) => [user.token, user]));

  const organizationId = randomUUID();
  const farmId = randomUUID();
  const membershipIds = { owner: randomUUID(), member: randomUUID() };

  const migration = new Client({ connectionString: withApplicationName(migrationUrl, `farmly-pn-migration-${suffix}`) });
  let app;
  let tenant;
  let operationError;
  let operationStage;
  let cleanupError;

  const setup = async () => {
    stage('setup-connect-and-check-schema');
    await migration.connect();
    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'DATABASE_IDENTITY_INVALID');
    const schema = await migration.query(`
      SELECT to_regclass('public.notifications') IS NOT NULL AS notifications,
             to_regclass('public.device_registrations') IS NOT NULL AS devices,
             to_regclass('public.privacy_requests') IS NOT NULL AS requests,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_notify_recipient') AS notify_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_generate_task_reminders') AS remind_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_mark_notification_read') AS read_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_mutate_device_registration') AS device_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_create_privacy_request') AS privacy_fn,
             EXISTS (SELECT 1 FROM pg_catalog.pg_proc WHERE proname = 'farmly_ai_set_consent') AS consent_fn
    `);
    assert(Object.values(schema.rows[0]).every(Boolean), 'PN_SCHEMA_NOT_READY');

    stage('setup-seed-actors-organizations-farm');
    const values = [];
    const rows = users.map((user, index) => {
      const offset = index * 4;
      values.push(user.id, user.name, user.email, new Date());
      return `($${offset + 1}, $${offset + 2}, $${offset + 3}, TRUE, $${offset + 4})`;
    });
    await migration.query(`INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt") VALUES ${rows.join(', ')}`, values);
    await migration.query(`
      INSERT INTO public.organizations (id, name, continuity_epoch)
      VALUES ($1::uuid, 'PN fixture org', 1)
    `, [organizationId]);
    await migration.query(`
      INSERT INTO public.organization_memberships (id, organization_id, user_id, role, status)
      VALUES ($1::uuid, $2::uuid, $3, 'owner', 'active'),
             ($4::uuid, $2::uuid, $5, 'member', 'active')
    `, [membershipIds.owner, organizationId, owner.id, membershipIds.member, member.id]);
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone, status, version, created_at, updated_at)
      VALUES ($1::uuid, $2::uuid, 'PN Fixture Farm', 'Asia/Ho_Chi_Minh', 'active', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `, [farmId, organizationId]);
    // Both members hold farm grants so reminder fan-out reaches each.
    await migration.query(`
      INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
      VALUES ($1::uuid, $2::uuid, $3::uuid, 'manager'),
             ($1::uuid, $4::uuid, $3::uuid, 'viewer')
    `, [organizationId, membershipIds.owner, farmId, membershipIds.member]);
    // One AI consent row for the withdraw path.
    await migration.query(`
      INSERT INTO public.ai_consents (organization_id, user_id, actor_pseudonym, revision, granted,
                                      ai_safe_summary_opted_in, granted_at, updated_at)
      VALUES ($1::uuid, $2, $3, 1, TRUE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `, [organizationId, owner.id, actorPseudonym(owner.id)]);
    // A due task occurrence for reminder generation.
    const templateId = randomUUID();
    const occurrenceId = randomUUID();
    await migration.query(`
      INSERT INTO public.task_templates (organization_id, farm_id, id, title, kind, recurrence, starts_on)
      VALUES ($1::uuid, $2::uuid, $3::uuid, 'Cho bò ăn sáng', 'feeding', '{}'::jsonb, CURRENT_DATE - 7)
    `, [organizationId, farmId, templateId]);
    await migration.query(`
      INSERT INTO public.task_occurrences (organization_id, farm_id, id, template_id, occurrence_date, slot, status, due_at)
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, CURRENT_DATE, 'sang', 'open', CURRENT_TIMESTAMP + INTERVAL '2 hours')
    `, [organizationId, farmId, occurrenceId, templateId]);
    return { occurrenceId };
  };

  const buildApp = async (controllers, providers) => {
    class PnHttpTestModule {}
    Module({ controllers, providers })(PnHttpTestModule);
    const instance = await NestFactory.create(PnHttpTestModule, new ExpressAdapter(), { logger: false });
    const filterModule = await import(new URL('../../dist/common/farmly-http-exception.filter.js', import.meta.url));
    instance.useGlobalFilters(new filterModule.FarmlyHttpExceptionFilter());
    await instance.listen(0, '127.0.0.1');
    return instance;
  };

  let origin;
  const me = (path) => `${origin}/v1/me${path}`;
  let fixture = {};

  try {
    fixture = await setup();

    stage('setup-load-http-surface');
    const [
      { TenantDatabaseService },
      { FarmlyNotificationsService },
      { FarmlyNotificationsController },
      { FarmlyPrivacyService },
      { FarmlyPrivacyController },
      { VerifiedSessionGuard },
      { FARMLY_AUTH },
      { API_ENVIRONMENT },
    ] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/notifications/notifications.service.js', import.meta.url)),
      import(new URL('../../dist/notifications/notifications.controller.js', import.meta.url)),
      import(new URL('../../dist/privacy/privacy.service.js', import.meta.url)),
      import(new URL('../../dist/privacy/privacy.controller.js', import.meta.url)),
      import(new URL('../../dist/auth/verified-session.guard.js', import.meta.url)),
      import(new URL('../../dist/auth/auth.module.js', import.meta.url)),
      import(new URL('../../dist/config/environment.js', import.meta.url)),
    ]);

    const apiEnvironment = {
      nodeEnv: 'test', port: 0,
      databaseUrlTenant: tenantConnectionString(`farmly-pn-http-${suffix}`),
      databaseUrlAuth: authDatabaseUrl ?? 'postgresql://farmly_auth_app:unused@postgres:5432/farmly_test_261005',
      betterAuthSecret: process.env.BETTER_AUTH_SECRET ?? 'farmly-pn-test-secret-0000000000000000',
      betterAuthUrl: 'http://127.0.0.1:3000',
      smtpHost: process.env.SMTP_HOST ?? 'mailpit', smtpPort: 1025,
      smtpSecure: false, smtpRequireTls: false,
      smtpFrom: 'Farmly <no-reply@farmly.test>',
      cursorSigningKey: process.env.CURSOR_SIGNING_KEY ?? 'pn-suite-key',
      weatherEnabled: false, weatherFreshTtlSeconds: 3600,
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

    app = await buildApp(
      [FarmlyNotificationsController, FarmlyPrivacyController],
      [
        VerifiedSessionGuard,
        { provide: FARMLY_AUTH, useValue: auth },
        { provide: API_ENVIRONMENT, useValue: apiEnvironment },
        { provide: ConfigService, useValue: configStub },
        { provide: TenantDatabaseService, useValue: tenant },
        { provide: FarmlyNotificationsService, useValue: new FarmlyNotificationsService(tenant) },
        { provide: FarmlyPrivacyService, useValue: new FarmlyPrivacyService(tenant) },
      ],
    );
    await tenant.onModuleInit().catch(() => {});
    const address = app.getHttpServer().address();
    assert(address && typeof address !== 'string', 'PN_HTTP_LISTENER_UNAVAILABLE');
    origin = `http://127.0.0.1:${address.port}`;

    const listNotifications = (token, query = '') =>
      fetch(`${me(`/notifications${query}`)}`, { headers: httpHeaders(token) });
    const markRead = (token, id) =>
      fetch(me(`/notifications/${id}/read`), { method: 'POST', headers: httpHeaders(token) });
    const deviceOp = (token, body) =>
      fetch(me('/device-registrations'), {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify(body),
      });
    const privacyOp = (token, body) =>
      fetch(me('/privacy-requests'), {
        method: 'POST',
        headers: httpHeaders(token, { 'content-type': 'application/json' }),
        body: JSON.stringify(body),
      });

    // ============================================ N-01 reminder dedup
    stage('n01-reminder-dedup');
    await check('N-01', async () => {
      const generated = await migration.query(
        `SELECT public.farmly_generate_task_reminders(INTERVAL '24 hours') AS count`);
      assert(Number(generated.rows[0].count) >= 2, `N01_COUNT_${generated.rows[0].count}`);
      const again = await migration.query(
        `SELECT public.farmly_generate_task_reminders(INTERVAL '24 hours') AS count`);
      assert(Number(again.rows[0].count) === 0, `N01_REDEDUP_${again.rows[0].count}`);
      const rows = await migration.query(
        `SELECT user_id, dedup_key FROM public.notifications
          WHERE source_ref = $1 ORDER BY user_id`,
        [`task_occurrence:${fixture.occurrenceId}`]);
      assert(rows.rowCount === 2, `N01_RECIPIENTS_${rows.rowCount}`);
      assert(new Set(rows.rows.map((r) => r.user_id)).size === 2, 'N01_ONE_PER_RECIPIENT');
    });

    // ============================================ N-02 owner-scoped list
    stage('n02-owner-scoped-list');
    await check('N-02', async () => {
      const own = await expectJson(await listNotifications(owner.token), 200, 'N02_LIST');
      assert(Array.isArray(own.data.items) && own.data.items.length >= 1, 'N02_EMPTY');
      assert(own.data.items.every((n) => typeof n.id === 'string' && typeof n.title === 'string'), 'N02_SHAPE');
      const memberOwn = await expectJson(await listNotifications(member.token), 200, 'N02_MEMBER');
      const memberIds = new Set(memberOwn.data.items.map((n) => n.id));
      for (const n of own.data.items) {
        const ownerRow = await migration.query(
          `SELECT user_id FROM public.notifications WHERE id = $1::uuid`, [n.id]);
        if (ownerRow.rows[0]?.user_id === owner.id) {
          assert(!memberIds.has(n.id), 'N02_CROSS_OWNER_LEAK');
        }
      }
      const foreignView = await expectJson(await listNotifications(foreign.token), 200, 'N02_FOREIGN');
      assert(foreignView.data.items.length === 0, 'N02_FOREIGN_NOT_EMPTY');
      const paged = await expectJson(await listNotifications(owner.token, '?limit=1'), 200, 'N02_PAGE');
      assert(paged.data.items.length <= 1, 'N02_LIMIT');
      assert(paged.data.page && 'nextCursor' in paged.data.page, 'N02_PAGE_SHAPE');
    });

    // ============================================ N-03 mark read
    stage('n03-mark-read');
    await check('N-03', async () => {
      const own = await expectJson(await listNotifications(owner.token), 200, 'N03_LIST');
      const target = own.data.items.find((n) => !n.readAt);
      assert(target, 'N03_NO_UNREAD');
      const marked = await expectJson(await markRead(owner.token, target.id), 200, 'N03_MARK');
      assert(marked.data.readAt, 'N03_NO_READAT');
      const again = await expectJson(await markRead(owner.token, target.id), 200, 'N03_REMARK');
      assert(again.data.readAt === marked.data.readAt, 'N03_READAT_CHANGED');
      const foreignAttempt = await markRead(foreign.token, target.id);
      assert(foreignAttempt.status === 404, `N03_FOREIGN_${foreignAttempt.status}`);
      const bogus = await markRead(owner.token, randomUUID());
      assert(bogus.status === 404, `N03_UNKNOWN_${bogus.status}`);
    });

    // ============================================ N-04 installation rebind
    stage('n04-installation-rebind');
    await check('N-04', async () => {
      const deviceId = `device-${suffix}`;
      const ownerOp = { operationId: randomUUID(), action: 'register', deviceId, pushToken: 'tok-owner-secret-aaaa' };
      const first = await expectJson(await deviceOp(owner.token, ownerOp), 200, 'N04_REG');
      assert(first.data.status === 'registered', 'N04_NOT_REGISTERED');
      const memberOp = { operationId: randomUUID(), action: 'register', deviceId, pushToken: 'tok-member-bbbb' };
      const second = await expectJson(await deviceOp(member.token, memberOp), 200, 'N04_REG2');
      assert(second.data.status === 'registered', 'N04_MEMBER_NOT_REGISTERED');
      const rows = await migration.query(
        `SELECT user_id, status FROM public.device_registrations WHERE device_id = $1`, [deviceId]);
      const ownerRow = rows.rows.find((r) => r.user_id === owner.id);
      const memberRow = rows.rows.find((r) => r.user_id === member.id);
      assert(ownerRow?.status === 'revoked', 'N04_OLD_OWNER_STILL_ACTIVE');
      assert(memberRow?.status === 'registered', 'N04_NEW_OWNER_NOT_ACTIVE');
      const cleared = await migration.query(
        `SELECT push_token FROM public.device_registrations WHERE user_id = $1 AND device_id = $2`,
        [owner.id, deviceId]);
      assert(cleared.rows[0]?.push_token === null, 'N04_TOKEN_NOT_CLEARED');
    });

    // ============================================ N-05 idempotency + revoke
    stage('n05-device-idempotency-revoke');
    await check('N-05', async () => {
      const deviceId = `device2-${suffix}`;
      const opId = randomUUID();
      const op = { operationId: opId, action: 'register', deviceId, pushToken: 'tok-cccc' };
      const first = await expectJson(await deviceOp(owner.token, op), 200, 'N05_REG');
      const replay = await expectJson(await deviceOp(owner.token, op), 200, 'N05_REPLAY');
      assert(replay.data.status === 'registered', 'N05_REPLAY_STATUS');
      // Same opId on a different device = misuse → OPERATION_ID_REUSED (409).
      const misused = await deviceOp(owner.token, {
        operationId: opId, action: 'register', deviceId: `other-${suffix}`, pushToken: 'tok-dddd' });
      assert(misused.status === 409, `N05_MISUSE_${misused.status}`);
      // Register without a token is rejected at the boundary.
      const noToken = await deviceOp(owner.token, {
        operationId: randomUUID(), action: 'register', deviceId: `bare-${suffix}` });
      assert(noToken.status === 400, `N05_NOTOKEN_${noToken.status}`);
      const revoked = await expectJson(await deviceOp(owner.token, {
        operationId: randomUUID(), action: 'revoke', deviceId }), 200, 'N05_REVOKE');
      assert(revoked.data.status === 'revoked', 'N05_NOT_REVOKED');
    });

    // ============================================ P-01 export content
    stage('p01-export-content');
    await check('P-01', async () => {
      const exportOp = { operationId: randomUUID(), action: 'export' };
      const result = await expectJson(await privacyOp(owner.token, exportOp), 202, 'P01_EXPORT');
      assert(result.data.status === 'completed', `P01_STATUS_${result.data.status}`);
      const payload = result.data.payload;
      assert(payload && typeof payload === 'object', 'P01_NO_PAYLOAD');
      assert(Array.isArray(payload.notifications) && payload.notifications.length >= 1, 'P01_NO_NOTIFICATIONS');
      assert(Array.isArray(payload.memberships) && payload.memberships.length >= 1, 'P01_NO_MEMBERSHIPS');
      const serialized = JSON.stringify(payload);
      assert(!serialized.includes('tok-'), 'P01_TOKEN_EGRESS');
      assert(!serialized.includes(member.id), 'P01_FOREIGN_USER');
      assert(!serialized.includes('@farmly.test'), 'P01_EMAIL_EGRESS');
      // Replay returns the same audited request — no second export.
      const replay = await expectJson(await privacyOp(owner.token, exportOp), 202, 'P01_REPLAY');
      assert(replay.data.requestId === result.data.requestId, 'P01_REPLAY_DIFFERENT');
    });

    // ============================================ P-02 withdraw-ai-consent
    stage('p02-withdraw-ai-consent');
    await check('P-02', async () => {
      const op = { operationId: randomUUID(), action: 'withdraw-ai-consent' };
      const result = await expectJson(await privacyOp(owner.token, op), 202, 'P02_WITHDRAW');
      assert(result.data.status === 'completed', `P02_STATUS_${result.data.status}`);
      const consent = await migration.query(
        `SELECT granted, revision, withdrawn_at FROM public.ai_consents
          WHERE organization_id = $1::uuid AND user_id = $2`,
        [organizationId, owner.id]);
      assert(consent.rows[0]?.granted === false, 'P02_STILL_GRANTED');
      assert(consent.rows[0]?.revision >= 2, `P02_REVISION_${consent.rows[0]?.revision}`);
      assert(consent.rows[0]?.withdrawn_at !== null, 'P02_NO_WITHDRAWN_AT');
      const replay = await expectJson(await privacyOp(owner.token, op), 202, 'P02_REPLAY');
      assert(replay.data.requestId === result.data.requestId, 'P02_REPLAY_DIFFERENT');
    });

    // ============================================ P-03 delete-history
    stage('p03-delete-history');
    await check('P-03', async () => {
      const conversationId = randomUUID();
      const requestId = randomUUID();
      await migration.query(
        `INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
         VALUES ($1::uuid, $2::uuid, $3, $4)`, [organizationId, farmId, owner.id, actorPseudonym(owner.id)]);
      const convRow = await migration.query(
        `SELECT id FROM public.ai_conversations WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`, [owner.id]);
      const convId = convRow.rows[0]?.id;
      await migration.query(
        `INSERT INTO public.ai_requests (
          id, organization_id, farm_id, user_id, actor_pseudonym, conversation_id,
          client_request_id, request_hash, consent_revision, context_mode, prompt,
          prompt_bytes, reserved_output_tokens, reserved_input_bytes, reserved_cost_micros,
          status, usage_state, terminal_at, finish_reason)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::uuid,
                 $7::uuid, repeat('a',64)::CHAR(64), 1, 'authorized-summary',
                 'P03-SECRET-PROMPT-MARKER', 24, 256, 1024, 3500, 'completed', 'reported', CURRENT_TIMESTAMP, 'stop')`,
        [requestId, organizationId, farmId, owner.id, actorPseudonym(owner.id), convId, randomUUID()]);
      await migration.query(
        `INSERT INTO public.ai_messages (conversation_id, organization_id, farm_id, user_id, actor_pseudonym, request_id, role, body)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::uuid, 'user', 'P03-SECRET-MESSAGE-MARKER'),
                ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::uuid, 'assistant', 'P03-SECRET-ANSWER-MARKER')`,
        [convId, organizationId, farmId, owner.id, actorPseudonym(owner.id), requestId]);
      const result = await expectJson(await privacyOp(owner.token, {
        operationId: randomUUID(), action: 'delete-history' }), 202, 'P03_DELETE');
      assert(result.data.status === 'completed', `P03_STATUS_${result.data.status}`);
      const residue = await migration.query(
        `SELECT (SELECT count(*) FROM public.ai_messages
                  WHERE conversation_id = $1::uuid AND body NOT LIKE '[deleted]') AS messages,
                (SELECT count(*) FROM public.ai_requests
                  WHERE user_id = $2 AND prompt IS NOT NULL) AS prompts,
                (SELECT status::TEXT FROM public.ai_conversations WHERE id = $1::uuid) AS conv`,
        [convId, owner.id]);
      assert(Number(residue.rows[0].messages) === 0, 'P03_MESSAGES_REMAIN');
      assert(Number(residue.rows[0].prompts) === 0, 'P03_PROMPTS_REMAIN');
      assert(residue.rows[0].conv === 'deleted', `P03_CONV_${residue.rows[0].conv}`);
    });

    // ============================================ P-04 operation reuse
    stage('p04-operation-reuse');
    await check('P-04', async () => {
      const opId = randomUUID();
      await expectJson(await privacyOp(owner.token, {
        operationId: opId, action: 'export' }), 202, 'P04_FIRST');
      const reused = await privacyOp(owner.token, {
        operationId: opId, action: 'delete-history' });
      assert(reused.status === 409, `P04_REUSED_${reused.status}`);
      const body = await readBody(reused);
      assert(body?.error?.code === 'OPERATION_ID_REUSED', `P04_CODE_${body?.error?.code}`);
    });

    // ============================================ P-05 boundary
    stage('p05-auth-boundary');
    await check('P-05', async () => {
      const anon = await fetch(me('/notifications'));
      assert(anon.status === 401, `P05_ANON_${anon.status}`);
      const anonPrivacy = await fetch(me('/privacy-requests'), {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ operationId: randomUUID(), action: 'export' }) });
      assert(anonPrivacy.status === 401, `P05_ANON_PRIV_${anonPrivacy.status}`);
      const badAction = await privacyOp(owner.token, {
        operationId: randomUUID(), action: 'wipe-everything' });
      assert(badAction.status === 400, `P05_ACTION_${badAction.status}`);
    });
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
  } finally {
    stage('cleanup');
    try {
      if (app) await app.close();
      if (tenant) await tenant.onModuleDestroy().catch(() => {});
      await migration.query(`DELETE FROM public.privacy_requests WHERE user_id = ANY($1::text[])`, [[owner.id, member.id, foreign.id]]);
      await migration.query(`DELETE FROM public.device_registrations WHERE user_id = ANY($1::text[])`, [[owner.id, member.id, foreign.id]]);
      // Org delete cascades memberships/farms/grants/ai_*/tasks/notifications —
      // deleting memberships first would trip the active-owner guard.
      await migration.query(`DELETE FROM public.organizations WHERE id = $1::uuid`, [organizationId]);
      await migration.query(`DELETE FROM auth."user" WHERE id = ANY($1::text[])`, [[owner.id, member.id, foreign.id]]);
    } catch (error) {
      cleanupError = error;
    } finally {
      await migration.end().catch(() => {});
    }
  }

  const failed = results.filter((result) => result.status !== 'passed');
  console.log(JSON.stringify({
    suite: 'privacy-notifications',
    stage: operationStage ?? currentStage,
    passed: results.length - failed.length,
    failed: failed.length,
    cases: results,
    ...(operationError ? { operationError: String(operationError).slice(0, 300) } : {}),
    ...(cleanupError ? { cleanupError: String(cleanupError).slice(0, 300) } : {}),
  }, null, 2));
  process.exit(failed.length === 0 && !operationError ? 0 : 1);
}

await main();
