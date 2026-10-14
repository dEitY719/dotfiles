#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/ai_usage.sh
# Thin wrappers (#2155) over the PATH executable tools/custom/ai_usage.sh (also
# ~/.local/bin/ai-usage), which records per-call AI token usage / cost to a
# usage.jsonl and summarises it. Callers: gh_flow.sh, gh_pr_approve.sh,
# gh_pr_reply.sh. Settings reach it only as exported env (AI_USAGE_RETRY_*).

_ai_usage_run() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ai_usage.sh" run "$@"
}

_ai_usage_summary() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ai_usage.sh" summary "$@"
}

_ai_usage_is_transient() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ai_usage.sh" is-transient "$@"
}
