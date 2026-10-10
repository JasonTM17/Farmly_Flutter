import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610120001_sync_bootstrap';
await applySqlMigration({
  migrationId,
  migrationName: 'sync bootstrap snapshots and retention floor',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
