#!/bin/sh
# scripts/test_smoke.sh — pre-push Layer 0 smoke (`mise run test-smoke`, #2046)
#
# Runs in the order below, against the files changed in the given git
# range(s), under one time budget:
#   1. `bash -n` on changed *.sh / *.bash, `zsh -n` on changed *.zsh
#   2. `pytest -m smoke` (a handful of shell-load / help-interface tests)
#   3. only the bats files mapped from the changed paths (none -> skipped)
#
# Mapping: a changed file's stem (basename minus extension, '-' -> '_')
# selects every tests/bats/**/*.bats whose stem (minus a leading `test_`)
# equals it or is a `_`-separated prefix of it, either way round:
#   shell-common/functions/gcp_scan.sh -> tests/bats/functions/gcp.bats
#   git/hooks/pre-push                -> tests/bats/git/test_pre_push_pytest.bats
# A changed .bats file selects itself. *.md never maps.
#
# Usage: scripts/test_smoke.sh [<git-range>...]
#   Ranges default to $PRE_PUSH_SMOKE_RANGES (whitespace-separated), then
#   `@{upstream}..HEAD`, then `HEAD^!`.
# Env:
#   PRE_PUSH_SMOKE_BUDGET  seconds (default 60). When exhausted the remaining
#                          stages are skipped with a warning — exit 0, not a
#                          failure (the full suite runs in CI). A bats `not ok`
#                          printed before the cut still fails.
#   SMOKE_BATS / SMOKE_PYTEST  command overrides (tests).
# Exit: 0 clean or budget-skipped, 1 syntax error / bats or pytest failure.

ROOT=$(git rev-parse --show-toplevel) || exit 1
cd "$ROOT" || exit 1

BUDGET=${PRE_PUSH_SMOKE_BUDGET:-60}
BATS=${SMOKE_BATS:-./tests/bats/lib/bats-core/bin/bats}
PYTEST=${SMOKE_PYTEST:-uv run pytest -m smoke -q -p no:cacheprovider}
START=$(date +%s)
fail=0

log() { printf '[pre-push smoke] %s\n' "$*" >&2; }

skip_rest() {
    log "WARN: ${BUDGET}s budget exhausted — skipped $1 (full suite: PRE_PUSH_FULL_TEST=1 git push, or CI)"
    exit "$fail"
}

# run_capped <cmd...> — run under the remaining budget. Returns 124 (as
# `timeout` does) when the budget is gone, before or during the command;
# callers then skip_rest — a warning, not a failure.
run_capped() {
    left=$((BUDGET - $(date +%s) + START))
    [ "$left" -gt 0 ] || return 124
    if command -v timeout >/dev/null 2>&1; then
        timeout "$left" "$@"
    else
        "$@"
    fi
}

# shellcheck disable=SC2086 # whitespace-separated list, split on purpose
[ $# -gt 0 ] || set -- ${PRE_PUSH_SMOKE_RANGES:-}
if [ $# -eq 0 ]; then
    if git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
        set -- '@{upstream}..HEAD'
    else
        set -- 'HEAD^!'
    fi
fi

files=$(for range in "$@"; do git log --format= --name-only "$range" --; done | sort -u)
log "range: $* ($(printf '%s' "$files" | grep -c .) changed files)"

# 1. syntax
while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in
    *.sh | *.bash) bash -n "$f" || {
        log "FAIL: bash -n $f"
        fail=1
    } ;;
    *.zsh) if command -v zsh >/dev/null 2>&1; then
        zsh -n "$f" || {
            log "FAIL: zsh -n $f"
            fail=1
        }
    fi ;;
    esac
done <<EOF
$files
EOF

# 2. pytest -m smoke (~5s) — ahead of bats so a slow bats file cannot
#    starve it. rc 5 = no tests collected, not a failure.
if [ -z "${SMOKE_PYTEST:-}" ] && ! command -v uv >/dev/null 2>&1; then
    log "pytest: uv unavailable — skipped"
else
    log "pytest -m smoke"
    # shellcheck disable=SC2086 # command string, split on purpose
    run_capped $PYTEST </dev/null
    rc=$?
    [ "$rc" -eq 124 ] && skip_rest "pytest -m smoke and bats"
    [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ] || fail=1
fi

# 3. mapped bats — exact stem matches first, prefix matches after.
selected=$(printf '%s\n' "$files" | CANDS=$(git ls-files 'tests/bats/*.bats' |
    grep -v -e '^tests/bats/lib/' -e '^tests/bats/_fixtures/') awk '
function stem(p, n) { n = p; sub(/.*\//, "", n); sub(/\.[^.]*$/, "", n); gsub(/-/, "_", n); return n }
BEGIN { nc = split(ENVIRON["CANDS"], C, "\n")
        for (i = 1; i <= nc; i++) { R[i] = stem(C[i]); S[i] = R[i]; sub(/^test_/, "", S[i]) } }
$0 == "" || /\.md$/ { next }
{ s = stem($0)
  for (i = 1; i <= nc; i++) {
      if (C[i] in seen) continue
      if (s == S[i] || s == R[i]) { seen[C[i]] = 1; print C[i] }
      else if (index(s, S[i] "_") == 1 || index(S[i], s "_") == 1 || index(R[i], s "_") == 1) {
          seen[C[i]] = 1; later[++nl] = C[i] } } }
END { for (i = 1; i <= nl; i++) print later[i] }')

if [ -z "$selected" ]; then
    log "bats: no mapped files — skipped"
else
    out=$(mktemp) || exit 1
    trap 'rm -f "$out" "$out.rc"' EXIT
    while IFS= read -r b; do
        log "bats $b"
        # tee the TAP stream: a `not ok` printed before a budget cut still
        # fails the push (the subshell's rc lands in $out.rc).
        {
            run_capped "$BATS" "$b" </dev/null
            echo $? >"$out.rc"
        } 2>&1 | tee "$out"
        grep -q '^not ok' "$out" && fail=1
        rc=$(cat "$out.rc")
        [ "$rc" -eq 124 ] && skip_rest "bats from $b on"
        [ "$rc" -eq 0 ] || fail=1
    done <<EOF
$selected
EOF
fi

[ "$fail" -eq 0 ] && log "OK ($(($(date +%s) - START))s)"
exit "$fail"
