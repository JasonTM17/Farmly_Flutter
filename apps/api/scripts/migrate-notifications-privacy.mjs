import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610140001_notifications_privacy';
await applySqlMigration({
  migrationId,
  migrationName: 'Notifications + privacy: in-app notifications, device registrations, audited privacy requests',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
