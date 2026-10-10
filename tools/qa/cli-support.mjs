import { fileURLToPath } from 'node:url';

export const REPO_ROOT = fileURLToPath(new URL('../../', import.meta.url));

export class QaCliError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

export function parseQaArgs(argv, optionDefinitions = {}) {
  const options = { help: false, selfTest: false, json: false };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--help' || token === '-h') {
      options.help = true;
      continue;
    }
    if (token === '--self-test') {
      options.selfTest = true;
      continue;
    }
    if (token === '--json') {
      options.json = true;
      continue;
    }
    const definition = optionDefinitions[token];
    if (!definition) throw new QaCliError('ARG_UNKNOWN');
    if (seen.has(token)) throw new QaCliError('ARG_DUPLICATE');
    seen.add(token);
    if (definition.type === 'boolean') {
      options[definition.key] = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) throw new QaCliError('ARG_VALUE');
    if (definition.values && !definition.values.includes(value)) throw new QaCliError('ARG_VALUE');
    options[definition.key] = value;
    index += 1;
  }
  if (!options.help && !options.selfTest) {
    for (const definition of Object.values(optionDefinitions)) {
      if (definition.required && options[definition.key] === undefined) throw new QaCliError('ARG_REQUIRED');
    }
  }
  return options;
}

export function emitQaResult(gate, result, json = false) {
  const record = {
    gate,
    status: result.status,
    code: result.code,
    productEvidence: result.productEvidence === true,
    ...(result.details ? { details: result.details } : {}),
  };
  if (json) console.log(JSON.stringify(record));
  else console.log(`${record.status} ${gate}: ${record.code}`);
  if (record.status !== 'PASS') process.exitCode = 2;
}

export async function runQaCli({ gate, usage, optionDefinitions = {}, run, selfTest }) {
  let options;
  try {
    options = parseQaArgs(process.argv.slice(2), optionDefinitions);
    if (options.help) {
      console.log(usage);
      return;
    }
    if (options.selfTest) {
      selfTest?.();
      emitQaResult(gate, { status: 'PASS', code: 'CLI_SELF_TEST_ONLY', productEvidence: false }, options.json);
      return;
    }
    emitQaResult(gate, await run(options), options.json);
  } catch (error) {
    const code = error instanceof QaCliError ? error.code : 'QA_COMMAND_FAILED';
    emitQaResult(gate, { status: 'FAIL', code, productEvidence: false }, options?.json === true || process.argv.includes('--json'));
  }
}

export function selfTestArgumentParser() {
  const options = parseQaArgs(['--platform', 'android', '--json'], {
    '--platform': { key: 'platform', type: 'value', values: ['android', 'ios'], required: true },
  });
  if (options.platform !== 'android' || !options.json) throw new Error('CLI_SELF_TEST');
  for (const args of [['--platform', 'windows'], ['--unknown'], ['--platform']]) {
    let rejected = false;
    try {
      parseQaArgs(args, { '--platform': { key: 'platform', type: 'value', values: ['android', 'ios'], required: true } });
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('CLI_SELF_TEST');
  }
}
