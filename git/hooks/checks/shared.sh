#!/usr/bin/env bash
# Shared helpers for git/hooks/pre-commit (project-level hook).

write_staged_or_worktree_to_tmp() {
    local repo_root="$1"
    local repo_rel_path="$2"
    local tmp_path="$3"

    # Prefer staged content (commit accuracy), fall back to worktree.
    if git cat-file -e ":$repo_rel_path" 2>/dev/null; then
        git show ":$repo_rel_path" >"$tmp_path" 2>/dev/null || return 1
        return 0
    fi

    local worktree_path="$repo_root/$repo_rel_path"
    [ -f "$worktree_path" ] || return 1
    cp "$worktree_path" "$tmp_path" 2>/dev/null
}

# The one place that says what a path under shell-common/tools/custom/ is:
# "entrypoint" for the flat *.sh scripts, "lib" for the source-only helpers in
# custom/lib/ (mode 0644, never executed), empty for everything else.
#
# The exception is lib/ specifically, not "any subdirectory": a future nested
# layout that does hold executables must fall through to the generic rules and
# be judged by them, rather than inheriting an exemption written for source-only
# helpers. Both nested arms have to come before the flat one because `*` matches
# `/` in a shell pattern, so `custom/*.sh` alone would claim every nested path
# too — and the empty arm is what keeps a nested file out of both classes
# instead of silently becoming either a lib or an entry point.
custom_tool_class() {
    case "$1" in
        shell-common/tools/custom/lib/*) echo "lib" ;;
        shell-common/tools/custom/*/*) ;;
        shell-common/tools/custom/*.sh) echo "entrypoint" ;;
    esac
}
