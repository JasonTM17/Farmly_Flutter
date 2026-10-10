import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { QaCliError, runQaCli, selfTestArgumentParser } from '../qa/cli-support.mjs';

const execFileAsync = promisify(execFile);
const REPO_ROOT = fileURLToPath(new URL('../../', import.meta.url));
const DATASET_PATH = new URL('./farmly-chatbot-v1.json', import.meta.url);

const gate = 'Q-LIVE-AI';
await runQaCli({
  gate,
  usage:
    'Usage: node tools/eval/run-chatbot-eval.mjs --suite chatbot-v1 --mode protocol|live ' +
    '[--require-approved-budget] [--protocol-report <path>] [--json]',
  optionDefinitions: {
    '--suite': { key: 'suite', type: 'value', values: ['chatbot-v1'], required: true },
    '--mode': { key: 'mode', type: 'value', values: ['protocol', 'simulated', 'live'], required: true },
    '--require-approved-budget': { key: 'requireApprovedBudget', type: 'boolean' },
    '--protocol-report': { key: 'protocolReport', type: 'value' },
  },
  run: async ({ mode, requireApprovedBudget, protocolReport }) => {
    const dataset = JSON.parse(await readFile(DATASET_PATH, 'utf8'));
    const datasetHash = createHash('sha256').update(JSON.stringify(dataset)).digest('hex');

    if (mode === 'live') {
      if (!requireApprovedBudget) throw new QaCliError('LIVE_BUDGET_FLAG_REQUIRED');
      const budgetReady =
        process.env.FARMLY_LIVE_AI_APPROVED === 'true' &&
        Boolean(process.env.DEEPSEEK_API_KEY) &&
        Boolean(process.env.AI_PROJECT_COST_CAP) &&
        Boolean(process.env.AI_MAX_CALLS);
      if (!budgetReady) {
        return {
          status: 'BLOCKED_CAPABILITY',
          code: 'LIVE_AI_BUDGET_OR_CREDENTIAL_MISSING',
          productEvidence: false,
          details: { providerRequests: 0, datasetHash },
        };
      }
      // Approved budget exists, but semantic grading still needs the frozen
      // live harness + independent grader loop — reported honestly.
      return {
        status: 'NOT_RUN',
        code: 'LIVE_EVAL_PENDING_INDEPENDENT_GRADER',
        productEvidence: false,
        details: { datasetHash, level: 'L', pendingCases: dataset.cases.filter((c) => c.level.includes('L')).length },
      };
    }

    // Protocol mode: execute the deterministic suite inside the isolated
    // api-runner and map each suite case onto the FAI cases it proves.
    const report = protocolReport
      ? JSON.parse(await readFile(protocolReport, 'utf8'))
      : await runProtocolSuite();
    if (!report || !Array.isArray(report.cases)) {
      return {
        status: 'BLOCKED_CAPABILITY',
        code: 'PROTOCOL_SUITE_UNAVAILABLE',
        productEvidence: false,
        details: { datasetHash },
      };
    }
    const caseStatus = new Map(report.cases.map((c) => [String(c.case), c]));
    const receipts = dataset.cases.map((faiCase) => {
      const probe = faiCase.oracle?.protocolCase;
      if (!probe) {
        return {
          case: faiCase.id,
          level: faiCase.level,
          status: 'NOT_RUN',
          reason: 'LIVE_LEVEL_ONLY',
          critical: faiCase.critical,
        };
      }
      const evidence = caseStatus.get(probe);
      return {
        case: faiCase.id,
        level: faiCase.level,
        protocolCase: probe,
        status: evidence ? (evidence.status === 'passed' ? 'PASS' : 'FAIL') : 'NOT_RUN',
        reason: evidence ? undefined : 'PROBE_MISSING_FROM_SUITE',
        critical: faiCase.critical,
        vetoes: faiCase.vetoes,
      };
    });
    const failed = receipts.filter((r) => r.status === 'FAIL');
    const criticalFailed = failed.filter((r) => r.critical);
    return {
      status: failed.length === 0 ? 'PASS' : 'FAIL',
      code: failed.length === 0 ? 'CHATBOT_PROTOCOL_SUITE_GREEN' : 'CHATBOT_PROTOCOL_CASES_FAILED',
      productEvidence: failed.length === 0,
      details: {
        datasetHash,
        protocolSuite: { passed: report.passed, failed: report.failed },
        protocolCasesCovered: receipts.filter((r) => r.protocolCase).length,
        liveOnlyCases: receipts.filter((r) => !r.protocolCase).length,
        criticalFailures: criticalFailed.map((r) => r.case),
        receipts,
      },
    };
  },
  selfTest: selfTestArgumentParser,
});

async function runProtocolSuite() {
  try {
    const { stdout } = await execFileAsync(
      'docker',
      [
        'compose', '-f', 'infra/compose.yaml', 'run', '--rm', 'api-runner',
        'node', 'test/integration/ai-protocol.mjs',
      ],
      { cwd: REPO_ROOT, maxBuffer: 8 * 1024 * 1024, timeout: 600_000 },
    );
    return extractReport(stdout);
  } catch (error) {
    return extractReport(error.stdout);
  }
}

function extractReport(stdout) {
  if (typeof stdout !== 'string' || !stdout.includes('"cases"')) return null;
  const marker = stdout.indexOf('{\n  "suite":');
  if (marker < 0) return null;
  try {
    return JSON.parse(stdout.slice(marker));
  } catch {
    return null;
  }
}
