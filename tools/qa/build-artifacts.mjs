import { QaCliError, runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-ARTIFACT';
await runQaCli({
  gate,
  usage: 'Usage: node tools/qa/build-artifacts.mjs --local-only [--json]',
  optionDefinitions: { '--local-only': { key: 'localOnly', type: 'boolean', required: true } },
  run: async ({ localOnly }) => {
    if (!localOnly) throw new QaCliError('LOCAL_ONLY_REQUIRED');
    return {
      status: 'NOT_RUN',
      code: 'ARTIFACT_BUILDER_IMPLEMENTATION_PENDING',
      productEvidence: false,
      details: { publicationAttempted: false, implementationPhase: 'P12' },
    };
  },
  selfTest: selfTestArgumentParser,
});
