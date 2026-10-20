import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { parseApiPreviewTag } from './assert-api-preview-tag.mjs';

const scriptPath = fileURLToPath(new URL('./assert-api-preview-tag.mjs', import.meta.url));

test('accepts the package version with a positive preview number', () => {
  assert.equal(parseApiPreviewTag('api-v0.1.0-preview.1', '0.1.0'), '0.1.0-preview.1');
  assert.equal(parseApiPreviewTag('api-v0.1.0-preview.12', '0.1.0'), '0.1.0-preview.12');
});

test('rejects a wildcard-like delimiter and unrelated tag suffixes', () => {
  assert.equal(parseApiPreviewTag('api-v0.1.0-previewx1', '0.1.0'), null);
  assert.equal(parseApiPreviewTag('api-v0.1.0-preview.1-extra', '0.1.0'), null);
});

test('rejects tags that do not match the package version or positive-number contract', () => {
  assert.equal(parseApiPreviewTag('api-v0.2.0-preview.1', '0.1.0'), null);
  assert.equal(parseApiPreviewTag('api-v0.1.0-preview.0', '0.1.0'), null);
  assert.equal(parseApiPreviewTag('api-v0.1.0-preview.01', '0.1.0'), null);
});

test('CLI writes the validated version to GITHUB_OUTPUT and rejects malformed refs', (context) => {
  const outputDirectory = mkdtempSync(join(tmpdir(), 'farmly-preview-tag-'));
  context.after(() => rmSync(outputDirectory, { recursive: true, force: true }));
  const outputPath = join(outputDirectory, 'github-output');
  const environment = {
    PATH: process.env.PATH,
    GITHUB_OUTPUT: outputPath,
    GITHUB_REF_NAME: 'api-v0.1.0-preview.1',
  };
  for (const key of ['SystemRoot', 'WINDIR']) {
    if (process.env[key]) environment[key] = process.env[key];
  }

  const valid = spawnSync(process.execPath, [scriptPath], { encoding: 'utf8', env: environment });
  assert.equal(valid.status, 0, valid.stderr);
  assert.equal(readFileSync(outputPath, 'utf8'), 'version=0.1.0-preview.1\n');

  const invalid = spawnSync(process.execPath, [scriptPath], {
    encoding: 'utf8',
    env: { ...environment, GITHUB_REF_NAME: 'api-v0.1.0-previewx1' },
  });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /must match api-v0\.1\.0-preview\.N/);
  assert.equal(readFileSync(outputPath, 'utf8'), 'version=0.1.0-preview.1\n');
});
