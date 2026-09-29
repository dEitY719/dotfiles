#!/usr/bin/env bash
# git/global-hooks/lib/graphify-refresh.sh (issue #1838)
#
# The single non-delegation step in the global wrappers: post-merge and
# post-rewrite refresh a graphify knowledge graph after the default branch is
# updated by `git pull` (ff, merge or rebase). graphify's own
# `graphify hook install` covers only post-commit/post-checkout and skips
# while a rebase is in progress, so pulls never reach it.
#
# `git rebase origin/main` with no local commits is a fast-forward: git never
# fires post-rewrite (nothing rewritten), only post-checkout while
# .git/rebase-merge/ still exists — where graphify's own post-checkout skips.
# post-checkout therefore refreshes exactly that case; a rebase that replays
# commits is left to post-rewrite so the refresh never runs twice.
#
# Opt-in per repo: runs only when ALL hold (otherwise a silent no-op):
#   - post-rewrite was invoked with $1 = rebase (amend is not a pull)
#   - post-checkout fired inside a fast-forward rebase (orig-head is an
#     ancestor of onto); plain branch switches stay graphify's own job
#   - branch = default branch (origin/HEAD, fallback main); during a rebase
#     HEAD is detached, so the branch comes from rebase-merge/head-name
#   - <repo root>/graphify-out/graph.json exists
#   - `command -v graphify` succeeds (no absolute path: pyenv switches)
# `graphify update .` is AST-only (no API cost) and runs in the background so
# the pull is never blocked; failures land in graphify-out/.hook-update.log.
# Prints one start line to stderr (git shows it in the pull output; the run
# is async, so completion is checked in the log). Never fails, never exits —
# the caller delegates afterwards.
# stdin is not read (post-rewrite's rewritten-ref list goes to the delegate).
#
# Usage: HOOK_NAME=<hook>; graphify_refresh "$@"

graphify_refresh() {
    local root default_branch branch rb
    [ "${HOOK_NAME:-}" = post-rewrite ] && [ "${1:-}" != rebase ] && return 0
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    [ -f "$root/graphify-out/graph.json" ] || return 0
    command -v graphify >/dev/null 2>&1 || return 0
    if [ "${HOOK_NAME:-}" = post-checkout ]; then
        rb="$(git rev-parse --git-dir 2>/dev/null)/rebase-merge"
        [ -f "$rb/head-name" ] || return 0
        git merge-base --is-ancestor "$(cat "$rb/orig-head")" "$(cat "$rb/onto")" 2>/dev/null || return 0
        branch=$(cat "$rb/head-name")
        branch=${branch#refs/heads/}
    else
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    fi
    default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    default_branch=${default_branch#origin/}
    [ "$branch" = "${default_branch:-main}" ] || return 0
    (cd "$root" && graphify update . </dev/null >graphify-out/.hook-update.log 2>&1 &) 2>/dev/null
    echo "graphify: update started in background (log: graphify-out/.hook-update.log)" >&2
    return 0
}
