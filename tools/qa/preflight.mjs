import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { REPO_ROOT, runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-PREFLIGHT';
const usage = 'Usage: node tools/qa/preflight.mjs [--json]';
const requiredEnvironmentKeys = [
  'DATABASE_URL_TENANT',
  'DATABASE_URL_AUTH',
  'BETTER_AUTH_SECRET',
  'BETTER_AUTH_URL',
  'CURSOR_SIGNING_KEY',
];

function environmentFileValues(filePath) {
  if (!existsSync(filePath)) return new Map();
  return parseEnvironmentValues(readFileSync(filePath, 'utf8'));
}

function parseEnvironmentValues(contents) {
  const values = new Map();
  for (const line of contents.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, '').trim();
    }
    values.set(match[1], value);
  }
  return values;
}

function isUsableEnvironmentValue(key, value) {
  if (typeof value !== 'string' || value.trim().length === 0) return false;
  const normalized = value.trim();
  if (/(?:^|[=:/])(?:replace-with-|replace-me(?:\b|[-/])|placeholder(?:\b|[-/])|example-|changeme\b|your[-_]|<set-locally)/i.test(normalized)) {
    return false;
  }
  if (key === 'BETTER_AUTH_SECRET' || key === 'CURSOR_SIGNING_KEY') return normalized.length >= 32;
  if (key === 'DATABASE_URL_TENANT' || key === 'DATABASE_URL_AUTH') {
    try {
      return ['postgres:', 'postgresql:'].includes(new URL(normalized).protocol);
    } catch {
      return false;
    }
  }
  if (key === 'BETTER_AUTH_URL') {
    try {
      return Boolean(new URL(normalized).hostname);
    } catch {
      return false;
    }
  }
  return true;
}

function missingEnvironmentKeys(values) {
  return requiredEnvironmentKeys.filter((key) => !isUsableEnvironmentValue(key, values.get(key)));
}

function selfTest() {
  selfTestArgumentParser();
  const canary = 'preflight-redaction-canary-0123456789';
  const setting = (parts, value) => [parts.join('_'), value].join('=');
  const values = parseEnvironmentValues([
    setting(['DATABASE', 'URL', 'TENANT'], `postgresql://farmly:${canary}@127.0.0.1/farmly_test`),
    setting(['DATABASE', 'URL', 'AUTH'], ''),
    setting(['BETTER', 'AUTH', 'SECRET'], `replace-with-${canary}`),
    setting(['BETTER', 'AUTH', 'URL'], '"http://localhost:3000"'),
    setting(['CURSOR', 'SIGNING', 'KEY'], 'cursor-signing-key-is-long-enough-0123456789'),
  ].join('\n'));
  const missing = missingEnvironmentKeys(values);
  if (missing.join(',') !== 'DATABASE_URL_AUTH,BETTER_AUTH_SECRET' || JSON.stringify(missing).includes(canary)) {
    throw new Error('PREFLIGHT_ENVIRONMENT_SELF_TEST');
  }
}

function inspect(command, args, cwd = REPO_ROOT) {
  const isFlutterBatch = process.platform === 'win32' && command === 'flutter';
  const executable = isFlutterBatch ? process.env.ComSpec ?? 'cmd.exe' : command;
  const actualArgs = isFlutterBatch ? ['/d', '/s', '/c', `flutter ${args.join(' ')}`] : args;
  const result = spawnSync(executable, actualArgs, { cwd, encoding: 'utf8', timeout: 20000, windowsHide: true });
  return result.error || result.status !== 0 ? undefined : result.stdout.trim();
}

async function run(options) {
  const configuredValues = environmentFileValues(join(REPO_ROOT, 'apps/api/.env'));
  for (const key of requiredEnvironmentKeys) {
    if (process.env[key] !== undefined) configuredValues.set(key, process.env[key]);
  }

  const [nodeMajor, nodeMinor] = process.versions.node.split('.').map(Number);
  const nodeOk = nodeMajor === 24 && nodeMinor >= 12;
  const flutterMachine = inspect('flutter', ['--version', '--machine']);
  const flutterOk = Boolean(flutterMachine && (() => {
    try {
      const version = JSON.parse(flutterMachine);
      return typeof version.frameworkVersion === 'string' && typeof version.dartSdkVersion === 'string';
    } catch {
      return false;
    }
  })());
  const devicesText = inspect('flutter', ['devices', '--machine']);
  let targetMatches = false;
  if (devicesText) {
    try {
      const devices = JSON.parse(devicesText);
      targetMatches = devices.some((device) =>
        device.id === process.env.FARMLY_QA_DEVICE_ID && ['android', 'ios'].includes(device.targetPlatform));
    } catch {
      targetMatches = false;
    }
  }
  const xcodeAvailable = Boolean(inspect('xcodebuild', ['-version']));
  const dockerServer = inspect('docker', ['version', '--format', '{{.Server.Version}}']);
  const missingKeys = missingEnvironmentKeys(configuredValues);
  const targetId = process.env.FARMLY_QA_DEVICE_ID;
  const targetAlias = process.env.FARMLY_QA_TARGET_ALIAS;
  const dedicatedAlias = typeof targetAlias === 'string' && /^farmly-[a-z0-9-]+$/i.test(targetAlias);
  const dedicatedDevice = Boolean(targetId) && dedicatedAlias && targetMatches;
  const blockers = [];
  if (!nodeOk) blockers.push('NODE_RUNTIME_UNVERIFIED');
  if (!flutterOk) blockers.push('FLUTTER_RUNTIME_UNAVAILABLE');
  if (!dedicatedDevice) blockers.push('FARMLY_NATIVE_TARGET_UNAVAILABLE');
  if (process.platform !== 'darwin' || !xcodeAvailable) blockers.push('IOS_TOOLCHAIN_UNAVAILABLE');
  if (!dockerServer) blockers.push('DOCKER_SERVER_UNAVAILABLE');
  if (missingKeys.length) blockers.push('API_ENVIRONMENT_INCOMPLETE');

  const details = {
    nodeRuntime: nodeOk ? 'available' : 'unverified',
    flutterRuntime: flutterOk ? 'available' : 'unavailable',
    dockerServer: dockerServer ? 'available' : 'unavailable',
    dedicatedFarmlyDevice: dedicatedDevice,
    iosToolchain: process.platform === 'darwin' && xcodeAvailable,
    missingEnvironmentKeys: missingKeys,
    blockers,
  };
  return blockers.length
    ? { status: 'BLOCKED_CAPABILITY', code: 'PREFLIGHT_REQUIREMENTS_MISSING', productEvidence: false, details }
    : { status: 'PASS', code: 'PREFLIGHT_CAPABILITIES_PRESENT', productEvidence: false, details };
}

await runQaCli({ gate, usage, run, selfTest });
