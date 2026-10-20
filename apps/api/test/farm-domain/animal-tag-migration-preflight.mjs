import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
assert(migrationUrl, 'MIGRATION_DATABASE_URL_REQUIRED');

const parsed = new URL(migrationUrl);
assert(parsed.hostname === 'postgres', 'DATABASE_HOST_INVALID');
assert(decodeURIComponent(parsed.pathname.slice(1)) === expectedDatabaseName, 'DATABASE_NAME_INVALID');
assert(decodeURIComponent(parsed.username) === 'farmly_migration', 'DATABASE_ROLE_INVALID');

const migrationSql = await readFile(new URL(
  '../../prisma/migrations/202610200001_animal_tag_farm_uniqueness/migration.sql',
  import.meta.url,
), 'utf8');
const preflight = migrationSql.match(/DO \$animal_tag_preflight\$[\s\S]*?\$animal_tag_preflight\$;/)?.[0];
assert(preflight, 'ANIMAL_TAG_PREFLIGHT_BLOCK_MISSING');

const client = new Client({ connectionString: migrationUrl });
let inTransaction = false;
try {
  await client.connect();
  const identity = await client.query('SELECT current_database() AS database, current_user AS role');
  assert(identity.rows[0]?.database === expectedDatabaseName, 'DATABASE_IDENTITY_INVALID');
  assert(identity.rows[0]?.role === 'farmly_migration', 'DATABASE_ROLE_INVALID');

  await client.query('BEGIN');
  inTransaction = true;
  const original = await client.query("SELECT 'public.animals'::regclass::oid AS relation_oid");
  await client.query('LOCK TABLE public.animals IN ACCESS EXCLUSIVE MODE');
  await client.query('ALTER TABLE public.animals RENAME TO animals_preflight_original');
  await client.query(`
    CREATE TABLE public.animals (
      organization_id UUID NOT NULL,
      farm_id UUID NOT NULL,
      id UUID NOT NULL,
      tag VARCHAR(64) NOT NULL
    )
  `);
  await client.query(`
    INSERT INTO public.animals (organization_id, farm_id, id, tag)
    VALUES
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'PREFLIGHT-COLLISION'),
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', ' PREFLIGHT-COLLISION ')
  `);
  await client.query('SAVEPOINT duplicate_fixture');

  let rejectionCode;
  try {
    await client.query(preflight);
  } catch (error) {
    rejectionCode = error && typeof error === 'object' && 'code' in error ? error.code : undefined;
  }
  await client.query('ROLLBACK TO SAVEPOINT duplicate_fixture');
  assert(rejectionCode === '23514', 'MIGRATION_PREFLIGHT_DID_NOT_FAIL_CLOSED');

  const fixture = await client.query(`
    SELECT count(*)::INTEGER AS rows, array_agg(tag ORDER BY tag COLLATE "C") AS tags
    FROM public.animals
  `);
  assert(fixture.rows[0]?.rows === 2, 'MIGRATION_PREFLIGHT_CHANGED_DUPLICATE_ROWS');
  assert(JSON.stringify(fixture.rows[0]?.tags) === JSON.stringify([' PREFLIGHT-COLLISION ', 'PREFLIGHT-COLLISION']),
    'MIGRATION_PREFLIGHT_CHANGED_TAG_VALUES');
  const fixtureIndex = await client.query(`
    SELECT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_row.indexrelid
      WHERE index_row.indrelid = 'public.animals'::regclass
        AND index_class.relname = 'animals_org_farm_trimmed_tag_uq'
    ) AS installed
  `);
  assert(fixtureIndex.rows[0]?.installed === false, 'MIGRATION_PREFLIGHT_INSTALLED_INDEX_ON_DUPLICATES');
  await client.query('ROLLBACK');
  inTransaction = false;

  const restored = await client.query("SELECT 'public.animals'::regclass::oid AS relation_oid");
  assert(restored.rows[0]?.relation_oid === original.rows[0]?.relation_oid, 'MIGRATION_PREFLIGHT_DID_NOT_RESTORE_TABLE');
  process.stdout.write(JSON.stringify({ status: 'passed', scope: 'Farmly animal-tag duplicate preflight rollback' }) + '\n');
} catch (error) {
  const safeCode = error && typeof error === 'object' && 'code' in error && typeof error.code === 'string'
    ? error.code
    : error instanceof Error && /^[A-Z0-9_]{1,100}$/.test(error.message)
      ? error.message
      : 'UNEXPECTED_FAILURE';
  process.stderr.write(JSON.stringify({ status: 'failed', code: safeCode }) + '\n');
  process.exitCode = 1;
} finally {
  if (inTransaction) await client.query('ROLLBACK').catch(() => undefined);
  await client.end().catch(() => undefined);
}
