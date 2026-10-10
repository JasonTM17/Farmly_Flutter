import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

export async function applySqlMigration({ migrationId, migrationFile, migrationName }) {
  const migrationSql = await readFile(migrationFile, 'utf8');
  const checksum = createHash('sha256').update(migrationSql).digest('hex');
  const connectionString = process.env.MIGRATION_DATABASE_URL;
  const expectedDatabase = process.env.FARMLY_MIGRATION_DATABASE_NAME;

  if (!connectionString || !expectedDatabase) {
    process.stderr.write(`Farmly ${migrationName} migration requires MIGRATION_DATABASE_URL and FARMLY_MIGRATION_DATABASE_NAME.\n`);
    process.exitCode = 2;
    return;
  }

  let targetDatabase;
  try {
    targetDatabase = decodeURIComponent(new URL(connectionString).pathname.slice(1));
  } catch {
    process.stderr.write(`Farmly ${migrationName} migration connection URL is invalid.\n`);
    process.exitCode = 2;
    return;
  }

  if (targetDatabase !== expectedDatabase) {
    process.stderr.write(`Farmly ${migrationName} migration target database does not match the explicit expected database.\n`);
    process.exitCode = 2;
    return;
  }

  const client = new Client({ connectionString });
  try {
    await client.connect();
    await client.query('BEGIN');
    await client.query(`
      CREATE TABLE IF NOT EXISTS public._farmly_migrations (
        id TEXT PRIMARY KEY,
        checksum CHAR(64) NOT NULL,
        applied_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    `);
    const existing = await client.query('SELECT checksum FROM public._farmly_migrations WHERE id = $1', [migrationId]);
    if (existing.rowCount) {
      if (existing.rows[0].checksum !== checksum) throw new Error('MIGRATION_CHECKSUM_MISMATCH');
      await client.query('COMMIT');
      process.stdout.write(JSON.stringify({ status: 'already-applied', migrationId }) + '\n');
    } else {
      await client.query(migrationSql);
      await client.query('INSERT INTO public._farmly_migrations (id, checksum) VALUES ($1, $2)', [migrationId, checksum]);
      await client.query('COMMIT');
      process.stdout.write(JSON.stringify({ status: 'applied', migrationId }) + '\n');
    }
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const code = error instanceof Error && 'code' in error && typeof error.code === 'string'
      ? error.code
      : error instanceof Error && error.message === 'MIGRATION_CHECKSUM_MISMATCH'
        ? error.message
        : `FARMLY_${migrationName.toUpperCase()}_MIGRATION_FAILED`;
    process.stderr.write(JSON.stringify({ status: 'failed', code }) + '\n');
    process.exitCode = 1;
  } finally {
    await client.end().catch(() => undefined);
  }
}
