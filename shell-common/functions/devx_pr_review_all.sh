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
# Every gh:pr-review preset mandates a closing verdict line — `판정:
# [LGTM|우려있음|블로킹]` on a Korean-dominant diff, `Verdict:
# [LGTM|CONCERNS|BLOCKING]` otherwise. Until #1527 nothing in the repo read
# it: PR #1518 collected two independent blocking verdicts and merged 32
# minutes later, because the train's only real gate was CI.
#
# That prompt is rendered at runtime by `_gh_pr_review_common_prefix`
# (gh_pr_review.sh), copied verbatim from
# claude/skills/gh-pr-review/references/review-presets.md — reword the tokens
# in either place and the case arms below have to move with them.
#
# These three helpers turn that prose into a label the train can gate on.
# Parsing lives here, in the *producer*, on purpose: if the train parsed
# comment bodies instead, a reviewer changing its output format would
# silently unlock the merge gate. Here a format change makes the lane
# `unknown`, which is fail-closed — no label, no merge.
#
#   devx_pr_review_all_lane_block <ai> [<head-sha>]  # comment bodies on stdin
#     -> that lane's raw block, or nothing
#   devx_pr_review_all_verdict                       # lane output on stdin
#     -> blocking | concerns | lgtm | unknown
#   devx_pr_review_all_aggregate                     # verdict tokens on stdin,
#     -> label=review-blocked | label=review-passed | label=   (+ lanes=N)
#
# The aggregate reads stdin, NOT positional args, and that is load-bearing:
# the natural call site `devx_pr_review_all_aggregate $VERDICTS` relies on the
# shell word-splitting an unquoted expansion, which zsh does not do without
# SH_WORD_SPLIT. In zsh every lane's verdict arrived as one argument, so a
# two-lane PR reported `lanes=1` and lost the blocking verdict outright. A
# newline-delimited stream behaves identically in bash, zsh and dash.
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
#
# Step 3 dispatches each lane as a subagent, and `gh:pr-review` guarantees only
# a one-line `[OK] PR #N reviewed by <ai> — comment: <URL>` as its return
# value — the verdict is nowhere in it. Reading the verdict out of a subagent's
# prose would make the merge gate depend on how an agent chose to summarise
# itself; every lane would land on `unknown`, no label would ever be written,
# and the train would skip every PR forever.
#
# So the verdict is read back from the artifact the lane already wrote:
# `gh:pr-review` Step 6 posts the reviewer's raw output wrapped in
# `<!-- ai-review:<ai> -->` markers, synchronously, before it returns. That is
# a durable machine-readable record, not a summary.
#
# The LAST complete block wins: a re-review posts a second comment and its
# verdict supersedes. An unterminated block (a truncated or still-being-written
# comment) is never harvested — half a review is not a verdict.
#
# The optional <head-sha> is the freshness gate. Without it a block from an
# earlier round is indistinguishable from one this run just posted, so a run
# that posted nothing (GH_DISABLE_AI_METRICS=1, --no-post-comment, a failed
# post) silently reuses a stale verdict — and a stale verdict can authorize a
# merge of code it never saw. Given a sha, only `<!-- ai-review:<ai>:<sha> -->`
# blocks match, and a lane with no block for that exact sha yields nothing,
# which reads downstream as `unknown`. Without it, sha-tagged and plain blocks
# both match and no freshness claim is made.
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
