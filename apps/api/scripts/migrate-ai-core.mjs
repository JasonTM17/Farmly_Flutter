import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610130001_ai_core';
await applySqlMigration({
  migrationId,
  migrationName: 'AI core: consent, conversations, requests, events, quota',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
