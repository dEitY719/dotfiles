#!/usr/bin/env bash
# git/hooks/checks/leak_pattern_check.sh
#
# Commit-time twin of the pre-push upstream leak guard (issue #1970).
# Reads the same user-exported variables (SSOT: git/config/pre-push-rules.sh)
# and blocks a commit whose staged *added* lines match LEAK_PATTERNS_ERE, so
# an internal identifier is caught before it enters history instead of at
# push time (when the fix is an amend/rebase).
#
# Active only when ALL hold (otherwise a no-op; the staged diff is read
# only when active, so inactive PCs pay nothing):
#   - SKIP_LEAK_GUARD is not 1         (same escape hatch as pre-push)
#   - LEAK_PATTERNS_ERE is non-empty
#   - UPSTREAM_REMOTES_ERE is non-empty and some remote URL of this repo
#     matches it (same "upstream" notion as pre-push; a checkout with only
#     a private mirror remote is never blocked)
#
# Output: `file:line` only, never the matched text, so the pattern values
# do not echo into terminals, CI logs or screen shares.

# check_leak_patterns OUTPUT_FILE
# Returns 0 when inactive or clean, 1 when a staged added line matches.
check_leak_patterns() {
    local output_file="$1"

    [ "${SKIP_LEAK_GUARD:-0}" = "1" ] && return 0
    [ -n "${LEAK_PATTERNS_ERE:-}" ] || return 0
    [ -n "${UPSTREAM_REMOTES_ERE:-}" ] || return 0
    git config --get-regexp '^remote\..*\.url$' 2>/dev/null \
        | cut -d' ' -f2- | grep -qE -- "${UPSTREAM_REMOTES_ERE}" || return 0

    # Emit "<file>:<line>\t<added text>" per staged added line, grep the
    # whole record (a matching path is a leak too), print only field 1.
    local hits
    hits=$(git -c core.quotePath=false diff --cached -U0 --no-color --no-ext-diff \
        --diff-filter=ACMR 2>/dev/null | awk '
        /^diff --git / { hdr = 1; next }
        hdr && /^\+\+\+ / { f = substr($0, 7); next }
        /^@@ / { hdr = 0; s = $3; sub(/^\+/, "", s); split(s, a, ","); n = a[1]; next }
        !hdr && /^\+/ { printf "%s:%d\t%s\n", f, n, substr($0, 2); n++ }
    ' | grep -E -- "${LEAK_PATTERNS_ERE}" | cut -f1)

    [ -z "$hits" ] && return 0
    printf '%s\n' "$hits" | sed 's/$/  (matches LEAK_PATTERNS_ERE)/' >>"$output_file"
    return 1
}
