#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh
# Source-of-truth mirror for the Layer-1 ABSOLUTE_BLOCK_PATTERNS
# documented in
#   claude/skills/gh-issue-proceed/references/safety-gates.md §4.1
#
# gh_proceed_check_absolute_block <command-string> returns 2 and prints
# "blocked: <key>" when the command matches a Layer-1 absolute
# prohibition; otherwise prints "ok" and returns 0. The bats suite
# exercises one positive + one negative per pattern.
#
# Context inputs (optional):
#   FAKE_DEFAULT_BRANCH   — default branch name (default: main)
#   FAKE_ME               — current user login (default: me)
#   FAKE_ISSUE_CLOSED_BY  — who closed the issue being reopened
#                           (default: $FAKE_ME → self → allowed)

_gp_block() { printf 'blocked: %s\n' "$1"; }

gh_proceed_check_absolute_block() {
    local _cmd="${1-}"
    local _default="${FAKE_DEFAULT_BRANCH:-main}"

    # gh pr merge — sibling skills own merges.
    if printf '%s' "$_cmd" | grep -iqE 'gh +pr +merge'; then
        _gp_block gh_pr_merge
        return 2
    fi

    # Branch deletion: local -D/-d, REST DELETE on a branch/ref, or a
    # remote delete push ("git push <remote> :branch").
    if printf '%s' "$_cmd" | grep -iqE 'git +branch +-D\b|git +branch +-d\b' ||
        printf '%s' "$_cmd" | grep -iqE 'gh +api +-X +DELETE.*/(branches|git/refs)/' ||
        printf '%s' "$_cmd" | grep -iqE 'git +push +[^ ]+ +:'; then
        _gp_block branch_deletion
        return 2
    fi

    # Force push. --force-with-lease is exempt here (Layer 2 token-gates it).
    if printf '%s' "$_cmd" | grep -iqE 'git +push'; then
        if printf '%s' "$_cmd" | grep -iqE -- '--force-with-lease'; then
            : # allowed at Layer 1
        elif printf '%s' "$_cmd" | grep -iqE -- '(--force|[[:space:]]-f([[:space:]]|$))'; then
            if printf '%s' "$_cmd" | grep -iqE -- "(\\b${_default}\\b|\\bmain\\b|\\bmaster\\b)"; then
                _gp_block force_push_default
                return 2
            fi
            _gp_block force_push_general
            return 2
        fi
    fi

    # rm -rf with a path outside $PWD (absolute, home, or parent-relative).
    if printf '%s' "$_cmd" | grep -iqE 'rm +-[a-z]*r[a-z]*f|rm +-[a-z]*f[a-z]*r'; then
        if printf '%s' "$_cmd" | grep -qE 'rm +-[A-Za-z]+ +(/|~|[^ ]*\.\.)'; then
            _gp_block rm_rf_outside_pwd
            return 2
        fi
    fi

    # Destructive DB ops.
    if printf '%s' "$_cmd" | grep -qE '\b(DROP|TRUNCATE)\b|admin +reset|DELETE +FROM'; then
        _gp_block destructive_db
        return 2
    fi

    # Secret-shaped token in the command/output.
    if printf '%s' "$_cmd" | grep -qE '[A-Za-z0-9_]*(_KEY|_TOKEN|_SECRET)[A-Za-z0-9_]*=|password=|Bearer +|eyJ[A-Za-z0-9_-]+\.'; then
        _gp_block secret_in_output
        return 2
    fi

    # Cross-worktree mutation (heuristic: explicit alternate git dir / -C).
    if printf '%s' "$_cmd" | grep -iqE 'git +-C +|--git-dir=|--work-tree='; then
        _gp_block cross_worktree_mutation
        return 2
    fi

    # Reopen of an issue closed by someone else.
    if printf '%s' "$_cmd" | grep -iqE 'gh +issue +reopen'; then
        local _me="${FAKE_ME:-me}"
        local _by="${FAKE_ISSUE_CLOSED_BY:-$_me}"
        if [ "$_by" != "$_me" ]; then
            _gp_block reopen_foreign_closed
            return 2
        fi
    fi

    printf 'ok\n'
    return 0
}
