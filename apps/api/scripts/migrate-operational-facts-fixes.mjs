import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610100002_operational_facts_fixes';
await applySqlMigration({
  migrationId,
  migrationName: 'operational facts kernel fixes',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
