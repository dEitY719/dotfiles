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

# ── Review verdict -> merge-gate label (issue #1527, fixed in #1562) ──
#
# Turns a reviewer lane's mandatory closing verdict line (`판정: ...` /
# `Verdict: ...`, rendered at runtime by `_gh_pr_review_common_prefix` in
# gh_pr_review.sh) into a label the merge train can gate on. Full rationale —
# the PR #1518 incident, the zsh word-splitting bug, the call-site contract —
# lives in claude/skills/devx-pr-review-all/references/review-verdict-label.md,
# which is the SSOT; this is the implementation.
#
#   devx_pr_review_all_lane_block <ai> [<head-sha>]  # comment bodies on stdin
#     -> that lane's raw block, or nothing
#   devx_pr_review_all_verdict                       # lane output on stdin
#     -> blocking | concerns | lgtm | unknown
#   devx_pr_review_all_aggregate                     # verdict tokens on stdin,
#     -> label=review-blocked | label=review-passed | label=   (+ lanes=N)
#
# devx_pr_review_all_aggregate reads stdin, NOT positional args — load-bearing,
# not stylistic; see the doc for the zsh bug that forces it.
#
# Skipped lanes contribute NO line — "not checked" and "checked and passed"
# must never collapse into the same state (#1527 확정 사항).

devx_pr_review_all_verdict() {
    local _line _value

    # Normalize before matching: fullwidth colon -> ASCII, strip the markdown
    # a reviewer may wrap the line in, drop a leading list dash. Then keep
    # only lines that *start* with the verdict key — a finding line like
    # `[BLOCKER] a.sh:1 — ...` must never be mistaken for the verdict.
    # Last one wins: the presets require the verdict to be the final line.
    _line=$(
        sed -e 's/：/:/g' -e 's/[*`_#>]//g' \
            -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/^[[:space:]]*//' |
            grep -iE '^(판정|verdict)[[:space:]]*:' |
            tail -n 1
    )

    if [ -z "$_line" ]; then
        printf 'unknown\n'
        return 0
    fi

    _value=$(
        printf '%s\n' "$_line" |
            sed -e 's/^[^:]*://' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    )

    # The unanswered preset template echoed back verbatim is not a verdict.
    # Its signature is the bracketed alternation `[A|B|C]` — the value opens
    # with `[` AND carries a `|` inside the brackets. Keying on `|` alone
    # (the #1527 attempt) threw away real answers like `Verdict: BLOCKING |
    # 5 findings`; keying on the leading `[` alone throws away `Verdict:
    # [BLOCKING]`. Both halves are required. The pattern's brackets and pipe
    # are quoted so `case` reads them as literals, not a bracket expression.
    case "$_value" in
    '['*'|'*']'*)
        printf 'unknown\n'
        return 0
        ;;
    esac

    _value=$(
        printf '%s\n' "$_value" |
            sed -e 's/[][]//g' -e 's/^[[:space:]]*//' |
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

    # `|| [ -n "$_v" ]` so a final line with no trailing newline still counts.
    while IFS= read -r _v || [ -n "$_v" ]; do
        [ -n "$_v" ] || continue
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

# Harvest one reviewer lane's raw output from the PR comment bodies on stdin.
# Reads it back from the `<!-- ai-review:<ai> -->` … `<!-- /ai-review:<ai> -->`
# markers `gh:pr-review` Step 6 posts (gh_pr_review.sh) — not from a lane's
# subagent return value, which never carries the verdict. Full rationale:
# claude/skills/devx-pr-review-all/references/review-verdict-label.md.
#
# Contract: the LAST complete block wins (a re-review supersedes); an
# unterminated block is never harvested. The optional <head-sha> is a
# freshness gate — given a sha, only `<!-- ai-review:<ai>:<sha> -->` blocks
# match, and a miss yields nothing (-> `unknown` downstream, fail-closed).
# Without it, sha-tagged and plain blocks both match and no freshness claim
# is made.
devx_pr_review_all_lane_block() {
    [ -n "${1-}" ] || return 0
    awk -v ai="$1" -v sha="${2-}" '
        function tagof(line, pre, plen,   p, rest, e) {
            p = index(line, pre)
            if (p == 0) return ""
            rest = substr(line, p + plen)
            e = index(rest, " -->")
            if (e == 0) return ""
            return substr(rest, 1, e - 1)
        }
        function wanted(t) {
            if (sha != "") return (t == ai ":" sha)
            return (t == ai || substr(t, 1, length(ai) + 1) == ai ":")
        }
        BEGIN {
            # `beg`/`fin`, not `open`/`close`: `close` is an awk built-in and
            # using it as a variable is a syntax error in POSIX awk.
            beg = "<!-- ai-review:"
            fin = "<!-- /ai-review:"
            blen = length(beg)
            flen = length(fin)
        }
        wanted(tagof($0, beg, blen))     { collecting = 1; buf = ""; next }
        collecting && wanted(tagof($0, fin, flen)) {
            collecting = 0; last = buf; next
        }
        collecting                       { buf = buf $0 "\n" }
        END                              { printf "%s", last }
    '
}
