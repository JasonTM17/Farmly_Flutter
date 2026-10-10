import { readdirSync, lstatSync, readFileSync } from 'node:fs';
import { basename, join, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { REPO_ROOT, runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-SECRETS';
const ignoredDirectories = new Set([
  '.git', '.agentkit', '.agents', '.codex', '.devin', '.playwright-mcp', '.dart_tool', '.pub',
  '.platform-scaffold-temp', 'node_modules', 'build', 'dist', 'coverage', '.gradle', 'Pods',
]);
const placeholderValues = /^(?:unit-test-|test-only-|local-test-|short-sensitive-value|replace-with-|placeholder|example-|changeme|your[-_]|<set-locally)/i;
const patterns = [
  { code: 'PRIVATE_KEY', pattern: /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/g },
  { code: 'PROVIDER_KEY', pattern: /\bsk-[A-Za-z0-9_-]{24,}\b/g },
  { code: 'AWS_ACCESS_KEY', pattern: /\bAKIA[0-9A-Z]{16}\b/g },
  { code: 'NPM_TOKEN', pattern: /\bnpm_[A-Za-z0-9]{36}\b/g },
  {
    code: 'NAMED_SECRET_VALUE',
    pattern: /\b(?:BETTER_AUTH_SECRET|CURSOR_SIGNING_KEY|DEEPSEEK_API_KEY|DATABASE_URL_(?:TENANT|AUTH|MIGRATION)|MIGRATION_DATABASE_URL)\s*=\s*["']?([^\s"'`#]{20,})/gi,
    capture: 1,
  },
  {
    code: 'TEST_DATABASE_PASSWORD',
    pattern: /\bFARMLY_TEST_POSTGRES_PASSWORD\s*=\s*["']?([^\s"'`#]+)/gi,
    capture: 1,
  },
];

function isSyntheticValue(value) {
  return placeholderValues.test(value) || (value.startsWith('<') && value.endsWith('>')) ||
    /:\/\/[^:\s]+:(?:placeholder|replace-me|unit-test)@(?:127\.0\.0\.1|localhost)(?::|\/)/i.test(value);
}

function isExampleFile(path) {
  const name = basename(path);
  return name === '.env.example' || name.endsWith('.example');
}

function collectFiles(directory, output) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const fullPath = join(directory, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      if (!ignoredDirectories.has(entry.name)) collectFiles(fullPath, output);
    } else if (entry.isFile() && !isExampleFile(fullPath)) {
      output.push(fullPath);
    }
  }
}

export function scanForSecrets(root = REPO_ROOT) {
  const absoluteRoot = resolve(root);
  const files = [];
  for (const directory of ['apps', 'contracts', 'infra', 'tools', 'plans']) {
    const path = join(absoluteRoot, directory);
    if (lstatSync(path).isDirectory()) collectFiles(path, files);
  }
  for (const name of ['.gitignore']) {
    const path = join(absoluteRoot, name);
    try { if (lstatSync(path).isFile()) files.push(path); } catch {}
  }

  const findings = [];
  const ignored = gitIgnoredPaths(absoluteRoot, files);
  for (const path of files.filter((file) => !ignored.has(file))) {
    const content = readFileSync(path).toString('utf8');
    findings.push(...findSecretCandidates(relative(absoluteRoot, path).replaceAll('\\', '/'), content));
  }
  return { scannedFiles: files.length, findings };
}

function gitIgnoredPaths(root, files) {
  const candidates = files.filter((path) => path !== join(root, '.gitignore'));
  if (candidates.length === 0) return new Set();
  const input = Buffer.concat(candidates.flatMap((path) => [
    Buffer.from(relative(root, path).replaceAll('\\', '/')),
    Buffer.from([0]),
  ]));
  const result = spawnSync('git', ['check-ignore', '--stdin', '-z'], {
    cwd: root,
    input,
    windowsHide: true,
  });
  if (result.error || (result.status !== 0 && result.status !== 1)) {
    throw new Error('GIT_IGNORE_SCAN_FAILED');
  }
  return new Set(result.stdout.toString('utf8').split('\0').filter(Boolean).map((path) => resolve(root, path)));
}

function findSecretCandidates(path, content) {
  const findings = [];
  for (const item of patterns) {
    item.pattern.lastIndex = 0;
    let match;
    while ((match = item.pattern.exec(content)) !== null) {
      const value = item.capture ? match[item.capture] : match[0];
      if (item.capture && isSyntheticValue(value)) continue;
      const line = content.slice(0, match.index).split('\n').length;
      findings.push({ path, line, code: item.code });
    }
  }
  return findings;
}

function selfTest() {
  selfTestArgumentParser();
  const candidate = 'database-password-canary-0123456789';
  const shortPassword = 'local-db-password';
  const lines = [
    ['MIGRATION_DATABASE_URL', `postgresql://farmly:${candidate}@127.0.0.1/farmly_test`].join('='),
    ['FARMLY_TEST_POSTGRES_PASSWORD', shortPassword].join('='),
    ['FARMLY_TEST_POSTGRES_PASSWORD', 'replace-with-a-unique-local-only-password'].join('='),
  ];
  const findings = findSecretCandidates('infra/.env', lines.join('\n'));
  const serialized = JSON.stringify(findings);
  if (findings.length !== 2 || serialized.includes(candidate) || serialized.includes(shortPassword) ||
      findings.some((finding) => Object.keys(finding).sort().join(',') !== 'code,line,path')) {
    throw new Error('SECRET_SCANNER_SELF_TEST');
  }
}

await runQaCli({
  gate,
  usage: 'Usage: node tools/qa/check-secrets.mjs --scope source-and-bundles [--json]',
  optionDefinitions: {
    '--scope': { key: 'scope', type: 'value', values: ['source-and-bundles'], required: true },
  },
  run: async () => {
    const scan = scanForSecrets();
    return scan.findings.length
      ? { status: 'FAIL', code: 'SECRET_CANDIDATES_FOUND', productEvidence: false, details: { scannedFiles: scan.scannedFiles, findings: scan.findings } }
      : { status: 'PASS', code: 'NO_SECRET_CANDIDATES_FOUND', productEvidence: false, details: { scannedFiles: scan.scannedFiles } };
  },
  selfTest,
});
