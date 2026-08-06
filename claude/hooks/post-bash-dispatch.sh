#!/usr/bin/env bash
# claude/hooks/post-bash-dispatch.sh
#
# Single front-door for PostToolUse:Bash. Claude Code spawns one process per
# registered hook on EVERY Bash tool call, so registering the two independent
# handlers (post-gh-pr-create.sh + plugin-sync.sh) directly meant two spawns
# per Bash call — avg 7647ms / max 12274ms over the WSL<->Windows boundary
# (/doctor, n=15) — for work that almost never matches. This thin dispatcher
# reads stdin + parses the envelope ONCE, then routes to a handler only when
# the command cheaply looks relevant. Common (non-matching) path: 2->1 spawn.
#
# The handlers stay STANDALONE (each still re-filters its own stdin and
# self-exits 0 on a miss), so this dispatcher only has to reject the
# obviously-irrelevant majority — the routing regexes are intentionally loose
# and the handler makes the final call. Handlers are unchanged: their verified
# edge cases (#390 #703 #804 #1072 #1125 #1080) and bats suites pass untouched.
#
# Contract mirrors the handlers: set -u, no-op without jq, always exit 0
# (best-effort — a dispatch hiccup never blocks the user's flow).
#
# Stage timings for the ROUTED path only are appended to
# ${XDG_STATE_HOME:-$HOME/.local/state}/claude/post-bash-dispatch-timing.log
# so a latency regression is measurable instead of guessed (#1258); the
# common non-matching path stays write-free on purpose. Report the log with
# claude/tools/hook-perf-report.sh.
#
# Reference: issue #1144, #1258.
set -u

# Entry stamp. Taken on EVERY invocation, but it is a plain variable read of
# bash 5's EPOCHREALTIME — no fork — so the non-matching majority pays
# nothing. Pre-bash-5 leaves it empty and _pbd_ms falls back (see below).
_t_entry="${EPOCHREALTIME:-}"

# A PostToolUse hook always receives JSON on stdin. If stdin is a terminal the
# script was launched by hand — bail before `cat` blocks forever.
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

# Handlers live beside this dispatcher. POST_BASH_DISPATCH_DIR overrides the
# location for tests (stub handlers that record the routed stdin). The `CDPATH=`
# prefix neutralises a user CDPATH so `cd` cannot resolve elsewhere.
# shellcheck disable=SC1007 # intentional env-prefix: CDPATH= cd ...
DISPATCH_DIR="${POST_BASH_DISPATCH_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"

# --- stage timing (#1258) ---------------------------------------------------
# All three helpers are only ever CALLED from the routed branches below, so the
# non-matching path costs three function definitions and nothing else. Inside
# them, timestamps are taken with plain expansions + `printf -v` rather than
# command substitutions: a `$(…)` fork per stamp would be self-defeating in the
# very code that measures dispatcher overhead.

# Convert an EPOCHREALTIME snapshot ("<sec>.<usec>", locale decimal point) to
# epoch milliseconds, assigned to the variable named by $1. An empty snapshot
# (bash < 5, no EPOCHREALTIME) falls back to GNU `date +%s%3N`; anything that
# still comes out non-numeric is dropped by the reader, so there is no third
# tier here — see claude/tools/hook-perf-report.sh.
_pbd_ms() {
	case "${2:-}" in
	*[.,]*) printf -v "$1" '%s%.3s' "${2%%[.,]*}" "${2#*[.,]}000" ;;
	*) printf -v "$1" '%s' "$(date +%s%3N 2>/dev/null || printf '0')" ;;
	esac
}

# Append `<entry-ms> <pre-invoke-ms> <post-exit-ms> <handler>`. Strictly
# best-effort: every failure path returns 0 so the exit-0 contract holds.
_pbd_log_timing() {
	local _handler="$1" _entry _pre _post _dir _f _lines=()
	_pbd_ms _entry "$_t_entry"
	_pbd_ms _pre "$2"
	_pbd_ms _post "$3"
	_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude"
	_f="$_dir/post-bash-dispatch-timing.log"
	[ -d "$_dir" ] || mkdir -p "$_dir" 2>/dev/null || return 0
	printf '%s %s %s %s\n' "$_entry" "$_pre" "$_post" "$_handler" \
		>>"$_f" 2>/dev/null || return 0
	# Cap growth without rewriting on every routed call: only once the log
	# passes 1000 lines is it trimmed back to the most recent 500. `mapfile`
	# keeps the check a builtin — `wc -l` costs a process on every routed call
	# just to learn that the usual answer is "no trim needed".
	mapfile -t _lines <"$_f" 2>/dev/null || return 0
	if [ "${#_lines[@]}" -gt 1000 ]; then
		printf '%s\n' "${_lines[@]: -500}" >"$_f.tmp" 2>/dev/null &&
			mv -f "$_f.tmp" "$_f" 2>/dev/null
	fi
	return 0
}

# Forward the untouched stdin JSON to one handler and record its stage timings.
# Guarded with `-x` so a missing/non-executable script is a silent no-op
# (best-effort contract) rather than stderr noise + a non-zero pipeline.
_pbd_route() {
	local _h="$1" _pre
	[ -x "$DISPATCH_DIR/$_h" ] || return 0
	_pre="${EPOCHREALTIME:-}"
	printf '%s' "$input" | "$DISPATCH_DIR/$_h"
	_pbd_log_timing "$_h" "$_pre" "${EPOCHREALTIME:-}"
}

# Route on a cheap, deliberately-loose command match; the handler's own filter
# makes the final call. Anchor on a word boundary so an env-var/`command`
# prefix (`FOO=bar gh pr create`) still routes (#390); both regexes use the
# same `(^|[[:space:]])…([[:space:]]|$)` shape for symmetry. `gh pr create` and
# `claude plugin ...` never co-occur in one command, so exclusive routing is
# sufficient. Naming each handler exactly once keeps the routing table, the
# `-x` guard and the timing label from drifting apart.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
	_pbd_route post-gh-pr-create.sh
elif printf '%s' "$cmd" | grep -qE '(^|[[:space:]])claude[[:space:]]+plugin([[:space:]]|$)'; then
	_pbd_route plugin-sync.sh
fi

exit 0
