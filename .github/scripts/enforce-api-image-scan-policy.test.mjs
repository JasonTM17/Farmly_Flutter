import assert from 'node:assert/strict';
import test from 'node:test';
import {
  evaluateScanPolicy,
  verifyPodTextAbsentInImage,
} from './enforce-api-image-scan-policy.mjs';

const exceptionTag = 'api-v0.1.0-preview.1';

const clearedPodTextFinding = {
  VulnerabilityID: 'CVE-2026-82560',
  PkgName: 'perl-base',
  InstalledVersion: '5.40.1-6+deb13u1',
  Severity: 'UNKNOWN',
};

function reportWith({ high = 0, critical = 0, unknown = 0, findings = [] } = {}) {
  const vulnerabilities = [
    ...Array.from({ length: high }, () => ({ Severity: 'HIGH' })),
    ...Array.from({ length: critical }, () => ({ Severity: 'CRITICAL' })),
    ...Array.from({ length: unknown }, (_, index) => ({
      VulnerabilityID: `CVE-2026-${90000 + index}`,
      Severity: 'UNKNOWN',
    })),
    ...findings,
  ];
  return {
    Results: [{
      Target: 'farmly-api:test (debian 13.7)',
      Type: 'debian',
      Vulnerabilities: vulnerabilities,
    }],
  };
}

function evaluate(report, tag = exceptionTag, highLimit = 43, podTextAbsenceVerified = false) {
  return evaluateScanPolicy({ report, tag, exceptionTag, highLimit, podTextAbsenceVerified });
}

test('allows the exact preview tag at its accepted HIGH cap with no CRITICAL findings', () => {
  assert.deepEqual(evaluate(reportWith({ high: 43 })), {
    high: 43,
    critical: 0,
    unknown: 0,
    clearedUnknown: 0,
    unresolvedUnknown: 0,
    allowed: true,
    exceptionUsed: true,
    podTextClearanceUsed: false,
  });
});

test('blocks the accepted preview tag above its HIGH cap', () => {
  assert.equal(evaluate(reportWith({ high: 44 })).allowed, false);
});

test('blocks the accepted preview tag if any CRITICAL finding appears', () => {
  assert.equal(evaluate(reportWith({ high: 43, critical: 1 })).allowed, false);
});

test('blocks unknown severities without an exact-image clearance match', () => {
  const policy = evaluate(reportWith({ high: 43, unknown: 1 }), exceptionTag, 43, true);
  assert.equal(policy.allowed, false);
  assert.equal(policy.unresolvedUnknown, 1);
});

test('clears only the exact reviewed Pod::Text finding after the runtime probe passes', () => {
  const policy = evaluate(
    reportWith({ high: 43, findings: [clearedPodTextFinding] }),
    exceptionTag,
    43,
    true,
  );
  assert.deepEqual(policy, {
    high: 43,
    critical: 0,
    unknown: 1,
    clearedUnknown: 1,
    unresolvedUnknown: 0,
    allowed: true,
    exceptionUsed: true,
    podTextClearanceUsed: true,
  });
});

test('blocks the reviewed finding when runtime absence evidence is missing', () => {
  const policy = evaluate(reportWith({ findings: [clearedPodTextFinding] }));
  assert.equal(policy.allowed, false);
  assert.equal(policy.unresolvedUnknown, 1);
});

test('blocks a known CVE if its package, version, or target differs from the review', () => {
  for (const finding of [
    { ...clearedPodTextFinding, PkgName: 'perl-modules-5.40' },
    { ...clearedPodTextFinding, InstalledVersion: '5.40.1-6+deb13u2' },
  ]) {
    assert.equal(
      evaluate(reportWith({ findings: [finding] }), exceptionTag, 43, true).allowed,
      false,
    );
  }
  const otherTarget = reportWith({ findings: [clearedPodTextFinding] });
  otherTarget.Results[0].Target = 'farmly-api:test (debian 14.0)';
  assert.equal(evaluate(otherTarget, exceptionTag, 43, true).allowed, false);
});

test('blocks duplicate and additional UNKNOWN findings even after the Pod::Text probe', () => {
  assert.equal(
    evaluate(
      reportWith({ findings: [clearedPodTextFinding, clearedPodTextFinding] }),
      exceptionTag,
      43,
      true,
    ).allowed,
    false,
  );
  assert.equal(
    evaluate(
      reportWith({ unknown: 1, findings: [clearedPodTextFinding] }),
      exceptionTag,
      43,
      true,
    ).allowed,
    false,
  );
});

test('keeps every other release tag strict', () => {
  assert.equal(evaluate(reportWith({ high: 1 }), 'api-v0.1.0-preview.2').allowed, false);
  assert.equal(
    evaluate(
      reportWith({ findings: [clearedPodTextFinding] }),
      'api-v0.1.0-preview.2',
      43,
      true,
    ).allowed,
    false,
  );
});

test('allows clean scans for any release tag without using the exception', () => {
  assert.deepEqual(evaluate(reportWith(), 'api-v0.1.0-preview.2'), {
    high: 0,
    critical: 0,
    unknown: 0,
    clearedUnknown: 0,
    unresolvedUnknown: 0,
    allowed: true,
    exceptionUsed: false,
    podTextClearanceUsed: false,
  });
});

test('verifies Pod::Text absence inside the exact tagged image and fails closed', () => {
  let invoked;
  assert.equal(
    verifyPodTextAbsentInImage('farmly-api:verify', (command, args, options) => {
      invoked = { command, args, options };
      return 'Pod::Text absence verified.\n';
    }),
    true,
  );
  assert.equal(invoked.command, 'docker');
  assert.deepEqual(invoked.args.slice(0, 5), [
    'run',
    '--rm',
    '--entrypoint',
    'sh',
    'farmly-api:verify',
  ]);
  assert.throws(
    () => verifyPodTextAbsentInImage('farmly-api:verify', () => ''),
    /absence verification marker/,
  );
  assert.throws(() => verifyPodTextAbsentInImage(''), /IMAGE is required/);
});

test('fails closed for a malformed Trivy report', () => {
  assert.throws(() => evaluate({ Results: 'invalid' }), /Results array/);
  assert.throws(() => evaluate({ Results: [{ Vulnerabilities: {} }] }), /must be an array/);
  assert.throws(() => evaluate(reportWith(), exceptionTag, -1), /non-negative integer/);
});
