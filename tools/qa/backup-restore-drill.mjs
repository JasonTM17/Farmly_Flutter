import { QaCliError, runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-RESTORE';
const options = { '--isolated-only': { key: 'isolatedOnly', type: 'boolean', required: true } };
await runQaCli({
  gate,
  usage: 'Usage: node tools/qa/backup-restore-drill.mjs --isolated-only [--json]',
  optionDefinitions: options,
  run: async ({ isolatedOnly }) => {
    if (!isolatedOnly) throw new QaCliError('ISOLATED_ONLY_REQUIRED');
    return {
      status: 'BLOCKED_CAPABILITY',
      code: 'ISOLATED_RESTORE_TARGET_NOT_CONFIGURED',
      productEvidence: false,
      details: { databaseTouched: false, implementationPhase: 'P11' },
    };
  },
  selfTest: () => {
    selfTestArgumentParser();
    const env = { databaseName: 'postgres', projectName: 'student-management' };
    if (isFarmlyQaDatabase(env.databaseName, env.projectName)) throw new Error('RESTORE_SCOPE_SELF_TEST');
    if (!isFarmlyQaDatabase('farmly_test_261005', 'farmly-test-261005')) throw new Error('RESTORE_SCOPE_SELF_TEST');
    if (!isFarmlyQaDatabase('farmly_restore_261005', 'farmly-restore-261005')) throw new Error('RESTORE_SCOPE_SELF_TEST');
    if (isFarmlyQaDatabase('farmly_test_261005', 'farmly-restore-261005')) throw new Error('RESTORE_SCOPE_SELF_TEST');
    if (isFarmlyQaDatabase('farmly_test_261005', 'farmly-test-999999')) throw new Error('RESTORE_SCOPE_SELF_TEST');
  },
});

export function isFarmlyQaDatabase(databaseName, projectName) {
  const database = databaseName.match(/^farmly_(test|restore)_([a-z0-9_-]+)$/i);
  const project = projectName.match(/^farmly-(test|restore)-([a-z0-9-]+)$/i);
  if (!database || !project) return false;

  return database[1].toLowerCase() === project[1].toLowerCase() &&
    database[2].replaceAll('_', '-').toLowerCase() === project[2].toLowerCase();
}
