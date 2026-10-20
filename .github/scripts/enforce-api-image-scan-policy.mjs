import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const allowedSeverities = new Set(['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN']);
const podTextClearance = {
  vulnerabilityId: 'CVE-2026-82560',
  packageName: 'perl-base',
  installedVersion: '5.40.1-6+deb13u1',
  packageType: 'debian',
  targetSuffix: '(debian 13.7)',
};
const podTextProbeMarker = 'Pod::Text absence verified.';
const podTextProbe = `set -eu
command -v perl >/dev/null 2>&1 || { echo 'Perl is missing from the scanned image.' >&2; exit 1; }
perl -e 'exit 0'
perl -e 'for my $dir (@INC) { my $path = "$dir/Pod/Text.pm"; if (-f $path) { print STDERR "Pod::Text module found: $path\\n"; exit 1; } }'
if output="$(perl -MPod::Text -e 1 2>&1)"; then
  echo 'Pod::Text is importable in the scanned image.' >&2
  exit 1
fi
case "$output" in
  *"Can't locate Pod/Text.pm"*) printf '%s\\n' '${podTextProbeMarker}' ;;
  *) printf 'Unexpected Pod::Text probe failure: %s\\n' "$output" >&2; exit 1 ;;
esac`;

export function verifyPodTextAbsentInImage(image, runDocker = execFileSync) {
  if (typeof image !== 'string' || image.trim() === '') {
    throw new TypeError('IMAGE is required to verify the scanned runtime image.');
  }

  const output = runDocker(
    'docker',
    ['run', '--rm', '--entrypoint', 'sh', image, '-ec', podTextProbe],
    { encoding: 'utf8' },
  );
  if (!output.includes(podTextProbeMarker)) {
    throw new Error('The runtime image did not produce the Pod::Text absence verification marker.');
  }
  return true;
}

function isClearedPodTextFinding(result, finding) {
  return (
    result?.Type === podTextClearance.packageType &&
    typeof result?.Target === 'string' &&
    result.Target.endsWith(podTextClearance.targetSuffix) &&
    finding?.VulnerabilityID === podTextClearance.vulnerabilityId &&
    finding?.PkgName === podTextClearance.packageName &&
    finding?.InstalledVersion === podTextClearance.installedVersion
  );
}

export function evaluateScanPolicy({
  report,
  tag,
  exceptionTag,
  highLimit,
  podTextAbsenceVerified = false,
}) {
  if (!report || !Array.isArray(report.Results)) {
    throw new TypeError('Trivy report must contain a Results array.');
  }
  if (typeof tag !== 'string' || typeof exceptionTag !== 'string') {
    throw new TypeError('Release tag and exception tag must be strings.');
  }
  if (!Number.isSafeInteger(highLimit) || highLimit < 0) {
    throw new TypeError('The HIGH finding cap must be a non-negative integer.');
  }

  const counts = { high: 0, critical: 0, unknown: 0 };
  const unknownFindings = [];
  for (const result of report.Results) {
    const vulnerabilities = result?.Vulnerabilities ?? [];
    if (!Array.isArray(vulnerabilities)) {
      throw new TypeError('Trivy result Vulnerabilities must be an array.');
    }

    for (const finding of vulnerabilities) {
      const severity = finding?.Severity;
      if (!allowedSeverities.has(severity)) {
        throw new TypeError('Trivy finding has a missing or unsupported severity.');
      }
      if (severity === 'HIGH') counts.high += 1;
      if (severity === 'CRITICAL') counts.critical += 1;
      if (severity === 'UNKNOWN') {
        counts.unknown += 1;
        unknownFindings.push({ result, finding });
      }
    }
  }

  const clean = counts.high === 0 && counts.critical === 0 && counts.unknown === 0;
  const clearedPodTextFindingCount = unknownFindings.filter(({ result, finding }) =>
    isClearedPodTextFinding(result, finding),
  ).length;
  const podTextClearanceUsed =
    tag === exceptionTag &&
    podTextAbsenceVerified === true &&
    unknownFindings.length === 1 &&
    clearedPodTextFindingCount === 1;
  const unresolvedUnknown = counts.unknown - (podTextClearanceUsed ? 1 : 0);
  const exceptionUsed =
    tag === exceptionTag &&
    counts.high <= highLimit &&
    counts.critical === 0 &&
    unresolvedUnknown === 0 &&
    (counts.high > 0 || podTextClearanceUsed);

  return {
    ...counts,
    clearedUnknown: podTextClearanceUsed ? 1 : 0,
    unresolvedUnknown,
    allowed: clean || exceptionUsed,
    exceptionUsed,
    podTextClearanceUsed,
  };
}

function main() {
  const reportPath = process.env.TRIVY_REPORT_PATH;
  if (!reportPath) throw new Error('TRIVY_REPORT_PATH is required.');

  const report = JSON.parse(readFileSync(reportPath, 'utf8'));
  const tag = process.env.GITHUB_REF_NAME;
  const exceptionTag = process.env.PREVIEW_EXCEPTION_TAG;
  const hasUnknownFinding = Array.isArray(report?.Results) && report.Results.some((result) =>
    Array.isArray(result?.Vulnerabilities) &&
    result.Vulnerabilities.some((finding) => finding?.Severity === 'UNKNOWN'),
  );
  const podTextAbsenceVerified =
    tag === exceptionTag && hasUnknownFinding
      ? verifyPodTextAbsentInImage(process.env.IMAGE)
      : false;
  const policy = evaluateScanPolicy({
    report,
    tag,
    exceptionTag,
    highLimit: Number(process.env.PREVIEW_HIGH_LIMIT),
    podTextAbsenceVerified,
  });

  const summary = `Trivy HIGH: ${policy.high}; CRITICAL: ${policy.critical}; UNKNOWN: ${policy.unknown}; cleared exact-image UNKNOWN: ${policy.clearedUnknown}; unresolved UNKNOWN: ${policy.unresolvedUnknown}.`;
  console.log(summary);

  if (!policy.allowed) {
    console.error(
      `${process.env.GITHUB_REF_NAME} is blocked by the vulnerability policy; the one-time preview exception does not apply.`,
    );
    process.exitCode = 1;
    return;
  }

  if (policy.exceptionUsed) {
    const clearance = policy.podTextClearanceUsed
      ? ` The single UNKNOWN report for ${podTextClearance.vulnerabilityId} on ${podTextClearance.packageName}@${podTextClearance.installedVersion} was cleared as not applicable after the runtime image passed the Pod::Text absence probe.`
      : '';
    const accepted = `One-time user-authorized preview exception for ${process.env.GITHUB_REF_NAME}: accepted ${policy.high} HIGH findings (cap: ${process.env.PREVIEW_HIGH_LIMIT}), ${policy.critical} CRITICAL, ${policy.unknown} UNKNOWN, and ${policy.unresolvedUnknown} unresolved UNKNOWN.${clearance} The full unfiltered Trivy JSON is attached as a workflow artifact. This image is preview-only.`;
    console.warn(accepted);
    if (process.env.GITHUB_STEP_SUMMARY) {
      appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n> **Security exception:** ${accepted}\n`);
    }
    return;
  }

  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n${summary}\n`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
