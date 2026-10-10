import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610130002_ai_dispatch';
await applySqlMigration({
  migrationId,
  migrationName: 'AI dispatch: lease, recovery, snapshot/message writers',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
