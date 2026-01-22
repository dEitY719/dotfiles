#!/usr/bin/env bash

check_library_purity() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    case "$repo_rel_path" in
        shell-common/functions/*.sh|shell-common/tools/integrations/*.sh) ;;
        *) return 0 ;;
    esac

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/purity_stage_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    local hits
    hits=$(awk '
        function is_comment(line) { return line ~ /^[[:space:]]*#/ }
        BEGIN { depth=0 }
        {
            line=$0
            if (is_comment(line)) next

            # Handle one-line functions: func() { ... }
            if (line ~ /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/) {
                # Check if it also has a closing brace on the same line
                if (line ~ /\}/) {
                    # One-line function, depth stays 0
                    next
                } else {
                    # Multi-line function begins
                    depth++
                    next
                }
            }

            if (line ~ /^[[:space:]]*\}/) { if (depth>0) depth--; next }
            if (depth==0 && line ~ /^[[:space:]]*(read|select)[[:space:]]/) {
                printf "INTERACTIVE:%d:%s\n", NR, line
            }
            if (depth==0 && line ~ /^[[:space:]]*(main|[a-z_][a-z0-9_]*_main)([[:space:]]+|$)/ &&
                line !~ /^[[:space:]]*(main|[a-z_][a-z0-9_]*_main)[[:space:]]*\(\)[[:space:]]*\{/) {
                printf "MAIN_CALL:%d:%s\n", NR, line
            }
            # INSTALL lines are detected outside awk using SSOT regex (from hook-config.sh)
        }
    ' "$tmp_file" 2>/dev/null || true)

    local install_ere="${DOTFILES_HOOKS_LIBRARY_PURITY_INSTALL_ERE:-apt-get[[:space:]]+install|apt[[:space:]]+install|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S|pip[[:space:]]+install|uv[[:space:]]+pip[[:space:]]+install|npm[[:space:]]+install|brew[[:space:]]+install}"
    local install_hits
    install_hits=$(grep -nE "$install_ere" "$tmp_file" 2>/dev/null || true)

    local violation_count=0

    if echo "$hits" | grep -q '^MAIN_CALL:'; then
        violation_count=1
        {
            echo "$repo_rel_path: [BLOCKING] Library purity violation (auto-sourced path)"
            echo "  - Top-level main/_main call (will execute when sourced)"
            echo "  Matches:"
            echo "$hits" | grep '^MAIN_CALL:' | sed 's/^MAIN_CALL:/    /'
        } >>"$output_file"
    fi

    if echo "$hits" | grep -q '^INTERACTIVE:'; then
        violation_count=1
        {
            echo "$repo_rel_path: [BLOCKING] Library purity violation (auto-sourced path)"
            echo "  - Top-level interactive prompt (read/select) found outside functions"
            echo "  Matches:"
            echo "$hits" | grep '^INTERACTIVE:' | sed 's/^INTERACTIVE:/    /'
        } >>"$output_file"
    fi

    if [ -n "$install_hits" ]; then
        violation_count=1
        {
            echo "$repo_rel_path: [BLOCKING] Library purity violation (auto-sourced path)"
            echo "  - Top-level installation command found (belongs in tools/custom, executed explicitly)"
            echo "  Matches:"
            echo "$install_hits" | sed 's/^/    /'
        } >>"$output_file"
    fi

    if [ $violation_count -ne 0 ]; then
        {
            echo "  Fix: Move executable/interactive logic to 'shell-common/tools/custom/' and invoke explicitly"
            echo "  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md"
            echo ""
        } >>"$output_file"
        rm -f "$tmp_file"
        return 1
    fi

    rm -f "$tmp_file"
    return 0
}
