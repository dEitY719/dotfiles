#!/usr/bin/env bash
# git/hooks/checks/hardcoded_home_path_check.sh
#
# Blocks staged shell config files that contain a hardcoded absolute home
# path like `/home/<user>/...` or `/Users/<user>/...`. Triggered by issue
# #737 — bun installer re-appends `/home/deity719/.bun/_bun` to `zsh/zshrc`
# on every run, silently breaking multi-PC portability after PR #736's
# one-shot normalization.
#
# Scope (staged files only):
#   bash/        zsh/        shell-common/
#   plus top-level dotfiles: zshrc, bashrc, profile (if ever tracked)
#
# Exclusions:
#   *.md       (docs may quote example paths)
#   tests/     (fixtures often hardcode tmpdir-shaped paths)
#   docs/      (same)
#   lines that start with `#` (comments / heredoc markers)
#   lines with the `# allow-abs-home` escape marker on the same line

check_hardcoded_home_path() {
    local repo_root="$1"
    local tmpdir="$2"
    local repo_rel_path="$3"
    local output_file="$4"

    case "$repo_rel_path" in
        bash/* | zsh/* | shell-common/*) ;;
        zshrc | bashrc | profile) ;;
        *) return 0 ;;
    esac

    case "$repo_rel_path" in
        *.md) return 0 ;;
        tests/* | */tests/*) return 0 ;;
        docs/* | */docs/*) return 0 ;;
    esac

    local tmp_file
    tmp_file=$(mktemp "$tmpdir/abs_home_stage_XXXXXX.txt")
    write_staged_or_worktree_to_tmp "$repo_root" "$repo_rel_path" "$tmp_file" 2>/dev/null || {
        rm -f "$tmp_file"
        return 0
    }

    # Pattern: `/home/<segment>` or `/Users/<segment>`. <segment> is one or
    # more name chars; the trailing `/` is intentionally NOT required so
    # `export MY_HOME=/home/user` (no slash, no following path) is also
    # caught (gemini-code-assist review on PR #738). `awk -v pfx=...`
    # embeds the file name directly into the printf so a downstream sed
    # rewrite is unnecessary and whitespace in $0 stays safe.
    local hits
    hits=$(awk -v pfx="$repo_rel_path" '
        {
            line = $0
            # Skip pure comment lines (first non-blank char is #)
            if (line ~ /^[[:space:]]*#/) next
            # Skip explicit allowlist
            if (line ~ /# allow-abs-home/) next
            # Match resolved home paths
            if (line ~ /\/home\/[A-Za-z0-9._-]+/ ||
                line ~ /\/Users\/[A-Za-z0-9._-]+/) {
                printf "    %s:%d:%s\n", pfx, NR, line
            }
        }
    ' "$tmp_file" 2>/dev/null || true)

    rm -f "$tmp_file"

    if [ -z "$hits" ]; then
        return 0
    fi

    {
        echo "$repo_rel_path: [BLOCKING] Hardcoded absolute home path"
        echo "  Use \$HOME or ~ instead. If the path is intentional, add"
        echo "  '# allow-abs-home' on the same line."
        echo "  Matches:"
        echo "$hits"
        echo ""
    } >>"$output_file"

    return 1
}
