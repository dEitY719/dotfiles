#!/usr/bin/env bash
# git/hooks/checks/run_all.sh — whole-file mode for the pre-commit checks (#2149)
#
# Usage: git/hooks/checks/run_all.sh <repo-relative-file>...
#
# Applies every registered per-file / per-shell-file check (the same
# *_check.sh modules git/hooks/pre-commit loads) to the given files, judging
# the whole file instead of the staged diff (CHECK_MODE=all). Global checks
# are skipped: they judge the staged set itself. Every finding, blocking or
# warning, is keyed `<check_name>:<path>`; keys listed in baseline.txt are
# known legacy violations and do not fail. Silent and exit 0 when every key
# is in it; otherwise prints the new keys and exits 1.
# Contract: git/doc/CHECK_REGISTRY.md.

CHECKS_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$CHECKS_DIR/../../.." && pwd)"
BASELINE="$CHECKS_DIR/baseline.txt"
export CHECK_MODE=all
# The shellcheck check takes paths relative to the repo root.
cd "$REPO_ROOT" || exit 1

# shellcheck source=/dev/null
. "$CHECKS_DIR/shared.sh" || exit 1
names=()
for check_file in "$CHECKS_DIR"/*_check.sh; do
    unset CHECK_NAME CHECK_SCOPE
    unset -f check_run
    # shellcheck source=/dev/null
    . "$check_file" || exit 1
    case "${CHECK_SCOPE:-}" in per-file | per-shell-file) ;; *) continue ;; esac
    eval "check_run__${CHECK_NAME}() $(declare -f check_run | tail -n +2)"
    names+=("$CHECK_NAME:$CHECK_SCOPE")
done

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/run_all.XXXXXX") || exit 1
trap 'rm -rf "$tmpdir"' EXIT
found="$tmpdir/found"
: >"$found"
for entry in "${names[@]}"; do : >"$tmpdir/${entry%%:*}.out"; done
for file in "$@"; do
    for entry in "${names[@]}"; do
        name="${entry%%:*}"
        [ "${entry#*:}" = per-shell-file ] && ! is_shell_lib_file "$REPO_ROOT" "$file" && continue
        "check_run__$name" "$REPO_ROOT" "$tmpdir" "$file" "$tmpdir/$name.out" || echo "$name:$file" >>"$found"
    done
done

grep -v '^#' "$BASELINE" 2>/dev/null | grep . >"$tmpdir/baseline"
new=$(grep -vxF -f "$tmpdir/baseline" "$found")
# A baseline key for a file judged in this run that no longer reproduces is
# stale: it would hide a later regression, so it fails until removed.
printf '%s\n' "$@" >"$tmpdir/files"
stale=$(awk 'FILENAME == ARGV[1] { judged[$0] = 1; next }
    FILENAME == ARGV[2] { hit[$0] = 1; next }
    (substr($0, index($0, ":") + 1) in judged) && !($0 in hit)' "$tmpdir/files" "$found" "$tmpdir/baseline")
[ -z "$new$stale" ] && exit 0
# One write per run so parallel chunks (golden rules) do not interleave lines.
report=$(
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        echo "$key"
        grep -F -- "${key#*:}" "$tmpdir/${key%%:*}.out" | head -n 5 | sed 's/^/    /'
    done <<<"$new"
    while IFS= read -r key; do
        [ -n "$key" ] && echo "$key  (stale: no longer reproduces, remove it from baseline.txt)"
    done <<<"$stale"
)
printf '%s\n' "$report"
exit 1
