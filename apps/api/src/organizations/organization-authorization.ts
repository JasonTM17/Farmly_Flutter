export type OrganizationRole = 'owner' | 'admin' | 'member' | 'viewer';
export type OrganizationStatus = 'active' | 'archived';
export type MembershipStatus = 'active' | 'suspended' | 'removed';
export type FarmGrantRole = 'manager' | 'worker' | 'viewer';
export type EffectiveFarmRole = OrganizationRole | 'manager' | 'worker';

export interface FarmAccessState {
  readonly organizationStatus: OrganizationStatus;
  readonly membershipStatus: MembershipStatus;
  readonly organizationRole: OrganizationRole;
  readonly farmGrant?: FarmGrantRole | null;
}

export function effectiveFarmRole(access: FarmAccessState): EffectiveFarmRole | null {
  if (access.organizationStatus !== 'active' || access.membershipStatus !== 'active') return null;
  if (access.organizationRole === 'owner' || access.organizationRole === 'admin') return access.organizationRole;
  if (access.organizationRole === 'viewer') return access.farmGrant ? 'viewer' : null;
  return access.farmGrant ?? null;
}

export function canManageOrganization(role: OrganizationRole): boolean {
  return role === 'owner' || role === 'admin';
}
