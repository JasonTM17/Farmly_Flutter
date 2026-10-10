import { createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-PINS';
const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const EVIDENCE_PATH = 'plans/261005-1435-farmly-mobile-app/reports/dependency-pin-evidence-p02.json';
const usage = 'Usage: node tools/qa/check-dependency-pins.mjs [--json]';

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

export function isExactRelease(value) {
  return typeof value === 'string' && /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(value);
}

export function parsePubLock(text) {
  const packages = new Map();
  let inPackages = false;
  let currentName;
  for (const line of text.split(/\r?\n/)) {
    if (line === 'packages:') {
      inPackages = true;
      continue;
    }
    if (inPackages && /^(?:sdks|dependency_overrides):/.test(line)) {
      inPackages = false;
      currentName = undefined;
      continue;
    }
    const entry = line.match(/^  ([A-Za-z0-9_.-]+):$/);
    if (inPackages && entry) {
      currentName = entry[1];
      packages.set(currentName, {});
      continue;
    }
    if (!inPackages || !currentName) continue;
    const source = line.match(/^    source: ([A-Za-z0-9_-]+)$/);
    const version = line.match(/^    version: "?([^"\s]+)"?$/);
    if (source) packages.get(currentName).source = source[1];
    if (version) packages.get(currentName).version = version[1];
  }
  return packages;
}

export function parsePubspecPins(text) {
  const pins = new Map();
  let section;
  let currentName;
  for (const line of text.split(/\r?\n/)) {
    const topLevel = line.match(/^(dependencies|dev_dependencies|dependency_overrides):\s*$/);
    if (topLevel) {
      section = topLevel[1];
      currentName = undefined;
      continue;
    }
    if (/^\S/.test(line)) {
      section = undefined;
      currentName = undefined;
      continue;
    }
    if (!section) continue;
    const dependency = line.match(/^  ([A-Za-z0-9_.-]+):(?:\s*(.*))?$/);
    if (dependency) {
      currentName = dependency[1];
      const value = dependency[2]?.trim();
      if (value) pins.set(currentName, value.replace(/^['"]|['"]$/g, ''));
      continue;
    }
    if (/^    (?:sdk|path|git):/.test(line)) currentName = undefined;
  }
  return pins;
}

function requireCondition(condition, code) {
  if (!condition) throw new Error(code);
}

function checkNpm(evidence) {
  const packageText = readFileSync(join(ROOT, 'apps/api/package.json'), 'utf8');
  const lockText = readFileSync(join(ROOT, evidence.lockfile), 'utf8');
  const manifest = JSON.parse(packageText);
  const lock = JSON.parse(lockText);
  requireCondition(sha256(lockText) === evidence.lockfileSha256, 'NPM_LOCK_EVIDENCE_STALE');
  requireCondition(lock.lockfileVersion === 3, 'NPM_LOCK_VERSION');
  const packageEntries = Object.entries(lock.packages).filter(([path]) => path !== '');
  const packageNames = new Set(packageEntries.map(([path]) => path.slice(path.lastIndexOf('node_modules/') + 13)));
  requireCondition(packageEntries.length === evidence.lockEntries, 'NPM_LOCK_COUNT');
  requireCondition(packageNames.size === evidence.uniquePackages, 'NPM_PACKAGE_COUNT');
  let directCount = 0;
  for (const section of ['dependencies', 'devDependencies']) {
    for (const [name, version] of Object.entries(manifest[section] ?? {})) {
      directCount += 1;
      requireCondition(isExactRelease(version), 'NPM_DIRECT_PIN_NOT_EXACT');
      requireCondition(lock.packages['']?.[section]?.[name] === version, 'NPM_ROOT_LOCK_DRIFT');
      requireCondition(lock.packages[`node_modules/${name}`]?.version === version, 'NPM_RESOLVED_PIN_DRIFT');
    }
  }
  const overrides = JSON.stringify(manifest.overrides ?? {});
  requireCondition(!/(?:"|:)\s*"?(?:\*|latest|next)"?(?:,|\})/i.test(overrides), 'NPM_FLOATING_OVERRIDE');
  for (const item of evidence.licenseMetadataExceptions) {
    const lockEntry = lock.packages[`node_modules/${item.name}`];
    requireCondition(lockEntry?.version === item.version, 'NPM_LICENSE_EXCEPTION_DRIFT');
    const licensePath = join(ROOT, item.archiveLicensePath);
    requireCondition(existsSync(licensePath), 'NPM_LICENSE_ARCHIVE_MISSING');
    const licenseText = readFileSync(licensePath, 'utf8');
    requireCondition(/permission is hereby granted, free of charge/i.test(licenseText), 'NPM_LICENSE_TEXT_UNVERIFIED');
  }
  return { lockEntries: packageEntries.length, uniquePackages: packageNames.size, directExactPins: directCount };
}

function checkPub(evidence) {
  const lockText = readFileSync(join(ROOT, evidence.lockfile), 'utf8');
  const specText = readFileSync(join(ROOT, 'apps/mobile/pubspec.yaml'), 'utf8');
  requireCondition(sha256(lockText) === evidence.lockfileSha256, 'PUB_LOCK_EVIDENCE_STALE');
  const lock = parsePubLock(lockText);
  const hosted = [...lock.values()].filter((item) => item.source === 'hosted');
  requireCondition(hosted.length === evidence.hostedLockEntries, 'PUB_LOCK_COUNT');
  const pins = parsePubspecPins(specText);
  let directCount = 0;
  for (const [name, pin] of pins) {
    requireCondition(isExactRelease(pin), 'PUB_DIRECT_PIN_NOT_EXACT');
    requireCondition(lock.get(name)?.version === pin, 'PUB_RESOLVED_PIN_DRIFT');
    directCount += 1;
  }
  return { hostedLockEntries: hosted.length, directExactPins: directCount };
}

export function validateDependencyEvidence(evidence) {
  requireCondition(evidence.schemaVersion === 'farmly-dependency-pin-evidence.v1', 'PIN_EVIDENCE_SCHEMA');
  requireCondition(evidence.acceptedMinimumReleaseAgeDays === 7, 'PIN_AGE_POLICY');
  const cutoff = Date.parse(evidence.registrySweepCutoff);
  const assessed = Date.parse(evidence.assessedAt);
  requireCondition(Number.isFinite(cutoff) && Number.isFinite(assessed), 'PIN_AGE_EVIDENCE_DATE');
  requireCondition(assessed - cutoff >= evidence.acceptedMinimumReleaseAgeDays * 86_400_000, 'PIN_AGE_WINDOW_INVALID');
  return true;
}

function validateAgeSweep(evidence) {
  requireCondition(evidence.ageSweep.underAge === 0 && evidence.ageSweep.unknownPublishedAt === 0 && evidence.ageSweep.registryErrors === 0, 'PIN_AGE_SWEEP_INCOMPLETE');
}

async function run(options) {
  const evidence = JSON.parse(readFileSync(join(ROOT, EVIDENCE_PATH), 'utf8'));
  validateDependencyEvidence(evidence);
  validateAgeSweep(evidence.npm);
  validateAgeSweep(evidence.pub);
  requireCondition(existsSync(join(ROOT, evidence.sourceReport)), 'PIN_SOURCE_REPORT_MISSING');
  const npm = checkNpm(evidence.npm);
  const pub = checkPub(evidence.pub);
  return {
    status: 'PASS',
    code: 'LOCKS_MATCH_HASH_BOUND_REGISTRY_SWEEP',
    productEvidence: false,
    details: {
      npm,
      pub,
      registryEvidence: evidence.assessedAt,
      licenseArchiveExceptions: evidence.npm.licenseMetadataExceptions.length,
      registryAdvisoryAudit: evidence.registryAdvisoryAudit,
    },
  };
}

await runQaCli({
  gate,
  usage,
  run,
  selfTest: () => {
    selfTestArgumentParser();
    if (!isExactRelease('1.2.3') || isExactRelease('^1.2.3') || isExactRelease('latest')) throw new Error('PIN_SELF_TEST');
    const pub = parsePubLock('packages:\n  alpha:\n    source: hosted\n    version: "1.2.3"\n  flutter:\n    source: sdk\n    version: "0.0.0"\nsdks:\n  dart: ">=3.0.0 <4.0.0"\n');
    if (pub.get('alpha')?.version !== '1.2.3' || pub.get('flutter')?.source !== 'sdk') throw new Error('PIN_SELF_TEST');
  },
});
