#!/usr/bin/env bash
# git/global-hooks/lib/local-ci.sh
#
# Warn-only local CI for the global pre-push wrapper: after the project hook
# (and git-lfs) passed, run scripts/ci.sh (dry, never --post) on the pushed
# commit. GitHub Actions is billing-locked for the dEitY719/* repos, so this
# is the earliest point a red validate/bats suite can be seen.
#
# WHEN IT RUNS — local_ci_applies "$2" is true only when ALL hold:
#   - CI_LOCAL_SKIP is not 1 (`git push --no-verify` skips every hook anyway)
#   - the push URL's owner (first path segment; scp-style, ssh:// and
#     https://, any host incl. GHES and ssh aliases) is in the allowlist:
#     dEitY719 plus CI_LOCAL_OWNERS (comma/space separated), case-insensitive
# Any other owner (collaborating orgs) gets the plain delegation path, byte
# for byte: no stdin buffering, no output, no ci.sh.
#
# WHAT IT DOES — local_ci_wrap "$@" (never returns)
#   1. buffers stdin (the ref list) once to an unlinked temp file;
#   2. runs the normal delegation (delegate.sh, incl. lib/lfs.sh) in a
#      subshell fed from that buffer and keeps its exit code;
#   3. only if that code is 0 and a non-deletion ref was pushed, runs
#      `ci.sh --repo <root> --sha <first pushed local sha>` under
#      `timeout ${CI_LOCAL_TIMEOUT:-300}` (when available);
#   4. exits with the delegation's code. ci.sh failing, hanging, missing or
#      broken only prints a warning to stderr — it never blocks the push.
#
# ci.sh is found next to this file's real path (../../../scripts/ci.sh), not
# via cwd. Requires SELF and HOOK_NAME from the wrapper.

# 0 = the push URL $1 belongs to an allowlisted owner and CI_LOCAL_SKIP!=1.
local_ci_applies() {
    local url="${1:-}" rest owner o
    [ "${CI_LOCAL_SKIP:-0}" = "1" ] && return 1

    case "$url" in
    *://*) rest="${url#*://}" && rest="${rest#*/}" ;; # drop scheme + authority
    *:*) rest="${url#*:}" ;;                          # scp-style host:owner/repo
    *) return 1 ;;                                    # local path: no owner
    esac
    owner="${rest%%/*}"
    [ -n "$owner" ] && [ "$owner" != "$rest" ] || return 1

    local -a extra=()
    IFS=$', \t' read -ra extra <<<"${CI_LOCAL_OWNERS:-}"
    for o in dEitY719 "${extra[@]}"; do
        [ "${o,,}" = "${owner,,}" ] && return 0
    done
    return 1
}

local_ci_wrap() {
    local buf rc=0 sha="" _ref local_sha _rest ci root out ci_rc=0
    local zero="0000000000000000000000000000000000000000"
    local lib_dir
    lib_dir="$(dirname "${BASH_SOURCE[0]}")"

    buf=$(mktemp "${TMPDIR:-/tmp}/local-ci-pre-push.XXXXXX") || {
        echo "[Global Hook] local CI: cannot buffer stdin, skipped" >&2
        # shellcheck source=./delegate.sh
        source "$lib_dir/delegate.sh"
    }
    cat >"$buf"
    exec 3<"$buf" 4<"$buf"
    rm -f "$buf"

    # delegate.sh exits (or execs) — the subshell contains that.
    # shellcheck source=./delegate.sh
    (source "$lib_dir/delegate.sh") <&3 3<&- 4<&- || rc=$?
    exec 3<&-
    if [ "$rc" -ne 0 ]; then
        exec 4<&-
        exit "$rc"
    fi

    while read -r _ref local_sha _rest; do
        [ -n "$local_sha" ] && [ "$local_sha" != "$zero" ] && sha="$local_sha" && break
    done <&4
    exec 4<&-
    # Branch deletion only, or nothing pushed: nothing to measure.
    [ -n "$sha" ] || exit 0

    root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    ci="$(cd "$lib_dir/../../.." && pwd)/scripts/ci.sh"
    if [ ! -f "$ci" ]; then
        echo "[Global Hook] local CI: $ci not found, skipped (push not blocked)" >&2
        exit 0
    fi

    echo "[Global Hook] local CI (warn-only, no --post): ci.sh --repo $root --sha ${sha:0:12}" >&2
    local -a run=(bash "$ci" --repo "$root" --sha "$sha")
    command -v timeout >/dev/null 2>&1 && run=(timeout "${CI_LOCAL_TIMEOUT:-300}" "${run[@]}")
    # Hooks may export GIT_DIR & co (linked worktrees); ci.sh clones elsewhere.
    out=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
        -u GIT_OBJECT_DIRECTORY -u GIT_PREFIX "${run[@]}" </dev/null 2>&1) || ci_rc=$?

    if [ "$ci_rc" -eq 0 ]; then
        echo "[Global Hook] local CI passed (statuses not posted; run ci.sh --post to publish)" >&2
    else
        {
            echo "[Global Hook] WARNING: local CI failed (exit $ci_rc$([ "$ci_rc" -eq 124 ] && echo ', timed out')) — push NOT blocked"
            grep -E '^(FAIL|suite) ' <<<"$out"
            echo "  rerun: bash $ci --repo $root   (add --post to publish commit statuses)"
            echo "  skip:  CI_LOCAL_SKIP=1 git push"
        } >&2
    fi
    exit 0
}
