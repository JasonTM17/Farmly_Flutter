import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const envFile = fileURLToPath(new URL('../../../infra/.env', import.meta.url));
if (existsSync(envFile)) process.loadEnvFile(envFile);

const databaseName = process.env.FARMLY_TEST_DATABASE_NAME ?? 'farmly_test_261005';
const databaseHost = process.env.FARMLY_TEST_DATABASE_HOST;
const databasePort = Number(process.env.FARMLY_TEST_DATABASE_PORT ?? 5432);
const migrationPassword = process.env.FARMLY_TEST_MIGRATION_PASSWORD;
const authPassword = process.env.FARMLY_TEST_AUTH_PASSWORD;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;

if (databaseName !== 'farmly_test_261005' || databaseHost !== 'postgres' || databasePort !== 5432) {
  process.stderr.write('Farmly isolated runner requires the dedicated postgres:5432 test target.\n');
  process.exit(2);
}
if (!migrationPassword || !authPassword || !tenantPassword) {
  process.stderr.write('Farmly isolated runner requires the dedicated test database credentials.\n');
  process.exit(2);
}

function connectionUrl(role, password) {
  return `postgresql://${role}:${encodeURIComponent(password)}@postgres:5432/${databaseName}`;
}

process.env.FARMLY_MIGRATION_DATABASE_NAME = databaseName;
process.env.MIGRATION_DATABASE_URL = connectionUrl('farmly_migration', migrationPassword);
process.env.DATABASE_URL_AUTH = connectionUrl('farmly_auth_app', authPassword);
process.env.DATABASE_URL_TENANT = connectionUrl('farmly_tenant_app', tenantPassword);
process.env.NODE_ENV ??= 'test';
process.env.BETTER_AUTH_SECRET ??= randomBytes(32).toString('base64url');
process.env.BETTER_AUTH_URL ??= 'http://127.0.0.1:3000';
process.env.CURSOR_SIGNING_KEY ??= randomBytes(32).toString('base64url');
process.env.SMTP_HOST ??= 'mailpit';
process.env.SMTP_PORT ??= '1025';
process.env.SMTP_SECURE ??= 'false';
process.env.SMTP_REQUIRE_TLS ??= 'false';

const separator = process.argv.indexOf('--');
const command = separator === -1 ? process.argv.slice(2) : process.argv.slice(separator + 1);
if (command.length === 0) {
  process.stderr.write('Farmly isolated runner requires a command after --.\n');
  process.exit(2);
}

const child = spawn(command[0], command.slice(1), { env: process.env, stdio: 'inherit' });
child.once('error', () => {
  process.stderr.write('Farmly isolated command could not start.\n');
  process.exitCode = 127;
});
child.once('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exitCode = code ?? 1;
});
