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
#   devx_pr_review_all_apply_label <pr> <repo> [host] [head-sha] # verdict
#     tokens on stdin -> aggregates, then writes the label to the PR. One
#     `[OK]`/`[WARN]` line. [head-sha], when given, stamps a freshness marker
#     alongside a `review-passed` label (#1601) — see that function's header.
#
# devx_pr_review_all_aggregate reads stdin, NOT positional args — load-bearing,
# not stylistic; see the doc for the zsh bug that forces it.
# devx_pr_review_all_apply_label takes the same stream for the same reason.
#
# Skipped lanes contribute NO line — "not checked" and "checked and passed"
# must never collapse into the same state (#1527 확정 사항).

devx_pr_review_all_verdict() {
    local _line _value _bracket_inner

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
    # Its signature is the bracketed alternation `[A|B|C]` — the pipe sits
    # INSIDE the first bracket pair. Checking for `[` and `|` anywhere in the
    # value (PR #1573 review, agy FOLLOW-UP) misclassified a real verdict
    # with a bracketed trailing detail, e.g. `[BLOCKING] | [5 findings]`, as
    # the template. Extract only the first bracket group's content and test
    # that for a pipe.
    case "$_value" in
    '['*)
        _bracket_inner=$(printf '%s\n' "$_value" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
        case "$_bracket_inner" in
        *'|'*)
            printf 'unknown\n'
            return 0
            ;;
        esac
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
        {
            # A collapsed block — open and close markers on the same line —
            # must be handled before the open-tag rule below: that rule
            # `next`s immediately, so a close tag trailing on that same line
            # would never be inspected (PR #1573 review, agy+codex
            # independently).
            bp = index($0, beg)
            if (bp > 0 && wanted(tagof($0, beg, blen))) {
                bt = tagof($0, beg, blen)
                rest = substr($0, bp + blen + length(bt) + 4)
                fp = index(rest, fin)
                if (fp > 0 && wanted(tagof(rest, fin, flen))) {
                    last = substr(rest, 1, fp - 1)
                    next
                }
                collecting = 1
                buf = ""
                next
            }
            if (collecting && wanted(tagof($0, fin, flen))) {
                collecting = 0
                last = buf
                next
            }
            if (collecting) { buf = buf $0 "\n" }
        }
        END { printf "%s", last }
    '
}

# Aggregate the verdict stream and WRITE the resulting label to the PR.
# This is the producer half of the merge gate (#1564): without it the two
# labels are never issued, `gh:pr-merge-train` reads "not verified" on every
# PR, and the gate degrades into a permanent skip.
#
#   <verdict tokens, one per line> | devx_pr_review_all_apply_label <pr> <repo> [host] [head-sha]
#
# Stdin, not positional args, for the zsh word-splitting reason
# devx_pr_review_all_aggregate's own header gives — a caller staging the
# verdicts in a variable and re-expanding it unquoted loses every lane but
# the first, which is #1527's original defect wearing a new hat.
#
# Contract (SSOT: claude/skills/devx-pr-review-all/references/review-verdict-label.md
# -> "Applying the label"):
#   - The OPPOSITE label is deleted first and unconditionally, so a re-review
#     that flips blocked -> passed cannot leave a consumer seeing both.
#   - The add goes through `_gh_pr_edit_safe_label`, never bare
#     `gh pr edit --add-label`: that silently exits 1 on repos with classic
#     Projects attached (#326). rc 3 means the label is missing in the repo
#     and the helper refused to auto-create it — provision it with
#     `gh:label-bootstrap`.
#   - Soft-fail throughout: rc is 0 for every labelling outcome, because an
#     unlabelled PR already reads as "not verified" downstream. Only a usage
#     error (rc 2) is a caller bug worth failing on.
#   - GH_HOST is pinned per call inside a subshell so a dual-host login cannot
#     write the label to the wrong server (#1403 / #1407), and the caller's own
#     GH_HOST is left untouched.
#
# [head-sha] (#1601): when given AND the resolved label is `review-passed`,
# post one plain issue comment carrying a freshness marker:
#   <!-- review-verdict:review-passed:<head-sha> -->
# `gh:pr-merge-train`'s gate (`_gh_pr_merge_train_review_passed_stale` in
# gh_pr_merge_train.sh) reads this back and compares it against the PR's
# CURRENT headRefOid before trusting the label — a label alone only proves
# some head was reviewed, not that the current one was. Never posted for
# `review-blocked`: a stale block is the safe direction and needs no
# freshness proof. Best-effort — a failed post never changes this function's
# one-line report contract; it is silent on stdout either way.
devx_pr_review_all_apply_label() {
    local _pr="$1" _repo="$2" _host="${3-}" _head_sha="${4-}"
    local _agg _label _lanes _opposite _rc

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        printf '[devx-pr-review-all] usage: devx_pr_review_all_apply_label <pr> <repo> [host]\n' >&2
        return 2
    fi

    _agg=$(devx_pr_review_all_aggregate)
    # `sed`, not `eval`: the values are controlled, but a parser that cannot
    # execute anything is the right default for something that gates a merge.
    _label=$(printf '%s\n' "$_agg" | sed -n 's/^label=//p')
    _lanes=$(printf '%s\n' "$_agg" | sed -n 's/^lanes=//p')

    if [ -z "$_label" ]; then
        printf '[WARN] no reviewer lane produced a verdict — PR #%s left unlabelled\n' "$_pr"
        return 0
    fi

    case "$_label" in
        review-blocked) _opposite=review-passed ;;
        *) _opposite=review-blocked ;;
    esac

    # The add-side helper lives in a sibling library. Both files are
    # auto-sourced into an interactive shell, but the skill's Bash tool calls
    # run `bash --noprofile --norc`, so source it on demand rather than
    # assuming the caller did.
    if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh" 2>/dev/null || :
    fi
    if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1; then
        printf '[WARN] _gh_pr_edit_safe_label unavailable — PR #%s left unlabelled\n' "$_pr"
        return 0
    fi

    (
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        gh api -X DELETE "repos/$_repo/issues/$_pr/labels/$_opposite"
    ) >/dev/null 2>&1 || :

    # `|| _rc=$?`, not a bare subshell followed by `_rc=$?`: this file is
    # sourced into callers that may have `set -e` armed (bats test bodies do),
    # and there errexit fires on the subshell's non-zero exit BEFORE the
    # capture runs — the soft-fail contract would silently become a hard fail
    # on exactly the rc 3 path the caller most needs to report.
    _rc=0
    (
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        _gh_pr_edit_safe_label "$_pr" "$_label" --repo "$_repo"
    ) || _rc=$?

    # #1601 freshness marker: only on a successfully applied `review-passed`,
    # and only when the caller supplied the head sha it reviewed. Best-effort
    # — a failed post is swallowed so it never adds a second stdout line.
    if [ "$_rc" -eq 0 ] && [ "$_label" = "review-passed" ] && [ -n "$_head_sha" ]; then
        (
            if [ -n "$_host" ]; then
                # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
                export GH_HOST="$_host"
            fi
            gh api -X POST "repos/$_repo/issues/$_pr/comments" \
                -f "body=<!-- review-verdict:review-passed:$_head_sha -->"
        ) >/dev/null 2>&1 || :
    fi

    # The backticks below are markdown in the report line (the label name
    # renders as code in a terminal-pasted comment), not command
    # substitution — single-quoted printf formats never expand.
    # shellcheck disable=SC2016
    case "$_rc" in
        0) printf '[OK] PR #%s labelled `%s` (%s lane(s))\n' "$_pr" "$_label" "$_lanes" ;;
        3) printf '[WARN] label `%s` missing in %s — provision it first (gh:label-bootstrap)\n' \
            "$_label" "$_repo" ;;
        *) printf '[WARN] labelling PR #%s failed — treat the PR as unverified\n' "$_pr" ;;
    esac
    return 0
}

# Self-check (issue #724): this file is sourced by the devx:pr-review-all skill
# in non-interactive bash. A syntax error mid-file or a future rename would
# leave the verdict path silently undefined — which reads as "no lane produced
# a verdict", i.e. every PR unlabelled and every merge skipped (#1564).
for _dpra_selfcheck_fn in \
    devx_pr_review_all_parse \
    devx_pr_review_all_verdict \
    devx_pr_review_all_aggregate \
    devx_pr_review_all_lane_block \
    devx_pr_review_all_apply_label; do
    command -v "$_dpra_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[devx_pr_review_all] BUG: %s undefined after source — the review verdict gate will not run. See dotfiles #724 / #1564.\n' \
        "$_dpra_selfcheck_fn" >&2
done
unset _dpra_selfcheck_fn
:
