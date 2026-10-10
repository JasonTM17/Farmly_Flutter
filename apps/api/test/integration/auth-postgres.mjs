import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { NestFactory } from '@nestjs/core';
import { Pool } from 'pg';

const apiOrigin = process.env.BETTER_AUTH_URL ?? 'http://127.0.0.1:3000';
const mailpitOrigin = 'http://mailpit:8025';
const authDatabaseUrl = process.env.DATABASE_URL_AUTH;
const tenantDatabaseUrl = process.env.DATABASE_URL_TENANT;
const marker = `farmly-e2e-${randomUUID()}`;
const email = `${marker}@farmly.test`;
const untrustedEmail = `${marker}-untrusted@farmly.test`;
const initialPassword = `Farmly-${randomUUID()}aA1!`;
const resetPassword = `Farmly-${randomUUID()}bB2!`;
const clientIps = new Set();
const verificationDigests = new Set();
const resetVerificationIdentifiers = new Set();
const messageIds = new Set();
const missingEmail = `${marker}-missing@farmly.test`;
const sensitiveAuthValues = new Set([email, untrustedEmail, missingEmail, initialPassword, resetPassword]);
const capturedRuntimeLogs = [];
const cleanupFailures = [];
let captureRuntimeLogs = false;
let mailDeliveryAttempted = false;

function installRuntimeLogCapture(stream) {
  const originalWrite = stream.write;
  const boundWrite = originalWrite.bind(stream);
  stream.write = function write(chunk, encoding, callback) {
    if (!captureRuntimeLogs) return boundWrite(chunk, encoding, callback);
    capturedRuntimeLogs.push(Buffer.isBuffer(chunk) ? chunk.toString('utf8') : String(chunk));
    const completion = typeof encoding === 'function' ? encoding : callback;
    if (typeof completion === 'function') completion();
    return true;
  };
  return () => { stream.write = originalWrite; };
}

const restoreRuntimeLogCapture = [installRuntimeLogCapture(process.stdout), installRuntimeLogCapture(process.stderr)];

function ensure(condition, code) {
  if (!condition) throw new Error(`FARMLY_AUTH_POSTGRES_${code}`);
}

function nextSyntheticClientIp() {
  let ip;
  do {
    const octets = randomBytes(4);
    ip = `192.0.2.${1 + (octets[0] % 254)}`;
  } while (clientIps.has(ip));
  clientIps.add(ip);
  return ip;
}

async function request(path, { method = 'GET', body, headers = {}, redirect = 'follow', clientIp = nextSyntheticClientIp() } = {}) {
  const response = await fetch(new URL(path, apiOrigin), {
    method,
    redirect,
    headers: {
      origin: apiOrigin,
      'x-forwarded-for': clientIp,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...headers,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return response;
}

async function responseJson(response) {
  try {
    return await response.json();
  } catch {
    ensure(false, 'RESPONSE_JSON_INVALID');
  }
}

async function safeAuthErrorCode(response) {
  const payload = await response.clone().json().catch(() => null);
  const candidate = payload && typeof payload === 'object'
    ? (typeof payload.code === 'string' ? payload.code : payload.error?.code)
    : null;
  return typeof candidate === 'string' && /^[A-Z][A-Z0-9_]{0,79}$/.test(candidate)
    ? candidate
    : 'UNAVAILABLE';
}

function recipientAddresses(message) {
  const to = message.To ?? message.to ?? [];
  return (Array.isArray(to) ? to : [to]).map((recipient) => {
    if (typeof recipient === 'string') return recipient.toLowerCase();
    return String(recipient?.Address ?? recipient?.address ?? '').toLowerCase();
  });
}

async function listMailpitMessages() {
  const response = await fetch(`${mailpitOrigin}/api/v1/messages?limit=200`);
  ensure(response.ok, 'MAILPIT_LIST_FAILED');
  const payload = await responseJson(response);
  ensure(Array.isArray(payload.messages), 'MAILPIT_LIST_SHAPE_INVALID');
  return payload.messages;
}

async function waitForMail(recipient, subjectPart) {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    const messages = await listMailpitMessages();
    const match = messages.find((message) => {
      const subject = String(message.Subject ?? message.subject ?? '').toLowerCase();
      return recipientAddresses(message).includes(recipient.toLowerCase()) && subject.includes(subjectPart.toLowerCase());
    });
    if (match) {
      const id = String(match.ID ?? match.Id ?? match.id ?? '');
      ensure(id.length > 0, 'MAILPIT_MESSAGE_ID_MISSING');
      messageIds.add(id);
      return { id };
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  ensure(false, 'MAILPIT_DELIVERY_TIMEOUT');
}

function decodeHtml(value) {
  return value
    .replace(/&amp;/gi, '&')
    .replace(/&#x2f;/gi, '/')
    .replace(/&#x3d;/gi, '=')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
}

async function messageUrls(messageId) {
  const response = await fetch(`${mailpitOrigin}/api/v1/message/${encodeURIComponent(messageId)}`);
  ensure(response.ok, 'MAILPIT_MESSAGE_READ_FAILED');
  const payload = await responseJson(response);
  const message = payload.Message ?? payload.message ?? payload;
  const content = decodeHtml(`${message.Text ?? message.text ?? ''}\n${message.HTML ?? message.html ?? ''}`);
  const candidates = [...content.matchAll(/https?:\/\/[^\s<>"']+/gi)].map((match) => match[0].replace(/[),.;\]]+$/u, ''));
  return candidates.map((value) => {
    try {
      return new URL(value);
    } catch {
      return null;
    }
  }).filter((value) => value !== null);
}

async function verificationUrl(messageId) {
  const candidates = await messageUrls(messageId);
  const result = candidates.find((url) => url.origin === apiOrigin && url.pathname.toLowerCase().includes('/verify-email') && url.searchParams.has('token'));
  ensure(result, 'VERIFICATION_LINK_MISSING');
  const token = result.searchParams.get('token');
  ensure(token, 'VERIFICATION_TOKEN_MISSING');
  sensitiveAuthValues.add(token);
  sensitiveAuthValues.add(result.toString());
  verificationDigests.add(createHash('sha256').update(token).digest('hex'));
  return result;
}

function resetTokenFromUrl(url) {
  const queryToken = url.searchParams.get('token');
  if (queryToken) return queryToken;
  const pieces = url.pathname.split('/').filter(Boolean);
  const index = pieces.findIndex((piece) => piece.toLowerCase() === 'reset-password');
  const routeToken = index >= 0 ? pieces[index + 1] : undefined;
  return routeToken ? decodeURIComponent(routeToken) : null;
}

async function resetToken(messageId) {
  const candidates = await messageUrls(messageId);
  const result = candidates.find((url) => url.origin === apiOrigin && url.pathname.toLowerCase().includes('reset-password'));
  ensure(result, 'RESET_LINK_MISSING');
  const token = resetTokenFromUrl(result);
  ensure(token, 'RESET_TOKEN_MISSING');
  sensitiveAuthValues.add(token);
  sensitiveAuthValues.add(result.toString());
  resetVerificationIdentifiers.add(`reset-password:${token}`);
  return token;
}

async function deleteMailpitMessages(recipients) {
  if (!mailDeliveryAttempted && messageIds.size === 0) return;
  const ownedRecipients = new Set(recipients.map((recipient) => recipient.toLowerCase()));
  if (ownedRecipients.size > 0) {
    const messages = await listMailpitMessages();
    for (const message of messages) {
      if (!recipientAddresses(message).some((address) => ownedRecipients.has(address))) continue;
      const id = String(message.ID ?? message.Id ?? message.id ?? '');
      if (id) {
        messageIds.add(id);
        for (const url of await messageUrls(id)) {
          const token = url.pathname.toLowerCase().includes('/verify-email') ? url.searchParams.get('token') : null;
          if (token) {
            sensitiveAuthValues.add(token);
            sensitiveAuthValues.add(url.toString());
            verificationDigests.add(createHash('sha256').update(token).digest('hex'));
          }
          const resetTokenValue = url.pathname.toLowerCase().includes('reset-password') ? resetTokenFromUrl(url) : null;
          if (resetTokenValue) {
            sensitiveAuthValues.add(resetTokenValue);
            sensitiveAuthValues.add(url.toString());
            resetVerificationIdentifiers.add(`reset-password:${resetTokenValue}`);
          }
        }
      }
    }
  }
  if (messageIds.size === 0) return;
  const response = await fetch(`${mailpitOrigin}/api/v1/messages`, {
    method: 'DELETE',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ IDs: [...messageIds] }),
  });
  ensure(response.ok, 'MAILPIT_MESSAGE_CLEANUP_FAILED');
}

async function clearOwnRateLimitRows(pool) {
  if (clientIps.size === 0) return;
  const keys = [...clientIps].map((ip) => `${ip}|%`);
  await pool.query('DELETE FROM auth.rate_limit WHERE key LIKE ANY($1::text[])', [keys]);
}

async function cleanupDatabase(pool, recipients) {
  if (verificationDigests.size > 0) {
    await pool.query('DELETE FROM auth.verification_token_digest WHERE digest = ANY($1::char(64)[])', [[...verificationDigests]]);
  }
  if (resetVerificationIdentifiers.size > 0) {
    await pool.query('DELETE FROM auth.verification WHERE identifier = ANY($1::text[])', [[...resetVerificationIdentifiers]]);
  }
  for (const recipient of recipients) {
    const user = await pool.query('SELECT id FROM auth."user" WHERE email = $1', [recipient]);
    if (user.rows.length > 0) {
      const userId = String(user.rows[0].id);
      await pool.query("DELETE FROM auth.verification WHERE value = $1 AND identifier LIKE 'reset-password:%'", [userId]);
      await pool.query('DELETE FROM auth."user" WHERE id = $1', [userId]);
    }
  }
  await clearOwnRateLimitRows(pool);
}

async function proveRateLimit() {
  // The test-only IP keeps this real database-backed limit isolated from prior local runs.
  const ip = nextSyntheticClientIp();
  const statuses = [];
  for (let index = 0; index < 4; index += 1) {
    const response = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email: missingEmail, password: initialPassword },
      clientIp: ip,
    });
    statuses.push(response.status);
    await response.arrayBuffer();
  }
  ensure(statuses.slice(0, 3).every((status) => status !== 429) && statuses[3] === 429, 'RATE_LIMIT_NOT_ENFORCED');
}

async function run() {
  ensure(authDatabaseUrl, 'AUTH_DATABASE_URL_MISSING');
  ensure(tenantDatabaseUrl, 'TENANT_DATABASE_URL_MISSING');
  ensure(new URL(authDatabaseUrl).hostname === 'postgres' && new URL(authDatabaseUrl).pathname === '/farmly_test_261005' && new URL(authDatabaseUrl).username === 'farmly_auth_app', 'AUTH_DATABASE_SCOPE_INVALID');
  ensure(new URL(tenantDatabaseUrl).hostname === 'postgres' && new URL(tenantDatabaseUrl).pathname === '/farmly_test_261005' && new URL(tenantDatabaseUrl).username === 'farmly_tenant_app', 'TENANT_DATABASE_SCOPE_INVALID');
  ensure(new URL(apiOrigin).hostname === '127.0.0.1' && new URL(apiOrigin).port === '3000', 'API_BIND_SCOPE_INVALID');

  // Keep migration authority and raw test passwords out of the API process.
  delete process.env.MIGRATION_DATABASE_URL;
  delete process.env.FARMLY_TEST_MIGRATION_PASSWORD;
  delete process.env.FARMLY_TEST_AUTH_PASSWORD;
  delete process.env.FARMLY_TEST_TENANT_PASSWORD;

  const [{ AppModule }, { FARMLY_AUTH }, { mountFarmlyAuthHandler }, { FarmlyHttpExceptionFilter }] = await Promise.all([
    import('../../dist/app.module.js'),
    import('../../dist/auth/auth.module.js'),
    import('../../dist/auth/mount-auth-handler.js'),
    import('../../dist/common/farmly-http-exception.filter.js'),
  ]);

  const pool = new Pool({ connectionString: authDatabaseUrl, max: 2 });
  let app;
  try {
    const identity = await pool.query('SELECT current_user AS role, current_database() AS database');
    ensure(identity.rows[0]?.role === 'farmly_auth_app' && identity.rows[0]?.database === 'farmly_test_261005', 'DATABASE_IDENTITY_INVALID');

    captureRuntimeLogs = true;
    app = await NestFactory.create(AppModule);
    const auth = app.get(FARMLY_AUTH);
    mountFarmlyAuthHandler(app, auth);
    app.useGlobalFilters(new FarmlyHttpExceptionFilter());
    await app.listen(3000, '127.0.0.1');

    mailDeliveryAttempted = true;
    const untrustedSignUp = await request('/api/auth/sign-up/email', {
      method: 'POST',
      body: { name: 'Untrusted User', email: untrustedEmail, password: initialPassword },
      headers: { origin: 'https://invalid.example' },
    });
    ensure(untrustedSignUp.status >= 400, 'UNTRUSTED_ORIGIN_ACCEPTED');
    await untrustedSignUp.arrayBuffer();
    const untrustedUser = await pool.query('SELECT 1 FROM auth."user" WHERE email = $1', [untrustedEmail]);
    ensure(untrustedUser.rowCount === 0, 'UNTRUSTED_ORIGIN_CREATED_ACCOUNT');

    const signUp = await request('/api/auth/sign-up/email', {
      method: 'POST',
      body: { name: 'Farmly E2E Owner', email, password: initialPassword },
    });
    if (signUp.status !== 200) {
      ensure(false, `SIGNUP_FAILED_STATUS_${signUp.status}_CODE_${await safeAuthErrorCode(signUp)}`);
    }
    const signUpPayload = await responseJson(signUp);
    ensure(signUpPayload.token === null && !signUp.headers.has('set-auth-token'), 'SIGNUP_ISSUED_SESSION');
    const verifyMail = await waitForMail(email, 'verify');
    const link = await verificationUrl(verifyMail.id);

    const signedToken = link.searchParams.get('token');
    ensure(signedToken, 'VERIFICATION_TOKEN_MISSING');
    const invalidVerificationUrl = new URL(link);
    invalidVerificationUrl.searchParams.set('token', `${signedToken}tampered`);
    const tamperedVerification = await request(`${invalidVerificationUrl.pathname}${invalidVerificationUrl.search}`, { redirect: 'manual' });
    ensure(tamperedVerification.status >= 400, 'TAMPERED_VERIFICATION_ACCEPTED');
    await tamperedVerification.arrayBuffer();
    const preservedVerificationDigest = await pool.query(
      'SELECT 1 FROM auth.verification_token_digest WHERE digest = ANY($1::char(64)[])',
      [[...verificationDigests]],
    );
    ensure(preservedVerificationDigest.rowCount === 1, 'TAMPERED_VERIFICATION_CONSUMED_VALID_TOKEN');

    const unverifiedLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: initialPassword },
    });
    ensure(unverifiedLogin.status === 403, 'UNVERIFIED_LOGIN_NOT_BLOCKED');
    await unverifiedLogin.arrayBuffer();

    const verificationResponses = await Promise.all([
      request(`${link.pathname}${link.search}`, { redirect: 'manual' }),
      request(`${link.pathname}${link.search}`, { redirect: 'manual' }),
    ]);
    const verificationStatuses = verificationResponses.map((response) => response.status).sort((a, b) => a - b);
    ensure(verificationStatuses[0] >= 400 && verificationStatuses[1] === 302, 'VERIFICATION_NOT_SINGLE_USE');
    await Promise.all(verificationResponses.map((response) => response.arrayBuffer()));
    const replay = await request(`${link.pathname}${link.search}`, { redirect: 'manual' });
    ensure(replay.status >= 400, 'VERIFICATION_REPLAY_ACCEPTED');
    await replay.arrayBuffer();

    const verifiedUser = await pool.query(
      'SELECT id, name, "emailVerified" FROM auth."user" WHERE email = $1',
      [email],
    );
    ensure(verifiedUser.rowCount === 1 && verifiedUser.rows[0].emailVerified === true, 'EMAIL_VERIFICATION_NOT_PERSISTED');
    const verificationDigest = await pool.query(
      'SELECT 1 FROM auth.verification_token_digest WHERE digest = ANY($1::char(64)[])',
      [[...verificationDigests]],
    );
    ensure(verificationDigest.rowCount === 0, 'VERIFICATION_DIGEST_NOT_CONSUMED');

    const wrongExisting = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: `${initialPassword}-wrong` },
    });
    const wrongExistingBody = await responseJson(wrongExisting);
    const wrongMissing = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email: missingEmail, password: `${initialPassword}-wrong` },
    });
    const wrongMissingBody = await responseJson(wrongMissing);
    ensure(wrongExisting.status === 401 && wrongMissing.status === wrongExisting.status, 'LOGIN_ENUMERATION_STATUS');
    ensure(JSON.stringify(wrongExistingBody) === JSON.stringify(wrongMissingBody), 'LOGIN_ENUMERATION_BODY');

    const primaryLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: initialPassword },
    });
    ensure(primaryLogin.status === 200, 'VERIFIED_LOGIN_FAILED');
    const primaryToken = primaryLogin.headers.get('set-auth-token');
    ensure(primaryToken && !primaryToken.includes('.'), 'BEARER_TOKEN_NOT_OPAQUE');
    sensitiveAuthValues.add(primaryToken);
    const primaryPayload = await responseJson(primaryLogin);
    ensure(!JSON.stringify(primaryPayload).includes(primaryToken), 'BEARER_TOKEN_IN_BODY');
    const primarySession = await pool.query(
      'SELECT "expiresAt" FROM auth.session WHERE token = $1 AND "userId" = $2',
      [primaryToken, verifiedUser.rows[0].id],
    );
    const sessionExpiresAt = new Date(primarySession.rows[0]?.expiresAt ?? 0).getTime();
    ensure(primarySession.rowCount === 1 && sessionExpiresAt > Date.now() && sessionExpiresAt <= Date.now() + 7 * 24 * 60 * 60 * 1_000 + 60_000, 'OPAQUE_SESSION_NOT_PERSISTED');

    const authSession = await request('/api/auth/get-session', {
      headers: { authorization: `Bearer ${primaryToken}` },
    });
    ensure(authSession.status === 200 && authSession.headers.get('cache-control')?.includes('no-store') && authSession.headers.get('pragma') === 'no-cache', 'AUTH_SESSION_NOT_PRIVATE_NO_STORE');
    const authSessionPayload = await responseJson(authSession);
    ensure(authSessionPayload.session && authSessionPayload.user?.emailVerified === true, 'AUTH_SESSION_NOT_VERIFIED');
    ensure(!JSON.stringify(authSessionPayload).includes(primaryToken), 'AUTH_SESSION_LEAKED_TOKEN');

    const profile = await request('/v1/me', { headers: { authorization: `Bearer ${primaryToken}` } });
    ensure(profile.status === 200 && profile.headers.get('cache-control')?.includes('no-store') && profile.headers.get('pragma') === 'no-cache', 'PROFILE_NOT_PRIVATE_NO_STORE');
    const profilePayload = await responseJson(profile);
    ensure(profilePayload.data?.userId === verifiedUser.rows[0].id && profilePayload.data?.email === email && profilePayload.data?.emailVerified === true, 'PROFILE_IDENTITY_INVALID');
    ensure(!JSON.stringify(profilePayload).includes(primaryToken) && !('token' in profilePayload.data), 'PROFILE_LEAKED_TOKEN');

    const secondLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: initialPassword },
    });
    ensure(secondLogin.status === 200, 'SECOND_LOGIN_FAILED');
    const secondToken = secondLogin.headers.get('set-auth-token');
    ensure(secondToken && secondToken !== primaryToken, 'SECOND_SESSION_NOT_ISSUED');
    sensitiveAuthValues.add(secondToken);
    const revokeFirst = await request('/api/auth/revoke-session', {
      method: 'POST',
      body: { token: primaryToken },
      headers: { authorization: `Bearer ${secondToken}` },
    });
    ensure(revokeFirst.ok, 'CROSS_SESSION_REVOKE_FAILED');
    await revokeFirst.arrayBuffer();
    const revokedProfile = await request('/v1/me', { headers: { authorization: `Bearer ${primaryToken}` } });
    ensure(revokedProfile.status === 401, 'REVOKED_SESSION_STILL_AUTHENTICATED');
    await revokedProfile.arrayBuffer();

    const signOutLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: initialPassword },
    });
    ensure(signOutLogin.status === 200, 'SIGNOUT_LOGIN_FAILED');
    const signOutToken = signOutLogin.headers.get('set-auth-token');
    ensure(signOutToken, 'SIGNOUT_TOKEN_MISSING');
    sensitiveAuthValues.add(signOutToken);
    const signOut = await request('/api/auth/sign-out', {
      method: 'POST',
      body: {},
      headers: { authorization: `Bearer ${signOutToken}` },
    });
    ensure(signOut.ok, 'SIGNOUT_FAILED');
    await signOut.arrayBuffer();
    const afterSignOut = await request('/v1/me', { headers: { authorization: `Bearer ${signOutToken}` } });
    ensure(afterSignOut.status === 401, 'SIGNOUT_SESSION_STILL_AUTHENTICATED');
    await afterSignOut.arrayBuffer();

    const badRedirect = await request('/api/auth/request-password-reset', {
      method: 'POST',
      body: { email, redirectTo: 'https://invalid.example/steal-token' },
    });
    ensure(badRedirect.status >= 400, 'UNTRUSTED_RESET_REDIRECT_ACCEPTED');
    await badRedirect.arrayBuffer();

    const resetRequest = await request('/api/auth/request-password-reset', {
      method: 'POST',
      body: { email, redirectTo: `${apiOrigin}/reset-password` },
    });
    ensure(resetRequest.ok, 'RESET_REQUEST_FAILED');
    await resetRequest.arrayBuffer();
    const resetMail = await waitForMail(email, 'reset');
    const token = await resetToken(resetMail.id);

    const tamperedReset = await request('/api/auth/reset-password', {
      method: 'POST',
      body: { token: `${token}tampered`, newPassword: resetPassword },
    });
    ensure(tamperedReset.status >= 400, 'TAMPERED_RESET_ACCEPTED');
    await tamperedReset.arrayBuffer();
    const preservedReset = await pool.query('SELECT 1 FROM auth.verification WHERE identifier = $1', [`reset-password:${token}`]);
    ensure(preservedReset.rowCount === 1, 'TAMPERED_RESET_CONSUMED_VALID_TOKEN');

    const reset = await request('/api/auth/reset-password', {
      method: 'POST',
      body: { token, newPassword: resetPassword },
    });
    ensure(reset.ok, 'PASSWORD_RESET_FAILED');
    await reset.arrayBuffer();
    const replayReset = await request('/api/auth/reset-password', {
      method: 'POST',
      body: { token, newPassword: `${resetPassword}-again` },
    });
    ensure(replayReset.status >= 400, 'RESET_REPLAY_ACCEPTED');
    await replayReset.arrayBuffer();

    const afterReset = await request('/v1/me', { headers: { authorization: `Bearer ${secondToken}` } });
    ensure(afterReset.status === 401, 'PASSWORD_RESET_DID_NOT_REVOKE_SESSIONS');
    await afterReset.arrayBuffer();
    const oldPasswordLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: initialPassword },
    });
    ensure(oldPasswordLogin.status === 401, 'OLD_PASSWORD_STILL_VALID');
    await oldPasswordLogin.arrayBuffer();
    const newPasswordLogin = await request('/api/auth/sign-in/email', {
      method: 'POST',
      body: { email, password: resetPassword },
    });
    ensure(newPasswordLogin.status === 200, 'NEW_PASSWORD_LOGIN_FAILED');
    const newToken = newPasswordLogin.headers.get('set-auth-token');
    ensure(newToken, 'NEW_PASSWORD_SESSION_MISSING');
    sensitiveAuthValues.add(newToken);

    const expiredProfileSession = await pool.query(
      'UPDATE auth.session SET "expiresAt" = NOW() - INTERVAL \'1 second\' WHERE token = $1 RETURNING id',
      [newToken],
    );
    ensure(expiredProfileSession.rowCount === 1, 'SESSION_EXPIRY_FIXTURE_FAILED');
    const expiredProfile = await request('/v1/me', { headers: { authorization: `Bearer ${newToken}` } });
    ensure(expiredProfile.status === 401, 'EXPIRED_SESSION_STILL_AUTHENTICATED');
    await expiredProfile.arrayBuffer();

    const duplicateSignUp = await request('/api/auth/sign-up/email', {
      method: 'POST',
      body: { name: 'Different Name', email, password: `${resetPassword}-different` },
    });
    const duplicateBody = await responseJson(duplicateSignUp);
    ensure(duplicateSignUp.status === signUp.status, 'SIGNUP_ENUMERATION_STATUS');
    ensure(Object.keys(duplicateBody).sort().join('|') === Object.keys(signUpPayload).sort().join('|'), 'SIGNUP_ENUMERATION_SHAPE');
    ensure(!JSON.stringify(duplicateBody).includes(email), 'SIGNUP_ENUMERATION_EMAIL');

    await proveRateLimit();
  } finally {
    if (app) {
      try {
        await app.close();
      } catch {
        cleanupFailures.push('APP_CLOSE');
      }
    }
    try {
      await deleteMailpitMessages([email, untrustedEmail]);
    } catch {
      cleanupFailures.push('MAILPIT');
    }
    try {
      await cleanupDatabase(pool, [email, untrustedEmail]);
    } catch {
      cleanupFailures.push('DATABASE');
    }
    try {
      await pool.end();
    } catch {
      cleanupFailures.push('DATABASE_POOL');
    }
    const capturedLogs = capturedRuntimeLogs.join('');
    if ([...sensitiveAuthValues].some((value) => value && capturedLogs.includes(value))) {
      cleanupFailures.push('SENSITIVE_AUTH_DATA_LOGGED');
    }
    captureRuntimeLogs = false;
    for (const restore of restoreRuntimeLogCapture) restore();
  }
}

run().then(() => {
  ensure(cleanupFailures.length === 0, 'CLEANUP_FAILED');
  process.stdout.write('PASS auth-postgres: signup, SMTP verify/tamper/replay, verified bearer sessions, private profile, revoke/signout/reset/expiry, redirect/origin denial, enumeration and PostgreSQL-backed rate limit.\n');
}).catch((error) => {
  const message = error instanceof Error && error.message.startsWith('FARMLY_AUTH_POSTGRES_')
    ? error.message
    : `FARMLY_AUTH_POSTGRES_UNEXPECTED_${error?.constructor?.name ?? 'ERROR'}`;
  const cleanup = cleanupFailures.length > 0 ? `_CLEANUP_${cleanupFailures.join('_')}` : '';
  process.stderr.write(`${message}${cleanup}\n`);
  process.exitCode = 1;
});
