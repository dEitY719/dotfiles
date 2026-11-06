#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/git_worktree_at.sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# gwt at — one-shot unattended dispatch at a local HH:MM (#2355).
#
# Thin frontend: help here, everything else in the bash runner
# tools/custom/gwt_at_dispatch.sh (validation, job JSON, detached waiter,
# list, cancel), so the logic runs under one shell whatever the user's is.
# dotfiles-only: not part of the vendored gwt file set (#2156).

_git_worktree_at_show_help() {
    ux_header "gwt at - schedule a one-shot unattended run"
    ux_info "Usage: gwt at <HH:MM> --wt-name <slug> [OPTIONS] [--prompt <text...>]"
    ux_info ""
    ux_info "At <HH:MM> a detached runner does: gwt spawn --wt-name <slug> ->"
    ux_info "herdr tab in the new worktree -> claude -> types the prompt."
    ux_info "claude runs WITHOUT permission prompts (--dangerously-skip-permissions)."
    ux_info ""
    ux_info "Required:"
    ux_info "  <HH:MM>          Local 24-hour time (e.g. 20:00, 08:30)."
    ux_info "                   Already passed today (or now) -> same time tomorrow."
    ux_info "  --wt-name <slug> Worktree name, as gwt spawn. The herdr agent is"
    ux_info "                   ga-<repo>-<slug> (max 32 chars: keep <slug> short)."
    ux_info ""
    ux_info "Optional (order-independent):"
    ux_info "  --base <ref>     Base branch/commit for the worktree (default: origin/main)"
    ux_info "  --user <account> Claude account (external multi-account PC only;"
    ux_info "                   internal PC warns and uses the default account)."
    ux_info ""
    ux_info "Trailing (must be LAST if used):"
    ux_info "  --prompt <text...>"
    ux_info "                   Task for claude. All remaining tokens are joined"
    ux_info "                   with single spaces. Omit to leave claude idle."
    ux_info ""
    ux_info "Subcommands:"
    ux_info "  list [--all]     Jobs: pending/running/done/failed/cancelled/missed/lost"
    ux_info "  cancel <id>      Cancel a pending job (a fired job is refused)"
    ux_info "  remove <id>      Delete a finished job from the list (pending/running refused)"
    ux_info "  remove --all|-A  Delete every finished job; pending/running are kept"
    ux_info ""
    ux_info "Lifetime: survives terminal close and logout; lost on reboot (list"
    ux_info "shows 'lost'); a wake-up more than 30m late is skipped as 'missed'."
    ux_info "WSL: the distro must keep running until <HH:MM> — an idle VM"
    ux_info "shutdown (wsl --shutdown, vmIdleTimeout) kills the runner too (lost)."
    ux_info ""
    ux_info "Examples:"
    ux_info "  gwt at 20:00 --wt-name issue-92 --prompt /gh-flow:wave 92"
    ux_info "  gwt at 07:30 --wt-name nightly     # 07:30 already passed -> tomorrow"
    ux_info "  gwt at 20:00 --wt-name review --user work --prompt PR 리뷰 반영해"
    ux_info "  gwt at list"
    ux_info "  gwt at cancel 1106-174501-12345"
    ux_info "  gwt at remove 1106-174501-12345"
    ux_info "  gwt at remove --all"
}

git_worktree_at() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    case "${1:-}" in
    "" | -h | --help | help)
        _git_worktree_at_show_help
        return 0
        ;;
    --run)
        # Internal detached half of the runner; never a user entry point.
        ux_error "Unknown argument: --run"
        return 2
        ;;
    esac

    local _ga_runner
    _ga_runner="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/gwt_at_dispatch.sh"
    if [ ! -f "$_ga_runner" ]; then
        ux_error "gwt at runner not found: $_ga_runner"
        return 1
    fi
    bash "$_ga_runner" "$@"
}
