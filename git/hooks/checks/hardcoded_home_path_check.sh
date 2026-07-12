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
#
# Scan input (issue #1142): only the **added lines** of the staged diff
# (`git diff --cached -U0`), not the whole file. Pre-existing absolute
# paths that predate this guard no longer surface when an unrelated line
# of an old file is first touched. The #737 defense contract is preserved
# because an installer re-appending `/home/...` shows up as an added line.

check_hardcoded_home_path() {
    local repo_root="$1"
    # $2 (tmpdir) is unused now — the diff scan streams git output directly.
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

    # Scan only the added (`+`) lines of the staged diff. Hunk headers
    # (`@@ -a,b +c,d @@`) seed the new-file line number so reported line
    # numbers still point at the real location in the committed file.
    #
    # Pattern: `/home/<segment>` or `/Users/<segment>`. <segment> is one or
    # more name chars; the trailing `/` is intentionally NOT required so
    # `export MY_HOME=/home/user` (no slash, no following path) is also
    # caught (gemini-code-assist review on PR #738). `awk -v pfx=...`
    # embeds the file name directly into the printf so a downstream sed
    # rewrite is unnecessary and whitespace in the line stays safe.
    local hits
    hits=$(git -C "$repo_root" diff --cached -U0 -- "$repo_rel_path" 2>/dev/null |
        awk -v pfx="$repo_rel_path" '
            # Hunk header: capture the new-file start line (the `+c` field).
            /^@@/ {
                match($0, /\+[0-9]+/)
                newline = substr($0, RSTART + 1, RLENGTH - 1) + 0
                next
            }
            # Added content lines only (skip the `+++ b/file` file header).
            /^\+/ {
                if ($0 ~ /^\+\+\+/) next
                line = substr($0, 2)
                if (line !~ /^[[:space:]]*#/ && line !~ /# allow-abs-home/ &&
                    (line ~ /\/home\/[A-Za-z0-9._-]+/ ||
                     line ~ /\/Users\/[A-Za-z0-9._-]+/)) {
                    printf "    %s:%d:%s\n", pfx, newline, line
                }
                newline++
                next
            }
        ' 2>/dev/null || true)

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
