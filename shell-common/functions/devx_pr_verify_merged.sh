#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_verify_merged.sh
# Pure arg parser for the devx:pr-verify-merged skill. Mirrors the
# devx_pr_verify_live_parse contract: one `key=value` line per resolved arg
# on success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR merge state, gh auth, clone/build success) belong to the skill
# body.
#
# This file lives under shell-common/functions/, so it is auto-sourced into
# the user's interactive shell. Every variable the parser assigns is `local`
# (house style here — see gh_pr_review.sh) so a call cannot clobber the
# user's `$pr` / `$remote` / `$matrix`. Callers read the stdout `key=value`
# contract, never the shell variables.

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
    _dotfiles_root_guard_self "$_drg_self" "devx_pr_verify_merged"
else
    printf '[devx_pr_verify_merged] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

_devx_pr_verify_merged_pos_int() {
    case "$1" in
    "" | *[!0-9]*) return 1 ;;
    *[!0]*) return 0 ;;
    *) return 1 ;;
    esac
}

# A newline inside a free-form value would inject an extra line into the
# `key=value` stdout contract callers parse line-by-line, forging a field
# that was never passed (#1779 codex BLOCKER). `=` needs no guard — the
# contract splits on the first one, so an embedded `=` stays in the value.
# Returns 1 when "$1" contains a newline.
_devx_pr_verify_merged_no_newline() {
    case "$1" in
    *"
"*) return 1 ;;
    *) return 0 ;;
    esac
}

devx_pr_verify_merged_parse() {
    local pr=""
    local remote="origin"
    local matrix="auto"
    local env_axes=""
    local clone_dir=""
    local diff_check=1
    local issue_mode="create"
    local post_comment=1
    local _remote_set=0
    local _pos_seen=0
    local _pr_set=0
    local _matrix_set=0
    local _env_set=0
    local _clone_dir_set=0
    local _no_issue=0
    local _rest=""
    local _item=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --matrix | --env | --clone-dir)
            [ "$#" -lt 2 ] && {
                echo "missing value for $1" >&2
                return 2
            }
            ;;
        esac
        case "$1" in
        --matrix)
            matrix="$2"
            _matrix_set=1
            shift 2
            ;;
        --matrix=*)
            matrix="${1#--matrix=}"
            _matrix_set=1
            shift
            ;;
        --env)
            env_axes="$2"
            _env_set=1
            shift 2
            ;;
        --env=*)
            env_axes="${1#--env=}"
            _env_set=1
            shift
            ;;
        --clone-dir)
            clone_dir="$2"
            _clone_dir_set=1
            shift 2
            ;;
        --clone-dir=*)
            clone_dir="${1#--clone-dir=}"
            _clone_dir_set=1
            shift
            ;;
        --no-diff-check)
            diff_check=0
            shift
            ;;
        --dry-run)
            issue_mode="dry-run"
            shift
            ;;
        --no-issue)
            _no_issue=1
            shift
            ;;
        --no-comment)
            post_comment=0
            shift
            ;;
        -h | --help | help)
            echo "help_requested=1"
            return 0
            ;;
        -*)
            # Single- and double-dash typos alike are flag errors, not
            # positionals — `-x` must not surface as a PR# complaint.
            echo "Unknown flag: $1" >&2
            return 2
            ;;
        *)
            # `[pr-number] [remote]` with an optional PR#. Discriminator:
            # PR numbers start with a digit (optionally `#`-prefixed, the
            # common GitHub PR notation), git remote names conventionally
            # do not. A leading digit therefore always means "this is the
            # PR#" — `12a` / `#12a` stay a loud PR# error instead of
            # silently becoming a remote name.
            if [ "$_pos_seen" -eq 0 ]; then
                _pos_seen=1
                case "$1" in
                [0-9]* | '#'*)
                    # Stripping `#` is a no-op on a bare digit string, so
                    # one arm covers `123` and `#123` alike.
                    pr="${1#\#}"
                    _pr_set=1
                    ;;
                *)
                    remote="$1"
                    _remote_set=1
                    ;;
                esac
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

    # Gate on "a PR# positional was given", not on `pr` being non-empty: a
    # bare `#` strips to an empty PR# and must still be rejected here
    # instead of silently falling back to PR auto-detection (#1748 codex
    # review, PR #1749).
    if [ "$_pr_set" -eq 1 ]; then
        if ! _devx_pr_verify_merged_pos_int "$pr"; then
            echo "PR# must be a positive integer: '$pr'" >&2
            return 2
        fi
    fi

    # An explicitly passed but empty value is an error for every
    # value-taking flag — silently dropping it would verify a different
    # clone than the user asked for.
    if [ "$_matrix_set" -eq 1 ] && [ -z "$matrix" ]; then
        echo "--matrix value must not be empty" >&2
        return 2
    fi

    if [ "$_env_set" -eq 1 ] && [ -z "$env_axes" ]; then
        echo "--env value must not be empty" >&2
        return 2
    fi

    if [ "$_clone_dir_set" -eq 1 ] && [ -z "$clone_dir" ]; then
        echo "--clone-dir value must not be empty" >&2
        return 2
    fi

    # Both free-form values that reach stdout unescaped. `env_axes` and
    # `matrix` are whitelisted below and `pr` is digits-only, so these two
    # are the whole injection surface.
    if ! _devx_pr_verify_merged_no_newline "$clone_dir"; then
        echo "--clone-dir value must not contain a newline" >&2
        return 2
    fi

    if ! _devx_pr_verify_merged_no_newline "$remote"; then
        echo "remote name must not contain a newline: '$remote'" >&2
        return 2
    fi

    case "$matrix" in
    auto | full) ;;
    *)
        echo "--matrix must be auto or full: '$matrix'" >&2
        return 2
        ;;
    esac

    if [ -n "$env_axes" ]; then
        _rest="${env_axes},"
        while [ -n "$_rest" ]; do
            _item="${_rest%%,*}"
            _rest="${_rest#*,}"
            case "$_item" in
            path | locale | shell | eol) ;;
            *)
                echo "--env axis must be one of path,locale,shell,eol: '$_item'" >&2
                return 2
                ;;
            esac
        done
    fi

    if [ "$_no_issue" -eq 1 ]; then
        issue_mode="none"
    fi

    printf '%s\n' "pr=$pr"
    printf '%s\n' "remote=$remote"
    printf '%s\n' "matrix=$matrix"
    printf '%s\n' "env_axes=$env_axes"
    printf '%s\n' "clone_dir=$clone_dir"
    printf '%s\n' "diff_check=$diff_check"
    printf '%s\n' "issue_mode=$issue_mode"
    printf '%s\n' "post_comment=$post_comment"
    return 0
}
