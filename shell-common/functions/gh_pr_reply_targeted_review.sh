#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_reply_targeted_review.sh
# Per-reviewer / per-severity gate for gh:pr-reply's `review-blocked`
# invalidation, plus the cheap targeted re-review lane it authorizes
# (issue #1616).
#
# Before #1616 the rule was one global counter pair —
# `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0`. A legitimately DECLINEd
# suggestion from a NON-blocking reviewer then pinned `review-blocked` on a
# PR whose every actual BLOCKER had been fixed (PR #1609: codex raised 2
# BLOCKERs, both fixed; agy raised 3 FOLLOW-UPs, all validly declined), and
# the only way out was a full 5-lane devx:pr-review-all re-run.
#
# The replacement asks a narrower question, per reviewer: "did THIS
# reviewer's blocking-severity items all get accepted?" Only when every
# originally-blocking reviewer answers yes is the targeted lane authorized;
# gh:pr-reply still never certifies itself (NF-2) — the label flip is
# decided by an independent gh:pr-review re-call whose verdict flows through
# `devx_pr_review_all_apply_label` unchanged.
#
# SSOT for the procedure: claude/skills/gh-pr-reply/references/targeted-rereview.md
#
# Deliberately NOT wrapped in an interactive guard: like
# devx_pr_review_all.sh, this is a pure function-defining library whose
# callers are the skill's non-interactive `bash --noprofile --norc` tool
# calls. A guard here would define nothing and the gate would never run.

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
    _dotfiles_root_guard_self "$_drg_self" "gh_pr_reply_targeted_review"
else
    printf '[gh_pr_reply_targeted_review] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# ── F-1: origin tokens ──────────────────────────────────────────────────
#
# One Step 3 classification becomes one `<reviewer>:<severity>:<verdict>`
# line. The reviewer set matches gh:pr-review's `--ai` enum, because the
# targeted lane can only re-invoke a reviewer that skill knows how to run.

_gh_pr_reply_origin_line() {
    local _reviewer _severity _verdict
    _reviewer=$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')
    # Reviewers tag findings as `[BLOCKER]` / `[FOLLOW-UP]`; the brackets are
    # rendering, not data.
    _severity=$(printf '%s' "${2-}" | tr -d '[]' | tr '[:lower:]' '[:upper:]')
    _verdict=$(printf '%s' "${3-}" | tr '[:lower:]' '[:upper:]')

    case "$_reviewer" in
    codex | agy | claude | opencode | hermes) ;;
    *)
        printf '[gh-pr-reply] unknown reviewer: %s (allowed: codex, agy, claude, opencode, hermes)\n' \
            "${1-}" >&2
        return 2
        ;;
    esac
    case "$_severity" in
    "")
        printf '[gh-pr-reply] severity must be a non-empty tag (e.g. BLOCKER, FOLLOW-UP, 블로커): %s\n' \
            "${2-}" >&2
        return 2
        ;;
    *:*)
        printf '[gh-pr-reply] severity must not contain ":" (breaks the reviewer:severity:verdict delimiter): %s\n' \
            "${2-}" >&2
        return 2
        ;;
    esac
    case "$_verdict" in
    ACCEPT | ACCEPT-PARTIAL | DECLINE | QUESTION) ;;
    *)
        printf '[gh-pr-reply] unknown verdict: %s (allowed: ACCEPT, ACCEPT-PARTIAL, DECLINE, QUESTION)\n' \
            "${3-}" >&2
        return 2
        ;;
    esac

    printf '%s:%s:%s\n' "$_reviewer" "$_severity" "$_verdict"
}

# Blocking severity = the tag that made `review-blocked` happen. Everything
# else (FOLLOW-UP, Suggestion, nit, PRAISE) is advisory and its DECLINE must
# never hold the label down — the whole point of #1616.
_gh_pr_reply_severity_is_blocking() {
    case "$(printf '%s' "${1-}" | tr -d '[]' | tr '[:lower:]' '[:upper:]')" in
    BLOCKER | BLOCKING | 블로커) return 0 ;;
    esac
    return 1
}

# Origin lines on stdin -> one summary line per reviewer, sorted by name.
# This is what Step 7's per-reviewer breakdown reports; the flat
# ACCEPTED_COUNT / DECLINED_COUNT pair it replaces could not distinguish
# "a blocker is unresolved" from "a suggestion was declined".
_gh_pr_reply_origin_tally() {
    # `sort` on the whole `reviewer:severity:verdict` line already groups
    # every reviewer's lines into one contiguous block (no two reviewer
    # names in the enum share a prefix), so a flush-on-change over sorted
    # input reports them in order without a second names[]/bubble-sort pass.
    sort | awk -F: '
        NF < 3 { next }
        function flush() {
            if (cur != "")
                printf "reviewer=%s blocking_total=%d blocking_accepted=%d nonblocking_total=%d nonblocking_declined=%d\n", \
                    cur, bt + 0, ba + 0, nt + 0, nd + 0
        }
        {
            if ($1 != cur) { flush(); cur = $1; bt = ba = nt = nd = 0 }
            if ($2 == "BLOCKER" || $2 == "BLOCKING") {
                bt++
                if ($3 == "ACCEPT" || $3 == "ACCEPT-PARTIAL") ba++
            } else {
                nt++
                if ($3 == "DECLINE") nd++
            }
        }
        END { flush() }
    '
}

# ── F-7: can this reviewer's lane run here at all? ──────────────────────
#
# Delegates to gh:pr-review's own precondition
# (`_gh_pr_review_require_ai_cli`) rather than re-deriving it: that helper
# already covers both `command -v <ai-bin>` and the
# `_dotfiles_setup_mode == internal` gate opencode/hermes need. The fallback
# source runs in a subshell so DOTFILES_FORCE_INIT (load-bearing past that
# file's interactive guard) never leaks into the caller's environment.
_gh_pr_reply_lane_available() {
    local _ai="${1-}"
    [ -n "$_ai" ] || return 1
    if command -v _gh_pr_review_require_ai_cli >/dev/null 2>&1; then
        _gh_pr_review_require_ai_cli "$_ai" >/dev/null 2>&1
        return $?
    fi
    (
        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_review.sh" 2>/dev/null || exit 1
        _gh_pr_review_require_ai_cli "$_ai" >/dev/null 2>&1
    )
}

# ── F-2 / F-6 / F-7: the decision ───────────────────────────────────────
#
#   <origin lines> | _gh_pr_reply_targeted_lane_decide <blocking-reviewer>...
#
# Prints exactly one token:
#   lane=<r1>[ <r2>…]        every originally-blocking reviewer is fully
#                            resolved and runnable -> re-review them
#   skip=unresolved-blocker:<r>   F-6 — keep review-blocked, spend nothing
#   skip=cli-unavailable:<r>      F-7 — fall back to the full re-run
#   skip=no-blocking-reviewer     nothing blocked; there is nothing to clear
#
# `<blocking-reviewer>...` is the set that posted a BLOCKING verdict in the
# round that applied `review-blocked` — read off the PR's `ai-review` blocks,
# not off this pass's items.
#
# One unresolved reviewer suppresses the lane for ALL of them: re-reviewing
# a resolved reviewer cannot lift a label another one is still holding, so
# the extra call would buy nothing.
_gh_pr_reply_targeted_lane_decide() {
    local _origins _r _blocking_total _blocking_open _lanes=""

    [ "$#" -gt 0 ] || {
        # Drain stdin so a piped caller never sees EPIPE on the fast path.
        cat >/dev/null
        printf 'skip=no-blocking-reviewer\n'
        return 0
    }

    _origins=$(cat)

    for _r in "$@"; do
        case "$_r" in
        codex | agy | claude | opencode | hermes) ;;
        *)
            printf '[gh-pr-reply] unknown blocking reviewer: %s\n' "$_r" >&2
            return 2
            ;;
        esac
    done

    for _r in "$@"; do
        _blocking_total=$(printf '%s\n' "$_origins" |
            grep -c "^${_r}:\(BLOCKER\|BLOCKING\):" || :)
        _blocking_open=$(printf '%s\n' "$_origins" |
            grep -c "^${_r}:\(BLOCKER\|BLOCKING\):\(DECLINE\|QUESTION\)$" || :)
        # Zero blocking items this pass is NOT a clean bill of health: this
        # reviewer blocked, and nothing here shows the blocker was addressed.
        # "No evidence" must read as unresolved (NF-2's direction).
        if [ "$_blocking_total" -eq 0 ] || [ "$_blocking_open" -ne 0 ]; then
            printf 'skip=unresolved-blocker:%s\n' "$_r"
            return 0
        fi
    done

    for _r in "$@"; do
        if ! _gh_pr_reply_lane_available "$_r"; then
            printf 'skip=cli-unavailable:%s\n' "$_r"
            return 0
        fi
        _lanes="${_lanes:+$_lanes }$_r"
    done

    printf 'lane=%s\n' "$_lanes"
    return 0
}

# ── F-4 / F-5: the Step 7 line ──────────────────────────────────────────
#
# Takes either the decide token or the targeted lane's own verdict as
# `verdict=<blocking|concerns|lgtm|unknown>` (the tokens
# `devx_pr_review_all_verdict` emits). Reporting is the ONLY thing this
# function does — the label itself is written by
# `devx_pr_review_all_apply_label`, so a report line can never become a
# self-certification.
_gh_pr_reply_targeted_lane_report() {
    local _token="${1-}" _who
    case "$_token" in
    verdict=blocking)
        printf '[BLOCKED] 타겟 재검토도 여전히 BLOCKING — 재수정 필요\n'
        ;;
    verdict=lgtm | verdict=concerns)
        printf '[OK] 타겟 재검토 통과 — review-blocked 해제, review-passed 적용\n'
        ;;
    verdict=*)
        printf '[WARN] 타겟 재검토 판정 불명 — review-blocked 유지, 전체 devx:pr-review-all 재실행 필요\n'
        ;;
    skip=unresolved-blocker:*)
        _who="${_token#skip=unresolved-blocker:}"
        printf '[BLOCKED] %s 의 블로커가 미해결 — review-blocked 유지, 타겟 재검토 미실행\n' "$_who"
        ;;
    skip=cli-unavailable:*)
        _who="${_token#skip=cli-unavailable:}"
        printf '[WARN] %s 리뷰어 CLI 를 이 환경에서 실행할 수 없음 — 전체 devx:pr-review-all 재실행 필요\n' "$_who"
        ;;
    skip=no-blocking-reviewer)
        printf '[OK] 원래 블로킹한 리뷰어 없음 — 타겟 재검토 불필요\n'
        ;;
    *)
        printf '[gh-pr-reply] unknown report token: %s\n' "$_token" >&2
        return 2
        ;;
    esac
    return 0
}

# Self-check (issue #724): the skill sources this file in non-interactive
# bash. A syntax error or a rename would leave the gate silently undefined,
# which reads as "no decision" — and a caller that cannot decide must not
# fall back to the old global rule.
for _gprtr_selfcheck_fn in \
    _gh_pr_reply_origin_line \
    _gh_pr_reply_severity_is_blocking \
    _gh_pr_reply_origin_tally \
    _gh_pr_reply_lane_available \
    _gh_pr_reply_targeted_lane_decide \
    _gh_pr_reply_targeted_lane_report; do
    command -v "$_gprtr_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_reply_targeted_review] BUG: %s undefined after source — the #1616 targeted re-review gate will not run.\n' \
        "$_gprtr_selfcheck_fn" >&2
done
unset _gprtr_selfcheck_fn
:
