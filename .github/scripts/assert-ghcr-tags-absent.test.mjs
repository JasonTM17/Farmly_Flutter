import assert from 'node:assert/strict';
import test from 'node:test';
import { assertTagsAbsent } from './assert-ghcr-tags-absent.mjs';

const image = 'ghcr.io/example/farmly-api';
const tags = ['0.1.0-preview.1', 'sha-0123456789abcdef'];
const digestA = `sha256:${'a'.repeat(64)}`;
const digestB = `sha256:${'b'.repeat(64)}`;

test('allows a push only after every destination tag is confirmed absent', () => {
  const inspected = [];
  const references = assertTagsAbsent({
    image,
    tags,
    inspect(reference) {
      inspected.push(reference);
      return { status: 1, stdout: '', stderr: `ERROR: ${reference}: not found` };
    },
  });

  assert.deepEqual(references, tags.map((tag) => `${image}:${tag}`));
  assert.deepEqual(inspected, references);
});

test('refuses to overwrite a tag that already exists', () => {
  assert.throws(
    () => assertTagsAbsent({ image, tags, inspect: () => ({ status: 0, stdout: `Digest: ${digestA}`, stderr: '' }) }),
    /Refusing to overwrite existing GHCR tags/,
  );
});

test('inspects both refs and reports a version-only partial release without authorizing a push', () => {
  const inspected = [];
  assert.throws(
    () => assertTagsAbsent({
      image,
      tags,
      inspect(reference) {
        inspected.push(reference);
        return reference.endsWith(tags[0])
          ? { status: 0, stdout: `Digest: ${digestA}`, stderr: '' }
          : { status: 1, stdout: '', stderr: `ERROR: ${reference}: not found` };
      },
    }),
    new RegExp(`Partial GHCR release detected.*${digestA}.*No tag was pushed`),
  );
  assert.deepEqual(inspected, tags.map((tag) => `${image}:${tag}`));
});

test('reports a SHA-only partial release and refuses to authorize the missing version tag', () => {
  const inspected = [];
  assert.throws(
    () => assertTagsAbsent({
      image,
      tags,
      inspect(reference) {
        inspected.push(reference);
        return reference.endsWith(tags[1])
          ? { status: 0, stdout: `Digest: ${digestB}`, stderr: '' }
          : { status: 1, stdout: '', stderr: `ERROR: ${reference}: not found` };
      },
    }),
    new RegExp(`Partial GHCR release detected.*${digestB}.*No tag was pushed`),
  );
  assert.deepEqual(inspected, tags.map((tag) => `${image}:${tag}`));
});

test('refuses a complete existing tag pair even when both point to one digest', () => {
  assert.throws(
    () => assertTagsAbsent({ image, tags, inspect: () => ({ status: 0, stdout: `Digest: ${digestA}`, stderr: '' }) }),
    /Refusing to overwrite existing GHCR tags/,
  );
});

test('reports divergent digests without authorizing a repair push', () => {
  assert.throws(
    () => assertTagsAbsent({
      image,
      tags,
      inspect(reference) {
        const digest = reference.endsWith(tags[0]) ? digestA : digestB;
        return { status: 0, stdout: `Digest: ${digest}`, stderr: '' };
      },
    }),
    new RegExp(`different digests.*${digestA}.*${digestB}`),
  );
});

test('fails closed for authentication, network, and other registry errors', () => {
  for (const stderr of ['unauthorized: denied', 'network timeout', 'ERROR: manifest unknown']) {
    assert.throws(
      () => assertTagsAbsent({ image, tags, inspect: () => ({ status: 1, stdout: '', stderr }) }),
      /Could not confirm that the GHCR tag is absent/,
    );
  }
});

test('fails closed when the Docker inspection process cannot start', () => {
  assert.throws(
    () => assertTagsAbsent({ image, tags, inspect: () => ({ status: null, stdout: '', stderr: '' }) }),
    /Could not confirm that the GHCR tag is absent/,
  );
});

test('rejects incomplete preflight inputs', () => {
  const inspectMissing = () => ({ status: 1, stderr: `ERROR: ${image}:tag: not found` });
  assert.throws(() => assertTagsAbsent({ image: '', tags, inspect: inspectMissing }), /Image name is required/);
  assert.throws(() => assertTagsAbsent({ image, tags: [], inspect: inspectMissing }), /At least one/);
  assert.throws(() => assertTagsAbsent({ image, tags, inspect: null }), /inspection function is required/);
});
