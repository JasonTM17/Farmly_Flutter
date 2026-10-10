import { describe, expect, it, vi } from 'vitest';
import type { TenantDatabaseService } from '../../src/db/tenant-database.service.js';
import { OrganizationInvitationsService } from '../../src/organizations/organization-invitations.service.js';
import type { VerifiedPrincipal } from '../../src/auth/verified-session.guard.js';

const organizationId = 'd4f92f8a-7487-4e8c-83e1-31b13e65a8c2';
const operationId = '162a67c4-a435-47be-a2e3-6c8b4b3d1785';

const principal: VerifiedPrincipal = {
  actorId: 'invitation-service-test-user',
  email: 'invitation-service-test@farmly.test',
  displayName: 'Invitation service test',
  sessionId: 'e03c765e-015d-45b6-b6b0-0feccb359cb1',
  sessionExpiresAt: new Date('2026-10-07T00:00:00.000Z'),
};

function serviceWithAdapterFailure(failure: unknown): OrganizationInvitationsService {
  const transaction = {
    $queryRaw: vi.fn().mockRejectedValue(failure),
  };
  const database = {
    client: {
      $transaction: vi.fn(async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction)),
    },
  };
  return new OrganizationInvitationsService(database as unknown as TenantDatabaseService);
}

async function captureFailure(action: () => Promise<unknown>): Promise<unknown> {
  try {
    await action();
  } catch (error) {
    return error;
  }
  throw new Error('EXPECTED_INVITATION_SERVICE_FAILURE');
}

describe('OrganizationInvitationsService PostgreSQL adapter errors', () => {
  it('maps the nested driver SQLSTATE to a safe permission response', async () => {
    const service = serviceWithAdapterFailure({
      code: 'P2010',
      meta: {
        driverAdapterError: {
          cause: { code: '42501' },
        },
      },
    });

    const failure = await captureFailure(() => service.createFor(principal, organizationId, {
      operationId,
      email: 'invitee@farmly.test',
      role: 'member',
      farmGrants: [],
    }));

    expect(failure).toMatchObject({
      getStatus: expect.any(Function),
      getResponse: expect.any(Function),
    });
    expect((failure as { getStatus: () => number }).getStatus()).toBe(403);
    expect((failure as { getResponse: () => unknown }).getResponse()).toEqual({ code: 'PERMISSION_DENIED' });
  });

});
