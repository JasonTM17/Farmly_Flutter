import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function parseApiPreviewTag(tag, apiVersion) {
  if (typeof tag !== 'string' || typeof apiVersion !== 'string') return null;
  if (!/^\d+\.\d+\.\d+$/.test(apiVersion)) return null;

  const escapedVersion = apiVersion.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`^api-v${escapedVersion}-preview\\.([1-9][0-9]*)$`).exec(tag);
  return match ? `${apiVersion}-preview.${match[1]}` : null;
}

function run() {
  const tag = process.env.GITHUB_REF_NAME;
  const outputPath = process.env.GITHUB_OUTPUT;
  const packageUrl = new URL('../../apps/api/package.json', import.meta.url);
  const { version } = JSON.parse(readFileSync(packageUrl, 'utf8'));
  const imageVersion = parseApiPreviewTag(tag, version);

  if (!imageVersion) {
    throw new Error(`Tag must match api-v${version}-preview.N with N >= 1.`);
  }
  if (!outputPath) {
    throw new Error('GITHUB_OUTPUT is required to pass the validated image version.');
  }

  appendFileSync(outputPath, `version=${imageVersion}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    run();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
