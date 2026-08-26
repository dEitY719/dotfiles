#!/usr/bin/env bash
# direct_exec_guard_check.sh
# Enforces that executable scripts in tools/custom/ have proper direct-exec guards
#
# Problem: Executable scripts without direct-exec guards can auto-execute when sourced,
# causing console pollution, side effects, and initialization conflicts.
#
# Solution: All tools/custom/*.sh files MUST have guard pattern:
#   if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
#       main "$@"
#   fi

check_direct_exec_guard() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    # Only check tools/custom entry points (executed scripts, not sourced).
    # Files under a subdirectory are source-only helpers, and the guard this
    # check demands dereferences ${BASH_SOURCE[0]} — a bad substitution under
    # dash, which would break the POSIX-sh entry points that source them.
    # custom_tool_class (shared.sh) is the SSOT for that distinction.
    [ "$(custom_tool_class "$repo_rel_path")" = "entrypoint" ] || return 0

    local abs_path="$repo_root/$repo_rel_path"
    [ -f "$abs_path" ] || return 0

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/guard_check_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    # Check for proper direct-exec guard pattern
    # Pattern 1: if [ "${BASH_SOURCE[0]}" = "$0" ]
    # Pattern 2: [[ "${BASH_SOURCE[0]}" == "$0" ]]
    # Pattern 3: if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]
    # Pattern 4: if [ "${0##*/}" = "<name>.sh" ]   — the basename guard
    #
    # Pattern 4 is what a POSIX-sh entry point has to use: dash aborts on
    # ${BASH_SOURCE[0]} with "Bad substitution" before the test is even
    # evaluated, so patterns 1-3 are unavailable to any script that must also
    # run under /bin/sh (ensure_jq.sh, aicron.sh). tests/golden_rules already
    # accepted this pattern; this list had drifted behind it.

    local has_guard=0

    if grep -qE 'if \[ "\$\{BASH_SOURCE\[0\]\}" = "\$0" \]|if \[\[ "\$\{BASH_SOURCE\[0\]\}" == "\$0" \]\]|if \[ "\$\{BASH_SOURCE\[0\]:-\$0\}" = "\$0" \]|"\$\{0##\*/\}"' "$tmp_file" 2>/dev/null; then
        has_guard=1
    fi

    if [ $has_guard -eq 0 ]; then
        {
            echo "$repo_rel_path: [BLOCKING] Missing direct-exec guard"
            echo "  Risk: Executable scripts without direct-exec guards can run code"
            echo "        when sourced, causing side effects, console pollution, and"
            echo "        shell initialization conflicts (p10k, prompt issues, etc)"
            echo ""
            echo "  Required Pattern (place at END of script, after all functions):"
            echo ""
            echo "  if [ \"\${BASH_SOURCE[0]}\" = \"\$0\" ] || [ -z \"\${BASH_SOURCE[0]}\" ]; then"
            echo "      main \"\$@\""
            echo "  fi"
            echo ""
            echo "  Explanation:"
            echo "  - Runs main() only if script executed directly (./script.sh)"
            echo "  - Skips main() if file is sourced (source script.sh)"
            echo "  - [ -z \"\${BASH_SOURCE[0]}\" ] handles POSIX shells (sh, etc)"
            echo ""
            echo "  Alternative (zsh compatible, more strict):"
            echo "  if [ \"\${BASH_SOURCE[0]:-\$0}\" = \"\$0\" ]; then"
            echo "      main \"\$@\""
            echo "  fi"
            echo ""
        } >> "$output_file"
        rm -f "$tmp_file"
        return 1
    fi

    rm -f "$tmp_file"
    return 0
}
