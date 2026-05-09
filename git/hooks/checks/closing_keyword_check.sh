#!/usr/bin/env bash
# git/hooks/checks/closing_keyword_check.sh
#
# Reject commit messages that use forbidden GitHub closing keywords.
# Allowed: Closes, Fixes
# Forbidden: Refs, Resolves, See, References
#
# Rationale (issue #392):
# - Refs/See/References are NOT recognized as closing keywords by GitHub,
#   so they break auto-close + project-board automation.
# - Resolves is recognized by GitHub but violates the AgentToolbox
#   stacked-closes-rollup policy.
# - skill-driven and manual commits must follow the same policy. The
#   skill side is enforced in claude/skills/gh-commit/**, this hook
#   catches `--no-verify`-less manual commits that bypass the skills.
#
# Escape hatch: `git commit --no-verify` (use sparingly — for genuine
# WIP / partial-progress commits where no auto-close is desired).
#
# Returns 0 if message is clean, 1 with a diagnostic on stderr otherwise.

# check_closing_keyword
#
# Args:
#   $1 — path to commit message file
#
# Reads the file, scans every line for `^(Refs|Resolves|See|References)\s+#<num>`,
# and prints all matches with line numbers when one or more are found.
# Comment lines (`#...`) are skipped so that git's own commented hints
# don't trip the check.
check_closing_keyword() {
    local msg_file="$1"
    [ -n "$msg_file" ] || return 0
    [ -f "$msg_file" ] || return 0

    local forbidden
    forbidden=$(grep -vE '^[[:space:]]*#' "$msg_file" \
        | grep -nE '^(Refs|Resolves|See|References)[[:space:]]+#[0-9]+' \
        || true)

    if [ -n "$forbidden" ]; then
        echo "✗ commit-msg: forbidden closing keyword detected" >&2
        echo "$forbidden" >&2
        echo "" >&2
        echo "  Allowed:   Closes #N, Fixes #N" >&2
        echo "  Forbidden: Refs, Resolves, See, References" >&2
        echo "" >&2
        echo "  Why: Refs/See/References do not auto-close issues on merge," >&2
        echo "       Resolves violates the AgentToolbox rollup policy." >&2
        echo "       See issue #392 for the full rationale." >&2
        echo "" >&2
        echo "  Fix:    use 'Closes #N' (default) or 'Fixes #N' (bug fix)." >&2
        echo "  WIP:    omit the footer; mention '(part of #N)' inline instead." >&2
        echo "  Bypass: git commit --no-verify (use sparingly)." >&2
        return 1
    fi

    return 0
}
