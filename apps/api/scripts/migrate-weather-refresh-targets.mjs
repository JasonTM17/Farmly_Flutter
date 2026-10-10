import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610110002_weather_refresh_targets';
await applySqlMigration({
  migrationId,
  migrationName: 'weather refresh targets',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
