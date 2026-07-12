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
# Reference: issue #1144.
set -u

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

# Route on a cheap, deliberately-loose command match; the handler's own filter
# makes the final call. Anchor on a word boundary so an env-var/`command`
# prefix (`FOO=bar gh pr create`) still routes (#390). `gh pr create` and
# `claude plugin ...` never co-occur in one command, so exclusive routing is
# sufficient — and forwards the untouched stdin JSON the handler expects.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
	printf '%s' "$input" | "$DISPATCH_DIR/post-gh-pr-create.sh"
elif printf '%s' "$cmd" | grep -qE '(^|[[:space:]])claude[[:space:]]+plugin[[:space:]]'; then
	printf '%s' "$input" | "$DISPATCH_DIR/plugin-sync.sh"
fi

exit 0
