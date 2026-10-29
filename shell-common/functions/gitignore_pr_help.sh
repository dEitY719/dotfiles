#!/bin/sh
# shell-common/functions/gitignore_pr_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gitignore_pr_help_rows_usage() {
    ux_bullet "gitignore-pr                   # list untracked entries, change nothing"
    ux_bullet "gitignore-pr <pattern>...      # add to repo-root .gitignore and open a PR"
    ux_bullet "An existing directory gets a trailing / (.omo -> .omo/); anything else is added as typed"
}

_gitignore_pr_help_rows_flow() {
    ux_numbered 1 "Check: git repo, gh CLI, origin is a GitHub remote, no staged/unstaged changes"
    ux_numbered 2 "Skip patterns already in origin/<default>'s .gitignore (.omo and .omo/ are the same)"
    ux_numbered 3 "Create chore/gitignore-<slug> from origin/<default>, not from the current branch"
    ux_numbered 4 "Commit 'chore: ignore <patterns>', push to origin, gh pr create --repo <host>/<owner>/<repo>"
    ux_numbered 5 "Switch back to the branch you started on (success or failure)"
}

_gitignore_pr_help_rows_safety() {
    ux_bullet "Fails on any staged/unstaged change, including .gitignore — untracked files are fine"
    ux_bullet "Fails if chore/gitignore-<slug> already exists locally or on origin (never overwrites)"
    ux_bullet "No force-push, no --no-verify: a failing hook stops the run and the empty branch is deleted"
    ux_bullet "Push or PR failure keeps the branch and commit and prints the retry command"
}

_gitignore_pr_help_rows_example() {
    ux_bullet "gitignore-pr .omo .superpowers   # -> chore/gitignore-omo-superpowers"
}

_gitignore_pr_help_full() {
    ux_header "gitignore-pr - .gitignore entry to PR in one shot"
    ux_section "Usage"
    _gitignore_pr_help_rows_usage
    ux_section "Flow"
    _gitignore_pr_help_rows_flow
    ux_section "Safety"
    _gitignore_pr_help_rows_safety
    ux_section "Example"
    _gitignore_pr_help_rows_example
}

gitignore_pr_help() {
    case "${1:-}" in
        "" | -h | --help | help | --all | all) _gitignore_pr_help_full ;;
        --list | list | section | sections)
            ux_bullet "sections"
            ux_bullet_sub "usage | flow | safety | example"
            ;;
        usage) _gitignore_pr_help_rows_usage ;;
        flow) _gitignore_pr_help_rows_flow ;;
        safety) _gitignore_pr_help_rows_safety ;;
        example | examples) _gitignore_pr_help_rows_example ;;
        *)
            ux_error "Unknown gitignore-pr-help section: $1"
            ux_info "Try: gitignore-pr-help --list"
            return 1
            ;;
    esac
}

alias gitignore-pr-help='gitignore_pr_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help gitignore_pr_help "[Development] .gitignore 추가부터 PR 생성까지 원샷" development
