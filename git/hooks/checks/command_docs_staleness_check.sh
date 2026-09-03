#!/usr/bin/env bash
# git/hooks/checks/command_docs_staleness_check.sh
#
# Warns (never blocks) when a commit stages a top-level
# shell-common/tools/custom/*.sh change without also staging the generated
# docs/guide/commands/mytool.md. Issue #1737 — mytool.md's "tools" section
# enumerates that directory (mytool_help.sh's `find "$custom_dir" -maxdepth 1
# -type f -name "*.sh"`), so a tool add/remove/rename that skips regeneration
# silently drifts from the committed doc until the command-docs drift gate
# (tests/integration/test_command_docs.py) catches it on a full test run.
#
# Scope: top-level only, matching that same -maxdepth 1 — a change under
# shell-common/tools/custom/<subdir>/*.sh never appears in mytool.md, so
# flagging it would be a pure false positive (agy + codex review, PR #1741).
#
# Heuristic warning only: many commits touch a tool's body (logic changes)
# without shifting the summary line the doc renders, which would be a
# false positive if this were a hard block.
#
# Usage:
#   . git/hooks/checks/command_docs_staleness_check.sh
#   check_command_docs_staleness "$STAGED_FILES" <warnings_file>

check_command_docs_staleness() {
    local staged_files="$1"
    local warnings_file="$2"

    grep -q '^shell-common/tools/custom/[^/]\+\.sh$' <<<"$staged_files" || return 0
    grep -q '^docs/guide/commands/mytool\.md$' <<<"$staged_files" && return 0

    {
        echo "shell-common/tools/custom/*.sh staged without docs/guide/commands/mytool.md"
        echo "  Fix: ./shell-common/tools/custom/gen_command_docs.sh --force && git add docs/guide/commands/mytool.md"
        echo "  (false positive if this commit doesn't change a tool's summary line)"
        echo ""
    } >>"$warnings_file"
    return 1
}
