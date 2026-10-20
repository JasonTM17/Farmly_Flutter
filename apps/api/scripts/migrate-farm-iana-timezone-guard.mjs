import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610190001_farm_iana_timezone_guard';
await applySqlMigration({
  migrationId,
  migrationName: 'farm IANA timezone guard',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
