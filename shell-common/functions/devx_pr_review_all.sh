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

# ── Review verdict -> merge-gate label (issue #1527) ─────────────────
#
# Every gh:pr-review preset mandates a closing verdict line — `판정:
# [LGTM|우려있음|블로킹]` on a Korean-dominant diff, `Verdict:
# [LGTM|CONCERNS|BLOCKING]` otherwise. Until #1527 nothing in the repo read
# it: PR #1518 collected two independent blocking verdicts and merged 32
# minutes later, because the train's only real gate was CI.
#
# That prompt is rendered at runtime by `_gh_pr_review_common_prefix`
# (gh_pr_review.sh), copied verbatim from
# claude/skills/gh-pr-review/references/review-presets.md — reword the tokens
# in either place and the case arm below has to move with them.
#
# These two helpers turn that prose into a label the train can gate on.
# Parsing lives here, in the *producer*, on purpose: if the train parsed
# comment bodies instead, a reviewer changing its output format would
# silently unlock the merge gate. Here a format change makes the lane
# `unknown`, which is fail-closed — no label, no merge.
#
#   devx_pr_review_all_verdict                 # lane output on stdin
#     -> blocking | concerns | lgtm | unknown
#   devx_pr_review_all_aggregate <verdict>...  # one arg per lane that RAN
#     -> label=review-blocked | label=review-passed | label=   (+ lanes=N)
#
# Skipped lanes contribute NO argument — "not checked" and "checked and
# passed" must never collapse into the same state (#1527 확정 사항).

devx_pr_review_all_verdict() {
    local _line _value

    # Normalize before matching: fullwidth colon -> ASCII, strip the markdown
    # a reviewer may wrap the line in, drop a leading list dash. Then keep
    # only lines that *start* with the verdict key — a finding line like
    # `[BLOCKER] a.sh:1 — ...` must never be mistaken for the verdict.
    # A value that opens with `[` is the preset's own template echoed back
    # (`판정: [LGTM|우려있음|블로킹]`) and is dropped; a bracket later in the
    # line is ordinary detail (`판정: 블로킹 [4건]`) and is kept. Last one
    # wins: the presets require the verdict to be the final line.
    _line=$(
        sed -e 's/：/:/g' -e 's/[*`_#>]//g' \
            -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/^[[:space:]]*//' |
            grep -iE '^(판정|verdict)[[:space:]]*:' |
            grep -viE '^(판정|verdict)[[:space:]]*:[[:space:]]*\[' |
            tail -n 1
    )

    if [ -z "$_line" ]; then
        printf 'unknown\n'
        return 0
    fi

    _value=$(
        printf '%s\n' "$_line" |
            sed -e 's/^[^:]*://' -e 's/^[[:space:]]*//' |
            tr '[:lower:]' '[:upper:]'
    )

    case "$_value" in
    블로킹* | BLOCKING*) printf 'blocking\n' ;;
    우려있음* | CONCERNS*) printf 'concerns\n' ;;
    LGTM*) printf 'lgtm\n' ;;
    *) printf 'unknown\n' ;;
    esac
}

devx_pr_review_all_aggregate() {
    local _lanes=0 _blocking=0 _unresolved=0 _v _label

    for _v in "$@"; do
        _lanes=$((_lanes + 1))
        case "$_v" in
        blocking) _blocking=1 ;;
        lgtm | concerns) ;;
        # `unknown` and anything unrecognized are the same thing: the lane
        # ran but its verdict could not be established. Fail closed.
        *) _unresolved=1 ;;
        esac
    done

    if [ "$_blocking" -eq 1 ]; then
        _label="review-blocked"
    elif [ "$_lanes" -eq 0 ] || [ "$_unresolved" -eq 1 ]; then
        _label=""
    else
        _label="review-passed"
    fi

    printf '%s\n' "label=$_label"
    printf '%s\n' "lanes=$_lanes"
    return 0
}
