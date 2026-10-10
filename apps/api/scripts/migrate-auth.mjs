import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610060001_auth_core';
await applySqlMigration({
  migrationId,
  migrationName: 'auth',
  migrationFile: new URL(`../prisma/auth/migrations/${migrationId}/migration.sql`, import.meta.url),
});
