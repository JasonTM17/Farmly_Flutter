import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const node = process.execPath;

function run(relativePath, args, env = process.env, environmentOverrides = {}) {
  return spawnSync(node, [relativePath, ...args], {
    cwd: root,
    encoding: 'utf8',
    env: { PATH: env.PATH, SystemRoot: env.SystemRoot, ...environmentOverrides },
    timeout: 15000,
    windowsHide: true,
  });
}

function jsonOutput(result) {
  assert.equal(result.stderr, '');
  return JSON.parse(result.stdout.trim());
}

test('safety shells expose read-only help and self-tests without product PASS claims', () => {
  for (const path of [
    'tools/qa/preflight.mjs',
    'tools/qa/check-dependency-pins.mjs',
    'tools/qa/run-device-journey.mjs',
    'tools/qa/run-device-profile.mjs',
    'tools/qa/backup-restore-drill.mjs',
    'tools/qa/check-secrets.mjs',
    'tools/qa/build-artifacts.mjs',
    'tools/eval/run-chatbot-eval.mjs',
    'apps/api/scripts/qa-gate.mjs',
  ]) {
    const help = run(path, ['--help']);
    assert.equal(help.status, 0, `${path} help should succeed`);
    assert.match(help.stdout, /^Usage:/);
    const selfTest = run(path, ['--self-test', '--json']);
    assert.equal(selfTest.status, 0, `${path} self-test should succeed`);
    const parsed = jsonOutput(selfTest);
    assert.equal(parsed.status, 'PASS');
    assert.equal(parsed.productEvidence, false);
  }
});

test('native and artifact commands never turn missing implementation into PASS', () => {
  const native = run('tools/qa/run-device-journey.mjs', ['--platform', 'android', '--json']);
  assert.equal(native.status, 2);
  assert.equal(jsonOutput(native).status, 'NOT_RUN');

  const badPlatform = run('tools/qa/run-device-profile.mjs', ['--platform', 'windows', '--json']);
  assert.equal(badPlatform.status, 2);
  assert.equal(jsonOutput(badPlatform).code, 'ARG_VALUE');

  const artifact = run('tools/qa/build-artifacts.mjs', ['--local-only', '--json']);
  assert.equal(artifact.status, 2);
  assert.equal(jsonOutput(artifact).status, 'NOT_RUN');
});

test('restore guard requires an isolated scope and does not touch a database', () => {
  const restore = run('tools/qa/backup-restore-drill.mjs', ['--isolated-only', '--json']);
  assert.equal(restore.status, 2);
  const result = jsonOutput(restore);
  assert.equal(result.status, 'BLOCKED_CAPABILITY');
  assert.equal(result.details.databaseTouched, false);
});

test('preflight rejects empty and placeholder environment values without echoing them', () => {
  const marker = 'preflight-redaction-canary-0123456789';
  const result = run('tools/qa/preflight.mjs', ['--json'], process.env, {
    DATABASE_URL_TENANT: `postgresql://farmly:${marker}@127.0.0.1/farmly_test`,
    DATABASE_URL_AUTH: '',
    BETTER_AUTH_SECRET: `replace-with-${marker}`,
    BETTER_AUTH_URL: 'http://localhost:3000',
    CURSOR_SIGNING_KEY: 'short-cursor-key',
  });
  assert.equal(result.status, 2);
  const parsed = jsonOutput(result);
  assert.equal(parsed.status, 'BLOCKED_CAPABILITY');
  assert.ok(parsed.details.missingEnvironmentKeys.includes('DATABASE_URL_AUTH'));
  assert.ok(parsed.details.missingEnvironmentKeys.includes('BETTER_AUTH_SECRET'));
  assert.ok(parsed.details.missingEnvironmentKeys.includes('CURSOR_SIGNING_KEY'));
  assert.equal(result.stdout.includes(marker), false);
  assert.equal(result.stderr.includes(marker), false);
});

test('live AI requires explicit budget authority and makes no provider request', () => {
  const result = run('tools/eval/run-chatbot-eval.mjs', [
    '--suite', 'chatbot-v1', '--mode', 'live', '--require-approved-budget', '--json',
  ], {});
  assert.equal(result.status, 2);
  const parsed = jsonOutput(result);
  assert.equal(parsed.status, 'BLOCKED_CAPABILITY');
  assert.equal(parsed.details.providerRequests, 0);
  assert.equal(result.stdout.includes('sk-'), false);
});

test('future API integration command reports NOT_RUN without connecting to a database', () => {
  const result = run('apps/api/scripts/qa-gate.mjs', ['--gate', 'integration', '--json']);
  assert.equal(result.status, 2);
  const parsed = jsonOutput(result);
  assert.equal(parsed.status, 'NOT_RUN');
  assert.equal(parsed.details.gate, 'Q-API-PG');
});

test('local test services stay scoped, version-pinned, loopback-only, and egress-isolated', () => {
  const compose = readFileSync(join(root, 'infra/compose.yaml'), 'utf8');
  const envExample = readFileSync(join(root, 'infra/.env.example'), 'utf8');

  assert.match(compose, /^name: farmly-test-261005$/m);
  assert.match(compose, /image: postgres:17\.11-alpine3\.24/);
  assert.match(compose, /image: axllent\/mailpit:v1\.31\.3/);
  assert.match(compose, /POSTGRES_DB: farmly_test_261005/);
  assert.match(compose, /com\.farmly\.data-scope: isolated-test-only/);
  assert.match(compose, /127\.0\.0\.1:\$\{FARMLY_TEST_POSTGRES_PORT/);
  assert.match(compose, /127\.0\.0\.1:\$\{FARMLY_TEST_MAILPIT_UI_PORT/);
  assert.match(compose, /127\.0\.0\.1:\$\{FARMLY_TEST_MAILPIT_SMTP_PORT/);
  assert.match(compose, /^\s+internal: true$/m);
  assert.doesNotMatch(compose, /image:\s*\S+:latest\b/);
  assert.match(envExample, /FARMLY_TEST_POSTGRES_PASSWORD=replace-with-a-unique-local-only-password/);
  for (const key of ['AUTH', 'TENANT', 'MIGRATION']) {
    assert.match(envExample, new RegExp(`FARMLY_TEST_${key}_PASSWORD=replace-with-a-unique-local-only-password`));
  }
  for (const path of ['infra/.env', 'apps/api/.env']) {
    const localEnvIgnore = spawnSync('git', ['check-ignore', '--quiet', '--', path], {
      cwd: root,
      windowsHide: true,
    });
    assert.equal(localEnvIgnore.status, 0, `${path} must stay Git-ignored`);
  }
});

test('secret scan excludes Git-ignored local environment files but scans the source tree', () => {
  const result = run('tools/qa/check-secrets.mjs', ['--scope', 'source-and-bundles', '--json']);
  assert.equal(result.status, 0);
  const parsed = jsonOutput(result);
  assert.equal(parsed.status, 'PASS');
  assert.ok(parsed.details.scannedFiles > 0);
});
