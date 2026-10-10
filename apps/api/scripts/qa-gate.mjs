import { runQaCli, selfTestArgumentParser } from '../../../tools/qa/cli-support.mjs';

const gates = {
  integration: 'Q-API-PG',
  rls: 'Q-RLS',
  sync: 'Q-SYNC',
  'ai-protocol': 'Q-AI-PROTOCOL',
  load: 'Q-LOAD',
};
const rawGateIndex = process.argv.indexOf('--gate');
const rawGate = rawGateIndex < 0 ? undefined : process.argv[rawGateIndex + 1];
const gate = gates[rawGate] ?? 'Q-API-TEST';

await runQaCli({
  gate,
  usage: `Usage: node apps/api/scripts/qa-gate.mjs --gate ${Object.keys(gates).join('|')} [--json]`,
  optionDefinitions: {
    '--gate': { key: 'gateName', type: 'value', values: Object.keys(gates), required: true },
  },
  run: async ({ gateName }) => ({
    status: 'NOT_RUN',
    code: 'PRODUCT_TEST_SLICE_NOT_IMPLEMENTED',
    productEvidence: false,
    details: { gate: gates[gateName], phase: gateName === 'integration' || gateName === 'rls' ? 'P03' : 'future-phase' },
  }),
  selfTest: () => {
    selfTestArgumentParser();
    if (Object.keys(gates).length !== 5 || gates.integration !== 'Q-API-PG') throw new Error('API_GATE_SELF_TEST');
  },
});
