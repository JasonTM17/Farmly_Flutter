import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610110001_farm_location_weather';
await applySqlMigration({
  migrationId,
  migrationName: 'farm location and weather cache',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
