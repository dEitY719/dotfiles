#!/usr/bin/env bash

check_auto_executable_in_custom() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    # Entry points only — files under a subdirectory are source-only helpers
    # (mode 0644) with no main() to guard. custom_tool_class lives in shared.sh.
    [ "$(custom_tool_class "$repo_rel_path")" = "entrypoint" ] || return 0

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/custom_stage_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    if grep -qE '^[[:space:]]*main[[:space:]]*\(\)[[:space:]]*\{' "$tmp_file" 2>/dev/null; then
        local tail_calls
        local main_tail_lines="${DOTFILES_HOOKS_CUSTOM_MAIN_TAIL_LINES:-30}"
        local guard_tail_lines="${DOTFILES_HOOKS_CUSTOM_GUARD_TAIL_LINES:-80}"

        tail_calls=$(tail -n "$main_tail_lines" "$tmp_file" | \
            grep -nE '^[[:space:]]*main([[:space:]]+"?\$@"?)?[[:space:]]*$' | \
            grep -vE '^[0-9]+:[[:space:]]*#' || true)

        if [ -n "$tail_calls" ]; then
            local guard_present=0
            # The ${0##*/} basename guard is the third accepted form: a script
            # that must also run under /bin/sh cannot reference BASH_SOURCE at
            # all, because dash rejects the expansion outright. Same list as
            # tests/golden_rules/test_golden_rules.sh Rule 2.
            if tail -n "$guard_tail_lines" "$tmp_file" | grep -Eq 'BASH_SOURCE\[0\].*(\$\{?0\}?|\$0)|(\$\{?0\}?|\$0).*BASH_SOURCE\[0\]|"\$\{0##\*/\}"'; then
                guard_present=1
            fi

            if [ $guard_present -eq 0 ]; then
                {
                    echo "$repo_rel_path: [BLOCKING] Auto-executable main() without direct-exec guard"
                    echo "  Postmortem risk: if tools/custom is accidentally sourced, this will execute at shell init"
                    echo "  Matches (near EOF):"
                    echo "$tail_calls" | sed 's/^/    /'
                    echo "  Fix (example):"
                    echo "    if [ \"\${BASH_SOURCE[0]}\" = \"\$0\" ]; then main \"\$@\"; fi"
                    echo "  Reference: docs/archive/postmortem/postmortem-auto-sourcing-utility-scripts.md"
                    echo ""
                } >>"$output_file"
                rm -f "$tmp_file"
                return 1
            fi
        fi
    fi

    rm -f "$tmp_file"
    return 0
}
