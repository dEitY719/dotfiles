#!/usr/bin/env bash

check_auto_executable_in_custom() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    case "$repo_rel_path" in
        shell-common/tools/custom/*.sh) ;;
        *) return 0 ;;
    esac

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/custom_stage_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    if grep -qE '^[[:space:]]*main[[:space:]]*\(\)[[:space:]]*\{' "$tmp_file" 2>/dev/null; then
        local tail_calls
        tail_calls=$(tail -n 30 "$tmp_file" | \
            grep -nE '^[[:space:]]*main([[:space:]]+"?\$@"?)?[[:space:]]*$' | \
            grep -vE '^[0-9]+:[[:space:]]*#' || true)

        if [ -n "$tail_calls" ]; then
            local guard_present=0
            if tail -n 80 "$tmp_file" | grep -Eq 'BASH_SOURCE\[0\].*(\$\{?0\}?|\$0)|(\$\{?0\}?|\$0).*BASH_SOURCE\[0\]'; then
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
                    echo "  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md"
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
