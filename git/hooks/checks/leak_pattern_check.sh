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
# do not echo into terminals, CI logs or screen shares. A file name that
# itself matches is printed as `<redacted path: N chars ...>` (#1997).

# leak_guard_active / leak_redact: one implementation shared with the global
# pre-commit hook (#2008). A missing lib fails this source, so the project
# hook blocks instead of silently running with the guard off.
# shellcheck source=../../global-hooks/lib/leak_guard.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../global-hooks/lib/leak_guard.sh" || return 1

# check_leak_patterns OUTPUT_FILE
# Returns 0 when inactive or clean, 1 when a staged added line matches.
check_leak_patterns() {
    local output_file="$1"

    leak_guard_active || return 0

    # Records "<file>\t<line>\t<added text>" per staged added line. Only the
    # text field is grepped for content hits; file names are scanned on
    # their own (#1997) so a matching path is caught even with no added
    # line (pure rename, empty file) and is never printed verbatim.
    local records bad idx
    records=$(git -c core.quotePath=false diff --cached -U0 --no-color --no-ext-diff \
        --diff-filter=ACMR 2>/dev/null | awk '
        /^diff --git / { hdr = 1; next }
        hdr && /^\+\+\+ / { f = substr($0, 7); next }
        /^@@ / { hdr = 0; s = $3; sub(/^\+/, "", s); split(s, a, ","); n = a[1]; next }
        !hdr && /^\+/ { printf "%s\t%d\t%s\n", f, n, substr($0, 2); n++ }
    ')
    bad=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR 2>/dev/null \
        | grep -E -- "${LEAK_PATTERNS_ERE}" || true)
    idx=$(printf '%s\n' "$records" | cut -f3- | grep -nE -- "${LEAK_PATTERNS_ERE}" | cut -d: -f1)

    [ -z "$bad$idx" ] && return 0
    # A matching path is replaced by its length, never printed.
    # shellcheck disable=SC2016 # literal ${LEAK_PATTERNS_ERE} in the hint, never its value
    printf '%s\n' "$records" | BAD="$bad" IDX="$idx" awk -F'\t' '
        BEGIN {
            split(ENVIRON["IDX"], t, "\n"); for (i in t) want[t[i]] = 1
            n = split(ENVIRON["BAD"], b, "\n")
            for (i = 1; i <= n; i++) {
                bad[b[i]] = 1
                printf "<redacted path: %d chars, matches LEAK_PATTERNS_ERE>  (use: git diff --cached --name-only | grep -nE \"${LEAK_PATTERNS_ERE}\")\n", length(b[i])
            }
        }
        NR in want {
            loc = ($1 in bad) ? sprintf("<redacted path: %d chars>", length($1)) : $1
            printf "%s:%s  (matches LEAK_PATTERNS_ERE)\n", loc, $2
        }' >>"$output_file"
    return 1
}
