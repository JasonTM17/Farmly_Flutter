import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610090001_farm_domain_resources';
await applySqlMigration({
  migrationId,
  migrationName: 'farm domain',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
