#!/usr/bin/env bash
# Check exein-gate.sh in both directions against fixture VEX files.
set -euo pipefail

cd "$(dirname "$0")"
gate=../scripts/exein-gate.sh
fixtures=fixtures
failures=0

expect() {
	local want="$1" enforce="$2"
	shift 2
	local got=0
	ENFORCE="$enforce" GITHUB_STEP_SUMMARY=/dev/null "$gate" "$@" >/dev/null || got=$?
	if [[ "$got" -ne "$want" ]]; then
		echo "FAIL: ENFORCE=${enforce} $* exited ${got}, want ${want}"
		failures=$((failures + 1))
		return
	fi
	echo "ok:   ENFORCE=${enforce} $* -> ${got}"
}

expect 0 true "${fixtures}/clean-vex.json"
expect 1 true "${fixtures}/vulnerable-vex.json"
expect 1 true "${fixtures}/clean-vex.json" "${fixtures}/vulnerable-vex.json"
expect 0 false "${fixtures}/vulnerable-vex.json"
expect 2 true

exit "$failures"
