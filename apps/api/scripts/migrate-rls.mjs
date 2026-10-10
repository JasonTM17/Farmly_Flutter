import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610060003_tenant_rls';
await applySqlMigration({
  migrationId,
  migrationName: 'tenant RLS',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
