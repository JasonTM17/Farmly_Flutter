import { applySqlMigration } from './apply-sql-migration.mjs';

const migrationId = '202610200001_animal_tag_farm_uniqueness';
await applySqlMigration({
  migrationId,
  migrationName: 'animal tag farm uniqueness',
  migrationFile: new URL(`../prisma/migrations/${migrationId}/migration.sql`, import.meta.url),
});
