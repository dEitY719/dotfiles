#!/usr/bin/env bash
# git/global-hooks/lib/graphify-refresh.sh (issue #1838)
#
# The single non-delegation step in the global wrappers: post-merge and
# post-rewrite refresh a graphify knowledge graph after the default branch is
# updated by `git pull` (ff, merge or rebase). graphify's own
# `graphify hook install` covers only post-commit/post-checkout and skips
# while a rebase is in progress, so pulls never reach it.
#
# Opt-in per repo: runs only when ALL hold (otherwise a silent no-op):
#   - post-rewrite was invoked with $1 = rebase (amend is not a pull)
#   - current branch = default branch (origin/HEAD, fallback main)
#   - <repo root>/graphify-out/graph.json exists
#   - `command -v graphify` succeeds (no absolute path: pyenv switches)
# `graphify update .` is AST-only (no API cost) and runs in the background so
# the pull is never blocked; failures land in graphify-out/.hook-update.log.
# Never prints, never fails, never exits — the caller delegates afterwards.
# stdin is not read (post-rewrite's rewritten-ref list goes to the delegate).
#
# Usage: HOOK_NAME=<hook>; graphify_refresh "$@"

graphify_refresh() {
    local root default_branch
    [ "${HOOK_NAME:-}" = post-rewrite ] && [ "${1:-}" != rebase ] && return 0
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    [ -f "$root/graphify-out/graph.json" ] || return 0
    command -v graphify >/dev/null 2>&1 || return 0
    default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    default_branch=${default_branch#origin/}
    [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "${default_branch:-main}" ] || return 0
    (cd "$root" && graphify update . </dev/null >graphify-out/.hook-update.log 2>&1 &) 2>/dev/null
    return 0
}
