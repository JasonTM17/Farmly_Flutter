import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610060002_tenant_identity';
await applySqlMigration({
  migrationId,
  migrationName: 'tenant',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
