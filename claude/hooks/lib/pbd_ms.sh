#!/usr/bin/env bash
# claude/hooks/lib/pbd_ms.sh
#
# Pure function library: defines _pbd_ms and nothing else. No top-level side
# effects (no stdin read, no exit, no output), so it is safe to `source` from
# both post-bash-dispatch.sh and a bats test.
#
# Extracted verbatim from post-bash-dispatch.sh (#1258) for exactly that
# reason: the dispatcher is a top-to-bottom script that reads stdin and calls
# `exit` early, so sourcing it to reach _pbd_ms is impossible — which left the
# BSD-date fallback tier below untestable, and it silently regressed once
# (a /simplify pass deleted the tier; it had to be restored by hand).
# Coverage now lives in tests/bats/skills/pbd_ms_lib.bats.

# Convert an EPOCHREALTIME snapshot ("<sec>.<usec>", locale decimal point) to
# epoch milliseconds, assigned to the variable named by $1. An empty snapshot
# (bash < 5, no EPOCHREALTIME) falls back to GNU `date +%s%3N`, and to
# whole-second granularity when that prints the literal `%N` (BSD date) —
# without this tier a BSD host would silently lose the whole timing row
# (the reader drops any non-numeric field), not just precision.
_pbd_ms() {
	local _d
	case "${2:-}" in
	*[.,]*) printf -v "$1" '%s%.3s' "${2%%[.,]*}" "${2#*[.,]}000" ;;
	*)
		_d=$(date +%s%3N 2>/dev/null) || _d=""
		case "$_d" in
		'' | *[!0-9]*) _d="$(date +%s 2>/dev/null || printf '0')000" ;;
		esac
		printf -v "$1" '%s' "$_d"
		;;
	esac
}
