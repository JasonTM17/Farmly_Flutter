import { runQaCli, selfTestArgumentParser } from './cli-support.mjs';

const gate = 'Q-NATIVE';
await runQaCli({
  gate,
  usage: 'Usage: node tools/qa/run-device-journey.mjs --platform android|ios [--json]',
  optionDefinitions: {
    '--platform': { key: 'platform', type: 'value', values: ['android', 'ios'], required: true },
  },
  run: async ({ platform }) => ({
    status: 'NOT_RUN',
    code: 'NATIVE_JOURNEY_IMPLEMENTATION_PENDING',
    productEvidence: false,
    details: { platform, implementationPhase: 'P11' },
  }),
  selfTest: selfTestArgumentParser,
});
