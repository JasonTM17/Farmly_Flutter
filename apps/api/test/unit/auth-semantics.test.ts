import { afterEach, describe, expect, it } from 'vitest';
import { betterAuth } from 'better-auth';
import { memoryAdapter, type MemoryDB } from 'better-auth/adapters/memory';
import type { ApiEnvironment } from '../../src/config/environment.js';
import { createFarmlyAuthOptions, type AuthEmailSender } from '../../src/auth/auth-options.js';
import { digestVerificationToken, type VerificationTokenStore } from '../../src/auth/one-time-verification.js';

const origin = 'http://localhost:3400';
const authEnvironment: Pick<ApiEnvironment, 'nodeEnv' | 'betterAuthUrl' | 'betterAuthSecret'> = {
  nodeEnv: 'test',
  betterAuthUrl: origin,
  betterAuthSecret: 'farmly-test-secret-with-at-least-thirty-two-characters',
};

interface SentEmail {
  readonly email: string;
  readonly name: string;
  readonly url: string;
}

interface AuthHarness {
  readonly auth: ReturnType<typeof betterAuth>;
  readonly db: MemoryDB;
  readonly verificationEmails: SentEmail[];
  readonly resetEmails: SentEmail[];
  readonly verificationTokens: Map<string, Date>;
}

const harnesses: AuthHarness[] = [];

function createHarness(includeFarmlyVerificationGuard = true): AuthHarness {
  const verificationEmails: SentEmail[] = [];
  const resetEmails: SentEmail[] = [];
  const emailSender: AuthEmailSender = {
    sendVerificationEmail: async (message) => { verificationEmails.push(message); },
    sendPasswordResetEmail: async (message) => { resetEmails.push(message); },
  };
  const verificationTokens = new Map<string, Date>();
  const verificationTokenStore: VerificationTokenStore = {
    issue: async (digest, expiresAt) => {
      if (verificationTokens.has(digest)) throw new Error('Verification token digest already exists');
      verificationTokens.set(digest, expiresAt);
    },
    consume: async (digest, now) => {
      const expiresAt = verificationTokens.get(digest);
      verificationTokens.delete(digest);
      return expiresAt !== undefined && expiresAt.getTime() > now.getTime();
    },
  };
  const db: MemoryDB = {
    user: [], session: [], account: [], verification: [], rateLimit: [],
  };
  const options = createFarmlyAuthOptions(authEnvironment, memoryAdapter(db), emailSender, verificationTokenStore);
  const auth = betterAuth(includeFarmlyVerificationGuard
    ? options
    : { ...options, plugins: options.plugins?.slice(0, 1) });
  const harness = { auth, db, verificationEmails, resetEmails, verificationTokens };
  harnesses.push(harness);
  return harness;
}

afterEach(() => {
  harnesses.length = 0;
});

async function post(auth: AuthHarness['auth'], path: string, body: unknown, headers: Record<string, string> = {}) {
  return auth.handler(new Request(`${origin}/api/auth${path}`, {
    method: 'POST',
    headers: { origin, 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  }));
}

async function getSession(auth: AuthHarness['auth'], token: string): Promise<unknown> {
  const response = await auth.handler(new Request(`${origin}/api/auth/get-session`, {
    headers: { authorization: `Bearer ${token}`, origin },
  }));
  return response.json();
}

function sessionFrom(payload: unknown): unknown {
  return payload && typeof payload === 'object' && 'session' in payload
    ? (payload as { session: unknown }).session
    : null;
}

function clearRateLimitFixture(harness: AuthHarness): void {
  harness.db.rateLimit!.length = 0;
}

async function signUpAndVerify(harness: AuthHarness, email = 'owner@farmly.test') {
  const signUp = await post(harness.auth, '/sign-up/email', {
    name: 'Farmly Owner', email, password: 'test-password-1234',
  });
  expect(signUp.status).toBe(200);
  expect(harness.verificationEmails).toHaveLength(1);
  const verificationUrl = new URL(harness.verificationEmails[0]!.url);
  const verified = await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }));
  expect(verified.status).toBe(302);
}

describe('pinned Better Auth session and email semantics', () => {
  it('accepts the exact native Farmly verification callback', async () => {
    const harness = createHarness();
    const callbackURL = 'farmly:///auth/verified';
    const signUp = await post(harness.auth, '/sign-up/email', {
      name: 'Farmly Native User',
      email: 'native@farmly.test',
      password: 'test-password-1234',
      callbackURL,
    });
    expect(signUp.status).toBe(200);
    expect(harness.verificationEmails).toHaveLength(1);

    const verificationUrl = new URL(harness.verificationEmails[0]!.url);
    expect(verificationUrl.searchParams.get('callbackURL')).toBe(callbackURL);
    const verified = await harness.auth.handler(new Request(verificationUrl, {
      headers: { origin },
    }));
    expect(verified.status).toBe(302);
    expect(verified.headers.get('location')).toMatch(/^farmly:\/\/\/auth\/verified/);
  });

  it('characterizes the pinned library replay behavior without Farmly’s guard', async () => {
    const harness = createHarness(false);
    const signUp = await post(harness.auth, '/sign-up/email', {
      name: 'Farmly Owner', email: 'baseline@farmly.test', password: 'test-password-1234',
    });
    expect(signUp.status).toBe(200);

    const verificationUrl = new URL(harness.verificationEmails[0]!.url);
    const firstUse = await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }));
    const replay = await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }));
    expect(firstUse.status).toBe(302);
    expect(replay.status).toBe(302);
  });

  it('requires verification, issues an opaque Bearer session, disables cookie cache, and honors revoke/expiry', async () => {
    const harness = createHarness();
    const signUp = await post(harness.auth, '/sign-up/email', {
      name: 'Farmly Owner', email: 'owner@farmly.test', password: 'test-password-1234',
    });
    expect(signUp.status).toBe(200);
    expect((await signUp.json() as { token: unknown }).token).toBeNull();
    expect(harness.verificationEmails).toHaveLength(1);

    const blockedSignIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    expect(blockedSignIn.status).toBe(403);

    const verificationUrl = new URL(harness.verificationEmails[0]!.url);
    const rawToken = verificationUrl.searchParams.get('token');
    expect(rawToken).toBeTruthy();
    expect(harness.verificationTokens.has(rawToken!)).toBe(false);
    expect(harness.verificationTokens.has(digestVerificationToken(rawToken!))).toBe(true);

    const wrongOrigin = await harness.auth.handler(new Request(verificationUrl, { headers: { origin: 'https://evil.example' } }));
    expect(wrongOrigin.status).toBeGreaterThanOrEqual(400);
    expect(harness.verificationTokens.has(digestVerificationToken(rawToken!))).toBe(true);

    const tamperedTokenUrl = new URL(verificationUrl);
    tamperedTokenUrl.searchParams.set('token', `${rawToken}tampered`);
    const tamperedToken = await harness.auth.handler(new Request(tamperedTokenUrl));
    expect(tamperedToken.status).toBe(401);
    expect(harness.verificationTokens.has(digestVerificationToken(rawToken!))).toBe(true);

    const invalidCallbackUrl = new URL(verificationUrl);
    invalidCallbackUrl.searchParams.set('callbackURL', 'https://evil.example/steal-token');
    const invalidCallback = await harness.auth.handler(new Request(invalidCallbackUrl));
    expect(invalidCallback.status).toBeGreaterThanOrEqual(400);
    expect(harness.verificationTokens.has(digestVerificationToken(rawToken!))).toBe(true);

    const verified = await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }));
    expect(verified.status).toBe(302);
    const duplicateVerification = await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }));
    expect(duplicateVerification.status).toBe(401);

    const signIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    clearRateLimitFixture(harness);
    expect(signIn.status).toBe(200);
    const token = signIn.headers.get('set-auth-token');
    expect(token).toBeTruthy();
    expect(token).not.toContain('Bearer ');

    const activeSession = await harness.auth.handler(new Request(`${origin}/api/auth/get-session`, {
      headers: { authorization: `Bearer ${token}`, origin },
    }));
    expect(activeSession.status).toBe(200);
    expect(activeSession.headers.get('cache-control')).toContain('no-store');
    expect(activeSession.headers.get('pragma')).toBe('no-cache');
    expect((await activeSession.json() as { session: unknown }).session).toBeTruthy();

    const secondSignIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    clearRateLimitFixture(harness);
    const secondToken = secondSignIn.headers.get('set-auth-token');
    expect(secondToken).toBeTruthy();
    const firstSessionToken = String(harness.db.session![0]!.token);
    const revoke = await post(harness.auth, '/revoke-session', { token: firstSessionToken }, { authorization: `Bearer ${secondToken}` });
    expect(revoke.status).toBe(200);
    expect(sessionFrom(await getSession(harness.auth, token!))).toBeNull();
    expect(sessionFrom(await getSession(harness.auth, secondToken!))).toBeTruthy();

    const thirdSignIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    clearRateLimitFixture(harness);
    const thirdToken = thirdSignIn.headers.get('set-auth-token');
    expect(thirdToken).toBeTruthy();
    const revokeOthers = await post(harness.auth, '/revoke-other-sessions', {}, { authorization: `Bearer ${secondToken}` });
    expect(revokeOthers.status).toBe(200);
    expect(sessionFrom(await getSession(harness.auth, thirdToken!))).toBeNull();
    expect(sessionFrom(await getSession(harness.auth, secondToken!))).toBeTruthy();

    const signOut = await post(harness.auth, '/sign-out', {}, { authorization: `Bearer ${secondToken}` });
    expect(signOut.status).toBe(200);
    expect(sessionFrom(await getSession(harness.auth, secondToken!))).toBeNull();

    const fourthSignIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    clearRateLimitFixture(harness);
    const fourthToken = fourthSignIn.headers.get('set-auth-token');
    expect(fourthToken).toBeTruthy();

    for (const session of harness.db.session!) session.expiresAt = new Date(Date.now() - 1_000);
    expect(sessionFrom(await getSession(harness.auth, fourthToken!))).toBeNull();
  });

  it('atomically accepts at most one concurrent use of a fresh verification link', async () => {
    const harness = createHarness();
    const signUp = await post(harness.auth, '/sign-up/email', {
      name: 'Farmly Worker', email: 'worker@farmly.test', password: 'test-password-1234',
    });
    expect(signUp.status).toBe(200);
    const verificationUrl = new URL(harness.verificationEmails[0]!.url);

    const responses = await Promise.all([
      harness.auth.handler(new Request(verificationUrl, { headers: { origin } })),
      harness.auth.handler(new Request(verificationUrl, { headers: { origin } })),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([302, 401]);
  });

  it('uses one-time reset links and revokes existing sessions after password reset', async () => {
    const harness = createHarness();
    await signUpAndVerify(harness);
    const signIn = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    const oldToken = signIn.headers.get('set-auth-token');
    expect(oldToken).toBeTruthy();

    const requestReset = await post(harness.auth, '/request-password-reset', {
      email: 'owner@farmly.test',
      redirectTo: `${origin}/reset-password`,
    });
    expect(requestReset.status).toBe(200);
    expect(harness.resetEmails).toHaveLength(1);
    const resetPath = new URL(harness.resetEmails[0]!.url).pathname.split('/');
    const resetToken = resetPath[resetPath.indexOf('reset-password') + 1] ?? null;
    expect(resetToken).toBeTruthy();

    const reset = await post(harness.auth, '/reset-password', {
      token: resetToken,
      newPassword: 'test-password-5678',
    });
    expect(reset.status).toBe(200);
    expect(sessionFrom(await getSession(harness.auth, oldToken!))).toBeNull();

    const oldPassword = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-1234',
    });
    expect(oldPassword.status).toBe(401);
    const newPassword = await post(harness.auth, '/sign-in/email', {
      email: 'owner@farmly.test', password: 'test-password-5678',
    });
    expect(newPassword.status).toBe(200);
    const repeatReset = await post(harness.auth, '/reset-password', {
      token: resetToken,
      newPassword: 'test-password-9999',
    });
    expect(repeatReset.status).toBeGreaterThanOrEqual(400);
  });

  it('does not disclose duplicate sign-up, rejects untrusted origins/redirects, and rate-limits login attempts', async () => {
    const harness = createHarness();
    const initial = await post(harness.auth, '/sign-up/email', {
      name: 'Farmly Owner', email: 'owner@farmly.test', password: 'test-password-1234',
    });
    const verificationUrl = new URL(harness.verificationEmails[0]!.url);
    expect((await harness.auth.handler(new Request(verificationUrl, { headers: { origin } }))).status).toBe(302);
    const firstBody = await initial.json() as Record<string, unknown>;
    const duplicate = await post(harness.auth, '/sign-up/email', {
      name: 'Other Name', email: 'owner@farmly.test', password: 'other-password-5678',
    });
    const duplicateBody = await duplicate.json() as Record<string, unknown>;
    expect(duplicate.status).toBe(initial.status);
    expect(Object.keys(duplicateBody).sort()).toEqual(Object.keys(firstBody).sort());
    expect(JSON.stringify(duplicateBody)).not.toMatch(/already|exists|registered/i);

    const wrongOrigin = await post(harness.auth, '/sign-up/email', {
      name: 'Intruder', email: 'intruder@evil.test', password: 'test-password-1234',
    }, { origin: 'https://evil.example' });
    expect(wrongOrigin.status).toBeGreaterThanOrEqual(400);

    const invalidRedirect = await post(harness.auth, '/request-password-reset', {
      email: 'owner@farmly.test',
      redirectTo: 'https://evil.example/steal-token',
    });
    expect(invalidRedirect.status).toBeGreaterThanOrEqual(400);
    expect(harness.resetEmails).toHaveLength(0);

    const knownReset = await post(harness.auth, '/request-password-reset', {
      email: 'owner@farmly.test', redirectTo: `${origin}/reset-password`,
    });
    const unknownReset = await post(harness.auth, '/request-password-reset', {
      email: 'missing@farmly.test', redirectTo: `${origin}/reset-password`,
    });
    const knownResetBody = await knownReset.json() as Record<string, unknown>;
    const unknownResetBody = await unknownReset.json() as Record<string, unknown>;
    expect(unknownReset.status).toBe(knownReset.status);
    expect(unknownResetBody).toEqual(knownResetBody);
    expect(JSON.stringify(unknownResetBody)).not.toMatch(/owner@farmly|missing@farmly/i);
    expect(harness.resetEmails).toHaveLength(1);

    const attempts = [];
    for (let count = 0; count < 4; count += 1) {
      attempts.push(await post(harness.auth, '/sign-in/email', {
        email: 'missing@farmly.test', password: 'wrong-password-1234',
      }));
    }
    expect(attempts.slice(0, 3).every((response) => response.status !== 429)).toBe(true);
    expect(attempts[3]!.status).toBe(429);
  });
});
