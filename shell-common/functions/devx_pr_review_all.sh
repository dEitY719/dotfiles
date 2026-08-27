#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_review_all.sh
# Pure arg parser for the devx:pr-review-all skill. Mirrors the
# gh_pr_review_parse contract: one `key=value` line per resolved arg on
# success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR state, gh auth, CLI presence) belong to the skill body.
#
# This file lives under shell-common/functions/, so it is auto-sourced into
# the user's interactive shell. Every variable the parser assigns is `local`
# (house style here — see gh_pr_review.sh) so a call cannot clobber the
# user's `$pr` / `$remote`. Callers read the stdout `key=value` contract,
# never the shell variables.

# Advisory only (issue #1454, propagated by #1505): warn once on stderr when
# this file was sourced from a checkout that is a different git repo than
# $HOME/dotfiles. Never blocks, and deliberately NOT wrapped in an
# interactive guard — this is a pure function-defining library that
# non-interactive skill callers rely on; the guard function is itself a
# silent no-op outside the genuine foreign-checkout case.
#
# The self-path branch must stay here at file top level — zsh rebinds $0 to
# the sourced file (FUNCTION_ARGZERO) only for this file's own statements,
# and inside a function $0 is the function's own name. Plain POSIX sh has
# neither $0-rebinding nor $BASH_SOURCE, and would abort on the bash array
# syntax, hence the $BASH_VERSION arm. Everything after it lives once, in
# _dotfiles_root_guard_self.
if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "devx_pr_review_all"
else
    printf '[devx_pr_review_all] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

devx_pr_review_all_parse() {
    local pr=""
    local remote="origin"
    local reply_mode="inline"
    local reply_delay="8"
    local _no_reply=0
    local _remote_set=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --defer-reply)
            [ "$#" -lt 2 ] && {
                echo "missing value for --defer-reply" >&2
                return 2
            }
            reply_delay="$2"
            reply_mode="defer"
            shift 2
            ;;
        --defer-reply=*)
            reply_delay="${1#--defer-reply=}"
            reply_mode="defer"
            shift
            ;;
        --no-reply)
            _no_reply=1
            shift
            ;;
        -h | --help | help)
            echo "help_requested=1"
            return 0
            ;;
        --*)
            echo "Unknown flag: $1" >&2
            return 2
            ;;
        *)
            if [ -z "$pr" ]; then
                pr="$1"
            elif [ "$_remote_set" -eq 0 ]; then
                remote="$1"
                _remote_set=1
            else
                echo "Unexpected positional arg: $1" >&2
                return 2
            fi
            shift
            ;;
        esac
    done

    case "$pr" in
    "")
        echo "missing required arg: <PR#>" >&2
        return 2
        ;;
    *[!0-9]*)
        echo "PR# must be a positive integer: '$pr'" >&2
        return 2
        ;;
    *[!0]*) ;;
    *)
        echo "PR# must be a positive integer: '$pr'" >&2
        return 2
        ;;
    esac

    if [ "${_no_reply:-0}" -eq 1 ]; then
        reply_mode="none"
    elif [ "$reply_mode" = "defer" ]; then
        case "$reply_delay" in
        "" | *[!0-9]*)
            echo "--defer-reply value must be a positive integer" >&2
            return 2
            ;;
        *[!0]*) ;;
        *)
            echo "--defer-reply value must be a positive integer" >&2
            return 2
            ;;
        esac
    fi

    printf '%s\n' "pr=$pr"
    printf '%s\n' "remote=$remote"
    printf '%s\n' "reply_mode=$reply_mode"
    printf '%s\n' "reply_delay=$reply_delay"
    return 0
}
