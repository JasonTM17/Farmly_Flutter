import { createHash } from 'node:crypto';
import { existsSync, lstatSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { bootstrapEntities } from '../../contracts/scripts/build-contracts.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const SERIALIZER_SOURCE = 'tools/qa/measure-bootstrap-fixture.mjs';
const PLAN_REPORTS = 'plans/261005-1435-farmly-mobile-app/reports/';
const FIXTURE_ROOT = 'tools/qa/fixtures/';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function wireJson(value) {
  return Buffer.from(JSON.stringify(canonicalize(value)), 'utf8');
}

function uuidFor(entityIndex, rowIndex, isOperation = false) {
  const suffix = String((entityIndex + 1) * 1_000_000 + rowIndex + 1).padStart(12, '0');
  return `00000000-0000-${isOperation ? '4001' : '4000'}-8000-${suffix}`;
}

function expand(value, entityIndex, rowIndex) {
  if (Array.isArray(value)) return value.map((item) => expand(item, entityIndex, rowIndex));
  if (!value || typeof value !== 'object') {
    if (typeof value !== 'string') return value;
    return value.replace(/\{\{(index|uuid|opId|cycle:([^}]+))\}\}/g, (_whole, token, choices) => {
      if (token === 'index') return String(rowIndex + 1).padStart(5, '0');
      if (token === 'uuid') return uuidFor(entityIndex, rowIndex);
      if (token === 'opId') return uuidFor(entityIndex, rowIndex, true);
      const cycle = choices.split('|');
      return cycle[(entityIndex + rowIndex) % cycle.length];
    });
  }
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, expand(item, entityIndex, rowIndex)]));
}

function validateFixture(fixture) {
  if (fixture.fixtureSchemaVersion !== 'farm-bootstrap-fixture.v1') throw new Error('FIXTURE_SCHEMA');
  if (fixture.serializerVersion !== 'farmly-bootstrap-wire.v1') throw new Error('SERIALIZER_VERSION');
  if (!fixture.snapshot || !fixture.snapshot.snapshotId || !fixture.snapshot.organizationId || !fixture.snapshot.farmId) throw new Error('SNAPSHOT_SCOPE');
  if (!Number.isInteger(fixture.chunkSizeRows) || fixture.chunkSizeRows < 1 || fixture.chunkSizeRows > 100) throw new Error('CHUNK_SIZE');
  if (!Array.isArray(fixture.entityProfiles)) throw new Error('ENTITY_PROFILES');
  const names = fixture.entityProfiles.map((profile) => profile.entity);
  if (new Set(names).size !== names.length) throw new Error('DUPLICATE_ENTITY');
  if (JSON.stringify(names) !== JSON.stringify(bootstrapEntities)) throw new Error('ENTITY_INVENTORY');
  for (const profile of fixture.entityProfiles) {
    if (!Number.isSafeInteger(profile.count) || profile.count < 1 || profile.count > 1_000_000) throw new Error('ROW_COUNT');
    if (!profile.template || typeof profile.template !== 'object' || Array.isArray(profile.template)) throw new Error('ROW_TEMPLATE');
  }
}

export function measureFixture(fixtureText, openapiText, serializerText = readFileSync(fileURLToPath(import.meta.url), 'utf8')) {
  const fixture = JSON.parse(fixtureText);
  const openapi = JSON.parse(openapiText);
  validateFixture(fixture);
  const declaredEntities = openapi['x-farmly-bootstrap-entities'];
  if (JSON.stringify(declaredEntities) !== JSON.stringify(bootstrapEntities)) throw new Error('OPENAPI_ENTITY_DRIFT');

  const materialized = fixture.entityProfiles.map((profile, entityIndex) => ({
    entity: profile.entity,
    rows: Array.from({ length: profile.count }, (_, rowIndex) => expand(profile.template, entityIndex, rowIndex)),
  }));
  const snapshot = fixture.snapshot;
  const chunkFrames = [];
  for (const [entityIndex, entity] of materialized.entries()) {
    for (let offset = 0; offset < entity.rows.length; offset += fixture.chunkSizeRows) {
      const chunkId = `chunk-${String(chunkFrames.length + 1).padStart(6, '0')}`;
      const rows = entity.rows.slice(offset, offset + fixture.chunkSizeRows);
      const frame = {
        schemaVersion: 'farm-bootstrap-chunk.v1',
        snapshotId: snapshot.snapshotId,
        chunkId,
        entity: entity.entity,
        rowOffset: offset,
        rows,
      };
      const bytes = wireJson(frame);
      chunkFrames.push({
        chunkId,
        entity: entity.entity,
        rowOffset: offset,
        rowCount: rows.length,
        utf8Bytes: bytes.byteLength,
        sha256: sha256(bytes),
        bytes,
      });
    }
  }

  const manifest = {
    schemaVersion: 'farm-bootstrap-manifest.v1',
    snapshotId: snapshot.snapshotId,
    scope: {
      organizationId: snapshot.organizationId,
      farmId: snapshot.farmId,
      continuityEpoch: snapshot.continuityEpoch,
      scopePolicyVersion: snapshot.scopePolicyVersion,
    },
    highWatermark: snapshot.highWatermark,
    createdAt: snapshot.createdAt,
    expiresAt: snapshot.expiresAt,
    chunks: chunkFrames.map(({ chunkId, entity, rowOffset, rowCount, sha256: digest }) => ({
      chunkId, entity, rowOffset, rowCount, sha256: digest,
    })),
  };
  const manifestBytes = wireJson(manifest);
  const totalRows = materialized.reduce((sum, entity) => sum + entity.rows.length, 0);
  const chunkByteCount = chunkFrames.reduce((sum, chunk) => sum + chunk.utf8Bytes, 0);
  const transferByteCount = manifestBytes.byteLength + chunkByteCount;
  const chunkDigest = createHash('sha256');
  for (const chunk of chunkFrames) chunkDigest.update(chunk.bytes);
  const rowCandidate = Math.ceil((totalRows * 1.25) / 100) * 100;
  const byteCandidate = Math.ceil((transferByteCount * 1.5) / 1024) * 1024;

  return {
    receiptVersion: 'farmly-bootstrap-sizing.v1',
    status: 'MEASURED_CANDIDATE_ONLY',
    accepted: false,
    fixtureId: fixture.fixtureId,
    fixturePath: 'tools/qa/fixtures/bootstrap-supported-v1.json',
    fixtureSha256: sha256(fixtureText),
    openapiPath: 'contracts/openapi/farmly-v1.yaml',
    openapiSha256: sha256(openapiText),
    schemaSha256: sha256(openapiText),
    serializerPath: SERIALIZER_SOURCE,
    serializerSha256: sha256(serializerText),
    serializerVersion: fixture.serializerVersion,
    fixtureProfilePurpose: fixture.profilePurpose,
    snapshotScope: {
      organizationId: snapshot.organizationId,
      farmId: snapshot.farmId,
      continuityEpoch: snapshot.continuityEpoch,
      scopePolicyVersion: snapshot.scopePolicyVersion,
      highWatermark: snapshot.highWatermark,
    },
    rowsByEntity: materialized.map(({ entity, rows }) => ({ entity, rows: rows.length })),
    totalRows,
    chunkSizeRows: fixture.chunkSizeRows,
    chunkCount: chunkFrames.length,
    manifest: { utf8Bytes: manifestBytes.byteLength, sha256: sha256(manifestBytes) },
    chunks: {
      totalUtf8Bytes: chunkByteCount,
      concatenatedSha256: chunkDigest.digest('hex'),
      frames: chunkFrames.map(({ chunkId, entity, rowOffset, rowCount, utf8Bytes, sha256: digest }) => ({
        chunkId, entity, rowOffset, rowCount, utf8Bytes, sha256: digest,
      })),
    },
    totalTransferUtf8Bytes: transferByteCount,
    candidateCaps: {
      maxRows: rowCandidate,
      maxBytes: byteCandidate,
      rowHeadroomPercent: 25,
      byteHeadroomPercent: 50,
      ratificationOwner: 'product/operator owner',
      requiresOwnerRatificationBefore: 'P08',
      approved: false,
    },
    limitations: [
      'Rows are deterministic synthetic shapes; this fixture does not validate relational foreign keys or production maximum cardinalities.',
      'Bytes measure canonical uncompressed UTF-8 JSON frames, including the manifest and chunk envelopes; HTTP headers, TLS, compression, and transport framing are excluded.',
      'This is a contract serializer measurement, not a server Repeatable Read snapshot, native encrypted-store measurement, or production bootstrap run.',
      'Weather freshness caches, auth/session records, private AI data, notifications, directory control-plane rows, and operation proofs are outside this farm bootstrap inventory.',
      'The 100-row chunk size is a measurement input and must match the eventual server/mobile contract before P08.',
    ],
  };
}

function isWithin(root, candidate) {
  const rel = relative(root, candidate);
  return rel === '' || (!rel.startsWith(`..${sep}`) && rel !== '..' && !isAbsolute(rel));
}

function safeInput(root, repoPath) {
  if (isAbsolute(repoPath) || repoPath.split(/[\\/]/).includes('..')) throw new Error('PATH_BOUNDARY');
  const normalized = repoPath.replaceAll('\\', '/');
  if (!normalized.startsWith(FIXTURE_ROOT)) throw new Error('FIXTURE_BOUNDARY');
  const absolute = resolve(root, normalized);
  if (!isWithin(root, absolute)) throw new Error('PATH_BOUNDARY');
  const real = realpathSync(absolute);
  if (!isWithin(realpathSync(root), real)) throw new Error('PATH_BOUNDARY');
  return { absolute: real };
}

function safeOutput(root, repoPath) {
  if (isAbsolute(repoPath) || repoPath.split(/[\\/]/).includes('..')) throw new Error('PATH_BOUNDARY');
  const normalized = repoPath.replaceAll('\\', '/');
  if (!normalized.startsWith(PLAN_REPORTS) || !normalized.endsWith('.json')) throw new Error('OUTPUT_BOUNDARY');
  const absolute = resolve(root, normalized);
  if (!isWithin(root, absolute)) throw new Error('PATH_BOUNDARY');
  const parent = realpathSync(dirname(absolute));
  if (!isWithin(realpathSync(root), parent)) throw new Error('PATH_BOUNDARY');
  const target = resolve(parent, basename(absolute));
  if (existsSync(target) && lstatSync(target).isSymbolicLink()) throw new Error('OUTPUT_SYMLINK');
  return { absolute: target, parent };
}

function parseArgs(argv) {
  const parsed = { help: false, fixture: undefined, output: undefined };
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === '--help') parsed.help = true;
    else if (key === '--fixture' || key === '--output') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Error('ARG_VALUE');
      parsed[key.slice(2)] = value;
      index += 1;
    } else throw new Error('ARG_UNKNOWN');
  }
  if (!parsed.help && (!parsed.fixture || !parsed.output)) throw new Error('ARG_REQUIRED');
  return parsed;
}

function run() {
  try {
    const args = parseArgs(process.argv.slice(2));
    if (args.help) {
      console.log('Usage: node tools/qa/measure-bootstrap-fixture.mjs --fixture tools/qa/fixtures/bootstrap-supported-v1.json --output plans/261005-1435-farmly-mobile-app/reports/bootstrap-sizing-p02.json');
      return;
    }
    const fixtureFile = safeInput(ROOT, args.fixture);
    const outputFile = safeOutput(ROOT, args.output);
    if (!isWithin(ROOT, fixtureFile.absolute) || !isWithin(ROOT, outputFile.parent)) throw new Error('PATH_BOUNDARY');
    const fixtureText = readFileSync(fixtureFile.absolute, 'utf8');
    const openapiText = readFileSync(resolve(ROOT, 'contracts/openapi/farmly-v1.yaml'), 'utf8');
    const receipt = `${JSON.stringify(measureFixture(fixtureText, openapiText), null, 2)}\n`;
    let existing;
    try { existing = readFileSync(outputFile.absolute, 'utf8'); } catch { existing = undefined; }
    if (existing !== undefined && existing !== receipt) throw new Error('OUTPUT_EXISTS_DIFFERENT');
    if (existing === undefined) writeFileSync(outputFile.absolute, receipt, { encoding: 'utf8', flag: 'wx' });
    const parsed = JSON.parse(receipt);
    console.log(`PASS bootstrap measurement: ${parsed.rowsByEntity.length} entities, ${parsed.totalRows} rows, ${parsed.chunkCount} chunks, ${parsed.totalTransferUtf8Bytes} UTF-8 bytes`);
    console.log(`Candidate only: maxRows=${parsed.candidateCaps.maxRows}, maxBytes=${parsed.candidateCaps.maxBytes}; owner ratification required before P08.`);
    console.log(`Receipt: ${args.output.replaceAll('\\', '/')}`);
  } catch (error) {
    const code = error instanceof Error ? error.message : 'UNKNOWN';
    console.error(`ERROR ${/^[A-Z0-9_]+$/.test(code) ? code : 'MEASUREMENT_FAILED'}`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run();
