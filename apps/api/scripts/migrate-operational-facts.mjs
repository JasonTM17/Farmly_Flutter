import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610100001_operational_facts';
await applySqlMigration({
  migrationId,
  migrationName: 'operational facts',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
