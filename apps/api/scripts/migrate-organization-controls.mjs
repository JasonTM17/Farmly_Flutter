import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationIds = [
  '202610060004_organization_controls',
  '202610060005_invitation_policy_version_qualification',
  '202610060006_invitation_ttl_after_org_lock',
  '202610060007_organization_memberships',
  '202610060008_ownership_transfer_replay',
  '202610060009_qualify_membership_actor',
  '202610060010_validate_membership_grants',
];

for (const migrationId of migrationIds) {
  await applySqlMigration({
    migrationId,
    migrationName: 'organization-controls',
    migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
  });
  if (process.exitCode) break;
}
