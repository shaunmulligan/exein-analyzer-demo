#!/usr/bin/env bash
# Fail when any VEX file has an exploitable high or critical CVE.
#
# Usage: exein-gate.sh <service>-vex.json ...
# Env:   ENFORCE              "false" reports without failing (default: true)
#        GITHUB_STEP_SUMMARY  markdown summary target (default: stdout)
#
# A CVE counts when any of its ratings is high or critical and Exein's VEX
# analysis does not mark it as not affected, a false positive, or resolved.
set -euo pipefail

enforce="${ENFORCE:-true}"

if [[ $# -eq 0 ]]; then
	echo "usage: $0 <service>-vex.json ..." >&2
	exit 2
fi

# shellcheck disable=SC2016 # jq program, not shell.
readonly BLOCKING_FILTER='
	[.vulnerabilities[]?
	 | select((.analysis.state // "") as $s
	          | ["not_affected", "false_positive", "resolved"] | index($s) | not)
	 | select(any(.ratings[]?; (.severity // "" | ascii_downcase) as $s
	              | ["critical", "high"] | index($s)))
	 | .id]
	| unique'

# fd 3 is the markdown summary.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	exec 3>>"$GITHUB_STEP_SUMMARY"
else
	exec 3>&1
fi

total_blocking=0
{
	echo "### Exein CVE gate"
	echo
	echo "| Service | High/critical | All CVEs |"
	echo "|---|---:|---:|"
} >&3

for vex in "$@"; do
	service="$(basename "$vex" -vex.json)"
	blocking="$(jq -r "${BLOCKING_FILTER} | length" "$vex")"
	all="$(jq '[.vulnerabilities[]?.id] | unique | length' "$vex")"
	total_blocking=$((total_blocking + blocking))
	echo "| ${service} | ${blocking} | ${all} |" >&3
	if [[ "$blocking" -gt 0 ]]; then
		echo "::group::${service}: ${blocking} high/critical CVEs"
		jq -r "${BLOCKING_FILTER} | .[]" "$vex"
		echo "::endgroup::"
	fi
done

echo >&3

if [[ "$total_blocking" -eq 0 ]]; then
	echo "**Pass:** no high or critical CVEs." >&3
	exit 0
fi

if [[ "$enforce" != "true" ]]; then
	echo "**Warning:** ${total_blocking} high/critical CVEs. Enforcement is off; deploy continues." >&3
	exit 0
fi

echo "**Blocked:** ${total_blocking} high/critical CVEs. Deploy cancelled." >&3
echo "::error::Exein found ${total_blocking} high/critical CVEs. Deploy cancelled."
exit 1
