#!/usr/bin/env bash
# auto_execution_check.sh
# Detects auto-execution in sourced shell files
# Problem: When functions are sourced (especially during shell init),
# if they have code that runs unconditionally, it can pollute output,
# hang the shell, or cause other side effects (especially p10k instant prompt conflicts)

check_auto_execution_in_sourced_files() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    # Only check shell function files and integration tools (sourced files, not direct executables)
    case "$repo_rel_path" in
        shell-common/functions/*.sh | shell-common/tools/integrations/*.sh)
            ;;
        *)
            return 0
            ;;
    esac

    local abs_path="$repo_root/$repo_rel_path"
    [ -f "$abs_path" ] || return 0

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/auto_exec_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    # Check for auto-execution patterns in sourced files
    # Pattern 1: Direct function calls (not in if statement)
    #   - work_log_help (function call at top level)
    #   - echo "Something" (console output)
    # Pattern 2: if [ ... ] then ... fi that runs unconditionally
    #   - if [ "${0##*/}" = "filename.sh" ]; then FUNCNAME; fi
    #     This can be triggered during sourcing in some contexts

    local violations=""

    # Lines that are concerning (function calls, echo, etc. at top level)
    violations=$(awk '
        BEGIN {
            skip_next = 0
        }
        # Skip comments and empty lines
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }

        # Skip common pattern: if [ ... ] block defining something
        /^if \[/ { skip_next = 1; next }
        skip_next && /^fi$/ { skip_next = 0; next }
        skip_next { next }

        # Skip function definitions
        /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ { in_function = 1; func_line = NR; next }
        in_function && /^}$/ { in_function = 0; next }
        in_function { next }

        # Look for code that shouldnt be at file scope (not in functions)
        # - Function calls (word followed by parens or just word on its own line)
        # - Console output (echo, printf, etc)
        # - Redirections to files
        /^[[:space:]]*(echo|printf|cat|tee|read|source|\.)[[:space:]]/ {
            if ($0 !~ /^[[:space:]]*#/) print NR": "$0
        }

        # Specific pattern: if [ "${0##" - likely to be execution guard
        /\$\{0##/ {
            # This is a direct execution check, which is often misused
            print NR": [SUSPICIOUS] Direct execution guard: "$0
        }
    ' "$tmp_file" 2>/dev/null || true)

    if [ -n "$violations" ]; then
        # For sourced files, these patterns are concerning
        # But we need to be careful not to flag legitimate helper functions
        # Only flag if there are multiple violations or very obvious ones

        local violation_count=$(echo "$violations" | wc -l)
        if [ "$violation_count" -gt 0 ]; then
            # Be conservative: only flag if we see function calls that look like auto-exec
            if echo "$violations" | grep -qE '\$\{0##|SUSPICIOUS|^[[:space:]]*(work_log_help|help_func|__init__)'; then
                {
                    echo "$repo_rel_path: [BLOCKING] Auto-execution pattern detected in sourced file"
                    echo "  Risk: When this file is sourced (especially during shell init), these"
                    echo "        lines will execute unconditionally, polluting console output"
                    echo "        or causing other side effects (p10k instant prompt conflicts, etc)"
                    echo "  Solution: Move all code into functions. Only define functions at file scope."
                    echo "           Call functions explicitly or through registry (my_help_impl, etc)."
                    echo "  Violations:"
                    echo "$violations" | sed 's/^/    /'
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
