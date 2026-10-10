import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610090002_kernel_record_guard';
await applySqlMigration({
  migrationId,
  migrationName: 'farm domain kernel guard',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
