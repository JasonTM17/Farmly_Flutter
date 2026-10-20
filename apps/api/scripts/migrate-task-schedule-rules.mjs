import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610190002_task_occurrence_schedule_rules';
await applySqlMigration({
  migrationId,
  migrationName: 'task occurrence schedule rules',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
