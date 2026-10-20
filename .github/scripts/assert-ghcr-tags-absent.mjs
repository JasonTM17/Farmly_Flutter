import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function assertTagsAbsent({ image, tags, inspect }) {
  if (typeof image !== 'string' || image.length === 0) {
    throw new TypeError('Image name is required.');
  }
  if (!Array.isArray(tags) || tags.length === 0 || tags.some((tag) => typeof tag !== 'string' || tag.length === 0)) {
    throw new TypeError('At least one non-empty image tag is required.');
  }
  if (typeof inspect !== 'function') {
    throw new TypeError('A registry inspection function is required.');
  }

  const references = tags.map((tag) => `${image}:${tag}`);
  const states = references.map((reference) => {
    const result = inspect(reference);
    if (result?.status === 0) {
      const output = [result?.stdout, result?.stderr]
        .filter((part) => typeof part === 'string')
        .join('\n');
      const digest = output.match(/^Digest:\s*(sha256:[0-9a-f]{64})$/m)?.[1] ?? 'digest-unavailable';
      return { reference, exists: true, digest };
    }

    const output = [result?.stdout, result?.stderr]
      .filter((part) => typeof part === 'string')
      .join('\n');
    const expectedMissingLine = `ERROR: ${reference}: not found`;
    const isConfirmedMissing = output.split(/\r?\n/).some((line) => line.trim() === expectedMissingLine);
    if (!isConfirmedMissing) {
      throw new Error(`Could not confirm that the GHCR tag is absent; refusing to push: ${reference}`);
    }
    return { reference, exists: false };
  });

  const existing = states.filter((state) => state.exists).map((state) => state.reference);
  if (existing.length === references.length) {
    const present = states.filter((state) => state.exists);
    const digests = present.map((state) => `${state.reference}@${state.digest}`);
    const distinctDigests = new Set(present.map((state) => state.digest));
    const detail = distinctDigests.size > 1 ? 'Existing GHCR tags resolve to different digests' : 'Refusing to overwrite existing GHCR tags';
    throw new Error(`${detail}: ${digests.join(', ')}`);
  }
  if (existing.length > 0) {
    const missing = states.filter((state) => !state.exists).map((state) => state.reference);
    const presentWithDigests = states
      .filter((state) => state.exists)
      .map((state) => `${state.reference}@${state.digest}`);
    throw new Error(
      `Partial GHCR release detected (existing: ${presentWithDigests.join(', ')}; missing: ${missing.join(', ')}). ` +
      'No tag was pushed. Inspect both digests and attestations read-only; do not retry, delete, or replace tags without release-owner direction.',
    );
  }

  return references;
}

function main() {
  const image = process.env.IMAGE;
  const tags = [process.env.VERSION, process.env.REVISION_TAG];
  const references = assertTagsAbsent({
    image,
    tags,
    inspect(reference) {
      const result = spawnSync('docker', ['buildx', 'imagetools', 'inspect', reference], {
        encoding: 'utf8',
        windowsHide: true,
      });
      return { status: result.status, stdout: result.stdout, stderr: result.stderr };
    },
  });

  for (const reference of references) {
    console.log(`Confirmed registry tag is absent: ${reference}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Registry tag preflight failed.');
    process.exitCode = 1;
  }
}
