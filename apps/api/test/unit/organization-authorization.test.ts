import { describe, expect, it } from 'vitest';
import { canManageOrganization, effectiveFarmRole } from '../../src/organizations/organization-authorization.js';

const activeMember = {
  organizationStatus: 'active' as const,
  membershipStatus: 'active' as const,
  organizationRole: 'member' as const,
};

describe('effective organization and farm roles', () => {
  it('grants organization owners/admins access across their farms', () => {
    expect(effectiveFarmRole({ ...activeMember, organizationRole: 'owner', farmGrant: null })).toBe('owner');
    expect(effectiveFarmRole({ ...activeMember, organizationRole: 'admin', farmGrant: null })).toBe('admin');
    expect(canManageOrganization('owner')).toBe(true);
    expect(canManageOrganization('admin')).toBe(true);
  });

  it('caps an organization viewer at read-only despite a stale stronger farm grant', () => {
    expect(effectiveFarmRole({ ...activeMember, organizationRole: 'viewer', farmGrant: 'manager' })).toBe('viewer');
    expect(effectiveFarmRole({ ...activeMember, organizationRole: 'viewer', farmGrant: null })).toBeNull();
    expect(canManageOrganization('viewer')).toBe(false);
  });

  it('requires an active membership and an explicit grant for ordinary members', () => {
    expect(effectiveFarmRole({ ...activeMember, farmGrant: null })).toBeNull();
    expect(effectiveFarmRole({ ...activeMember, farmGrant: 'worker' })).toBe('worker');
    expect(effectiveFarmRole({ ...activeMember, membershipStatus: 'suspended', farmGrant: 'manager' })).toBeNull();
    expect(effectiveFarmRole({ ...activeMember, organizationStatus: 'archived', farmGrant: 'manager' })).toBeNull();
  });
});
