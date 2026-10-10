import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610060011_farm_mutation_kernel';
await applySqlMigration({
  migrationId,
  migrationName: 'mutation kernel',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
