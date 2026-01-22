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
