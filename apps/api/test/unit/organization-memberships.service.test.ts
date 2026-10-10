import { describe, expect, it, vi } from 'vitest';
import type { TenantDatabaseService } from '../../src/db/tenant-database.service.js';
import { OrganizationMembershipsService } from '../../src/organizations/organization-memberships.service.js';
import type { VerifiedPrincipal } from '../../src/auth/verified-session.guard.js';

const organizationId = 'd4f92f8a-7487-4e8c-83e1-31b13e65a8c2';
const membershipId = '5c4f0ab4-df6f-49ab-a0e4-448fdce54a51';
const operationId = '162a67c4-a435-47be-a2e3-6c8b4b3d1785';

const principal: VerifiedPrincipal = {
  actorId: 'membership-service-test-user',
  email: 'membership-service-test@farmly.test',
  displayName: 'Membership service test',
  sessionId: 'e03c765e-015d-45b6-b6b0-0feccb359cb1',
  sessionExpiresAt: new Date('2026-10-07T00:00:00.000Z'),
};

function serviceWithAdapterFailure(failure: unknown): OrganizationMembershipsService {
  const transaction = {
    $queryRaw: vi.fn()
      .mockResolvedValueOnce([])
      .mockRejectedValueOnce(failure),
  };
  const database = {
    client: {
      $transaction: vi.fn(async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction)),
    },
  };
  return new OrganizationMembershipsService(database as unknown as TenantDatabaseService);
}

async function captureFailure(action: () => Promise<unknown>): Promise<unknown> {
  try {
    await action();
  } catch (error) {
    return error;
  }
  throw new Error('EXPECTED_MEMBERSHIP_SERVICE_FAILURE');
}

describe('OrganizationMembershipsService PostgreSQL adapter errors', () => {
  it('maps the driver adapter original SQLSTATE to a safe operation conflict', async () => {
    const service = serviceWithAdapterFailure({
      code: 'P2010',
      meta: {
        driverAdapterError: {
          cause: { originalCode: '23505' },
        },
      },
    });

    const failure = await captureFailure(() => service.updateFor(
      principal,
      organizationId,
      membershipId,
      operationId,
      { role: 'member', farmGrants: [] },
    ));

    expect(failure).toMatchObject({
      getStatus: expect.any(Function),
      getResponse: expect.any(Function),
    });
    expect((failure as { getStatus: () => number }).getStatus()).toBe(409);
    expect((failure as { getResponse: () => unknown }).getResponse()).toEqual({ code: 'OPERATION_ID_REUSED' });
  });
});
