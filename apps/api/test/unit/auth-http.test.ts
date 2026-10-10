import 'reflect-metadata';
import { createServer } from 'node:net';
import { ConflictException, ForbiddenException, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import { betterAuth } from 'better-auth';
import { memoryAdapter, type MemoryDB } from 'better-auth/adapters/memory';
import { afterEach, describe, expect, it } from 'vitest';
import type { ApiEnvironment } from '../../src/config/environment.js';
import { createFarmlyAuthOptions, type AuthEmailSender } from '../../src/auth/auth-options.js';
import { FARMLY_AUTH } from '../../src/auth/auth.module.js';
import { mountFarmlyAuthHandler } from '../../src/auth/mount-auth-handler.js';
import type { VerificationTokenStore } from '../../src/auth/one-time-verification.js';
import { VerifiedSessionGuard } from '../../src/auth/verified-session.guard.js';
import { MeController } from '../../src/identity/me.controller.js';
import { FarmlyHttpExceptionFilter } from '../../src/common/farmly-http-exception.filter.js';
import { OrganizationsController } from '../../src/organizations/organizations.controller.js';
import { OrganizationsService } from '../../src/organizations/organizations.service.js';
import { OrganizationMembershipsController } from '../../src/organizations/organization-memberships.controller.js';
import { OrganizationMembershipsService } from '../../src/organizations/organization-memberships.service.js';

const applications: Array<{ close(): Promise<void> }> = [];

afterEach(async () => {
  await Promise.all(applications.splice(0).map((application) => application.close()));
});

async function availablePort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('FARMLY_TEST_PORT_UNAVAILABLE');
  const port = address.port;
  await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return port;
}

describe('Nest HTTP auth mount', () => {
  it('serves auth and protects /v1/me with the verified opaque Bearer session', async () => {
    const port = await availablePort();
    const origin = `http://127.0.0.1:${port}`;
    const verificationEmails: Array<{ email: string; name: string; url: string }> = [];
    const emailSender: AuthEmailSender = {
      sendVerificationEmail: async (message) => { verificationEmails.push(message); },
      sendPasswordResetEmail: async () => undefined,
    };
    const digests = new Map<string, Date>();
    const verificationTokenStore: VerificationTokenStore = {
      issue: async (digest, expiresAt) => { digests.set(digest, expiresAt); },
      consume: async (digest, now) => {
        const expiresAt = digests.get(digest);
        if (!expiresAt || expiresAt <= now) return false;
        digests.delete(digest);
        return true;
      },
    };
    const environment: Pick<ApiEnvironment, 'nodeEnv' | 'betterAuthUrl' | 'betterAuthSecret'> = {
      nodeEnv: 'test',
      betterAuthUrl: origin,
      betterAuthSecret: 'farmly-http-test-secret-with-at-least-thirty-two-characters',
    };
    const db: MemoryDB = { user: [], session: [], account: [], verification: [], rateLimit: [] };
    const auth = betterAuth(createFarmlyAuthOptions(environment, memoryAdapter(db), emailSender, verificationTokenStore));
    const organizationCalls: Array<{ actorId: string; operationId: string; name: string }> = [];
    const directoryCalls: Array<{ actorId: string; organizationId: string; limit: number | null; cursor: string | null }> = [];
    const membershipRemovalCalls: Array<{ actorId: string; organizationId: string; membershipId: string }> = [];
    const membershipUpdateCalls: Array<{ actorId: string; organizationId: string; membershipId: string }> = [];
    const organizationsService = {
      listFor: async () => ({ data: { organizations: [] }, page: { hasMore: false }, meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() } }),
      farmDirectoryFor: async (
        principal: { actorId: string },
        organizationId: string,
        limit: number | null,
        cursor: string | null,
      ) => {
        directoryCalls.push({ actorId: principal.actorId, organizationId, limit, cursor });
        if (organizationId === '00000000-0000-4000-8000-000000000102') {
          throw new ForbiddenException({ code: 'ACCESS_REVOKED' });
        }
        return {
          schemaVersion: 'farm-directory.v1',
          scopePolicyVersion: '9007199254740993',
          continuityEpoch: '1',
          farms: [{ farmId: '00000000-0000-4000-8000-000000000103', status: 'active', grantRole: 'owner' }],
        };
      },
      createFor: async (principal: { actorId: string }, operationId: string, name: string) => {
        organizationCalls.push({ actorId: principal.actorId, operationId, name });
        return { data: { id: '00000000-0000-4000-8000-000000000101', name }, meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() } };
      },
    };
    const membershipsService = {
      updateFor: async (principal: { actorId: string }, organizationId: string, membershipId: string) => {
        membershipUpdateCalls.push({ actorId: principal.actorId, organizationId, membershipId });
        return {};
      },
      removeFor: async (principal: { actorId: string }, organizationId: string, membershipId: string) => {
        membershipRemovalCalls.push({ actorId: principal.actorId, organizationId, membershipId });
        throw new ConflictException({ code: 'VERSION_CONFLICT' });
      },
    };
    class AuthHttpTestModule {}
    Module({
      controllers: [MeController, OrganizationsController, OrganizationMembershipsController],
      providers: [
        VerifiedSessionGuard,
        { provide: FARMLY_AUTH, useValue: auth },
        { provide: OrganizationsService, useValue: organizationsService },
        { provide: OrganizationMembershipsService, useValue: membershipsService },
      ],
    })(AuthHttpTestModule);
    const app = await NestFactory.create(AuthHttpTestModule, new ExpressAdapter(), { logger: false });
    app.useGlobalFilters(new FarmlyHttpExceptionFilter());
    mountFarmlyAuthHandler(app, auth);
    await app.listen(port, '127.0.0.1');
    applications.push(app);

    const signUp = await fetch(`${origin}/api/auth/sign-up/email`, {
      method: 'POST',
      headers: { origin, 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Farmly Owner', email: 'owner@farmly.test', password: 'test-password-1234' }),
    });
    expect(signUp.status).toBe(200);
    expect(verificationEmails).toHaveLength(1);

    const verificationUrl = verificationEmails[0]!.url;
    const verified = await fetch(verificationUrl, { headers: { origin }, redirect: 'manual' });
    const replay = await fetch(verificationUrl, { headers: { origin }, redirect: 'manual' });
    expect(verified.status).toBe(302);
    expect(replay.status).toBe(401);

    const noSession = await fetch(`${origin}/v1/me`);
    expect(noSession.status).toBe(401);
    expect(await noSession.json()).toMatchObject({ error: { code: 'UNAUTHENTICATED' } });
    const noSessionDirectory = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/farm-directory`);
    expect(noSessionDirectory.status).toBe(401);
    expect(directoryCalls).toHaveLength(0);
    const signIn = await fetch(`${origin}/api/auth/sign-in/email`, {
      method: 'POST',
      headers: { origin, 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'owner@farmly.test', password: 'test-password-1234' }),
    });
    expect(signIn.status).toBe(200);
    const bearer = signIn.headers.get('set-auth-token');
    expect(bearer).toBeTruthy();
    const profile = await fetch(`${origin}/v1/me`, { headers: { authorization: `Bearer ${bearer}` } });
    expect(profile.status).toBe(200);
    expect(profile.headers.get('cache-control')).toContain('no-store');
    expect(profile.headers.get('pragma')).toBe('no-cache');
    const profileBody = await profile.json() as { data: Record<string, unknown> };
    expect(profileBody.data).toMatchObject({ email: 'owner@farmly.test', emailVerified: true });
    expect(profileBody.data).not.toHaveProperty('token');
    expect(JSON.stringify(profileBody)).not.toContain(bearer);

    const invalidDirectoryId = await fetch(`${origin}/v1/organizations/not-a-uuid/farm-directory`, {
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(invalidDirectoryId.status).toBe(400);
    expect(directoryCalls).toHaveLength(0);

    const revokedDirectory = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000102/farm-directory`, {
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(revokedDirectory.status).toBe(403);
    expect(await revokedDirectory.json()).toMatchObject({ error: { code: 'ACCESS_REVOKED' } });
    expect(directoryCalls).toEqual([{
      actorId: profileBody.data.userId as string,
      organizationId: '00000000-0000-4000-8000-000000000102',
      limit: null,
      cursor: null,
    }]);

    const directory = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/farm-directory?limit=2&cursor=opaque.cursor`, {
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(directory.status).toBe(200);
    expect(directory.headers.get('cache-control')).toContain('no-store');
    expect(directory.headers.get('pragma')).toBe('no-cache');
    expect(await directory.json()).toEqual({
      schemaVersion: 'farm-directory.v1',
      scopePolicyVersion: '9007199254740993',
      continuityEpoch: '1',
      farms: [{ farmId: '00000000-0000-4000-8000-000000000103', status: 'active', grantRole: 'owner' }],
    });
    expect(directoryCalls).toEqual([
      {
        actorId: profileBody.data.userId as string,
        organizationId: '00000000-0000-4000-8000-000000000102',
        limit: null,
        cursor: null,
      },
      {
        actorId: profileBody.data.userId as string,
        organizationId: '00000000-0000-4000-8000-000000000101',
        limit: 2,
        cursor: 'opaque.cursor',
      },
    ]);

    const invalidDirectoryPage = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/farm-directory?limit=101`, {
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(invalidDirectoryPage.status).toBe(400);
    expect(directoryCalls).toHaveLength(2);

    const duplicateDirectoryCursor = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/farm-directory?cursor=first&cursor=second`, {
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(duplicateDirectoryCursor.status).toBe(410);
    expect(await duplicateDirectoryCursor.json()).toMatchObject({ error: { code: 'CURSOR_EXPIRED' } });
    expect(directoryCalls).toHaveLength(2);

    const mismatch = await fetch(`${origin}/v1/organizations`, {
      method: 'POST',
      headers: {
        origin,
        authorization: `Bearer ${bearer}`,
        'content-type': 'application/json',
        'idempotency-key': '00000000-0000-4000-8000-000000000002',
      },
      body: JSON.stringify({ operationId: '00000000-0000-4000-8000-000000000001', name: 'Farmly Org' }),
    });
    expect(mismatch.status).toBe(400);
    expect(await mismatch.json()).toMatchObject({ error: { code: 'VALIDATION_FAILED' } });
    expect(organizationCalls).toHaveLength(0);

    const createOrganization = await fetch(`${origin}/v1/organizations`, {
      method: 'POST',
      headers: {
        origin,
        authorization: `Bearer ${bearer}`,
        'content-type': 'application/json',
        'idempotency-key': '00000000-0000-4000-8000-000000000001',
      },
      body: JSON.stringify({ operationId: '00000000-0000-4000-8000-000000000001', name: 'Farmly Org' }),
    });
    expect(createOrganization.status).toBe(201);
    expect(createOrganization.headers.get('cache-control')).toContain('no-store');
    expect(organizationCalls).toEqual([{ actorId: profileBody.data.userId, operationId: '00000000-0000-4000-8000-000000000001', name: 'Farmly Org' }]);

    const ownerEscalation = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/memberships/00000000-0000-4000-8000-000000000104`, {
      method: 'PATCH',
      headers: {
        authorization: `Bearer ${bearer}`,
        'content-type': 'application/json',
        'idempotency-key': '00000000-0000-4000-8000-000000000201',
      },
      body: JSON.stringify({ operationId: '00000000-0000-4000-8000-000000000201', payload: { role: 'owner', farmGrants: [] } }),
    });
    expect(ownerEscalation.status).toBe(400);
    expect(await ownerEscalation.json()).toMatchObject({ error: { code: 'VALIDATION_FAILED' } });
    expect(membershipUpdateCalls).toHaveLength(0);

    const lastOwnerRemoval = await fetch(`${origin}/v1/organizations/00000000-0000-4000-8000-000000000101/memberships/00000000-0000-4000-8000-000000000104`, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${bearer}` },
    });
    expect(lastOwnerRemoval.status).toBe(409);
    expect(await lastOwnerRemoval.json()).toMatchObject({ error: { code: 'VERSION_CONFLICT', retryable: false } });
    expect(membershipRemovalCalls).toEqual([{
      actorId: profileBody.data.userId as string,
      organizationId: '00000000-0000-4000-8000-000000000101',
      membershipId: '00000000-0000-4000-8000-000000000104',
    }]);

    const signOut = await fetch(`${origin}/api/auth/sign-out`, {
      method: 'POST',
      headers: { origin, authorization: `Bearer ${bearer}` },
    });
    expect(signOut.status).toBe(200);
    const revokedSession = await fetch(`${origin}/v1/me`, { headers: { authorization: `Bearer ${bearer}` } });
    expect(revokedSession.status).toBe(401);
  });
});
