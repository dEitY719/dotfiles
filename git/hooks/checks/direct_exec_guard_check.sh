#!/usr/bin/env bash
# direct_exec_guard_check.sh
# Enforces that executable scripts in tools/custom/ have proper direct-exec guards
#
# Problem: Executable scripts without direct-exec guards can auto-execute when sourced,
# causing console pollution, side effects, and initialization conflicts.
#
# Solution: All tools/custom/*.sh files MUST have guard pattern:
#   if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
#       main "$@"
#   fi

check_direct_exec_guard() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    # Only check tools/custom files (executable scripts, not sourced)
    case "$repo_rel_path" in
        shell-common/tools/custom/*.sh)
            ;;
        *)
            return 0
            ;;
    esac

    local abs_path="$repo_root/$repo_rel_path"
    [ -f "$abs_path" ] || return 0

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/guard_check_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    # Check for proper direct-exec guard pattern
    # Pattern 1: if [ "${BASH_SOURCE[0]}" = "$0" ]
    # Pattern 2: [[ "${BASH_SOURCE[0]}" == "$0" ]]
    # Pattern 3: if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]

    local has_guard=0

    if grep -qE 'if \[ "\$\{BASH_SOURCE\[0\]\}" = "\$0" \]|if \[\[ "\$\{BASH_SOURCE\[0\]\}" == "\$0" \]\]|if \[ "\$\{BASH_SOURCE\[0\]:-\$0\}" = "\$0" \]' "$tmp_file" 2>/dev/null; then
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
            echo "  if [ \"\${BASH_SOURCE[0]}\" = \"\$0\" ] || [ -z \"\$BASH_SOURCE\" ]; then"
            echo "      main \"\$@\""
            echo "  fi"
            echo ""
            echo "  Explanation:"
            echo "  - Runs main() only if script executed directly (./script.sh)"
            echo "  - Skips main() if file is sourced (source script.sh)"
            echo "  - [ -z \"\$BASH_SOURCE\" ] handles POSIX shells (sh, etc)"
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
