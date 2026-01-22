#!/usr/bin/env bash

check_init_auto_sourcing() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    case "$repo_rel_path" in
        bash/main.bash|zsh/main.zsh) ;;
        *) return 0 ;;
    esac

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/init_stage_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

    local matches
    matches=$(awk '
        function is_comment(line) { return line ~ /^[[:space:]]*#/ }
        BEGIN { in_custom_loop=0 }
        {
            line=$0
            if (is_comment(line)) next

            if (line ~ /(^|[[:space:];])(source)[[:space:]]+.*tools\/custom/ ||
                line ~ /(^|[[:space:];])\.[[:space:]]+.*tools\/custom/ ||
                line ~ /(^|[[:space:];])(safe_source)[[:space:]]+.*tools\/custom/) {
                printf "%d:%s\n", NR, line
            }

            if (line ~ /^[[:space:]]*for[[:space:]].*in[[:space:]].*tools\/custom/ &&
                line ~ /\.sh/ ) {
                in_custom_loop=1
                next
            }
            if (in_custom_loop && line ~ /^[[:space:]]*done([[:space:]]|$)/) {
                in_custom_loop=0
                next
            }
            if (in_custom_loop &&
                (line ~ /(^|[[:space:];])(source)[[:space:]]+/ ||
                 line ~ /(^|[[:space:];])\.[[:space:]]+/ ||
                 line ~ /(^|[[:space:];])(safe_source)[[:space:]]+/)) {
                printf "%d:%s\n", NR, line
            }
        }
    ' "$tmp_file" 2>/dev/null || true)

    if [ -n "$matches" ]; then
        {
            echo "$repo_rel_path: [BLOCKING] tools/custom auto-sourcing detected in init file"
            echo "  Risk: Re-introduces auto-sourcing of executable utilities (hangs, infinite loops, blocked shell init)"
            echo "  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md"
            echo "  Matches:"
            echo "$matches" | sed 's/^/    /'
            echo ""
        } >>"$output_file"
        rm -f "$tmp_file"
        return 1
    fi

    rm -f "$tmp_file"
    return 0
}
