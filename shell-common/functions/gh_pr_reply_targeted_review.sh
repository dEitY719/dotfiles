#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_reply_targeted_review.sh
# gh:pr-reply's severity gate: the per-item origin tokens (#1616) and the
# `review-passed` decision they now feed (#1636).
#
# Before #1616 the rule was one global counter pair —
# `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0`. A legitimately DECLINEd
# suggestion from a NON-blocking reviewer then pinned `review-blocked` on a
# PR whose every actual BLOCKER had been fixed (PR #1609: codex raised 2
# BLOCKERs, both fixed; agy raised 3 FOLLOW-UPs, all validly declined), and
# the only way out was a full 5-lane devx:pr-review-all re-run.
#
# #1616 replaced that with a per-reviewer / per-severity question and a cheap
# targeted `gh:pr-review --paths` re-call that had to come back non-blocking
# before `review-passed` could be applied. #1636 removes that re-call: it was
# the remaining cost and failure point, and a jammed `gh:pr-merge-train` was
# the recurring symptom.
#
# NF-2, as redefined by #1636: "never self-certify" is DELIBERATELY RELAXED on
# this one path. gh:pr-reply now applies `review-passed` from its own
# judgment — every BLOCKER-severity item ACCEPT/ACCEPT-PARTIAL, or none
# raised — with no external AI CLI in the loop. The verification link that
# remains is the division of labour: the BLOCKERs were FOUND by an external
# reviewer (devx:pr-review-all, which still fans out on every PR and still
# owns `review-blocked`); gh:pr-reply only confirms they were resolved. The
# fail-closed direction is untouched: one unresolved BLOCKER means no
# `review-passed`, ever. Full rationale and the user's explicit trade-off:
# claude/skills/gh-pr-reply/references/constraints.md and
# claude/skills/devx-pr-review-all/references/review-verdict-label.md.
#
# SSOT for the procedure: claude/skills/gh-pr-reply/references/review-passed-gate.md
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
# line. The reviewer set stays pinned to gh:pr-review's `--ai` enum even now
# that nothing re-invokes those CLIs (#1636): a closed enum is what keeps a
# typo'd reviewer name from silently becoming its own tally row, and it keeps
# the token comparable with the `ai-review` blocks on the PR.

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

# ── F-2: the `review-passed` gate (issue #1636) ─────────────────────────
#
#   <origin lines> | _gh_pr_reply_review_passed_gate
#
# Prints exactly one token:
#   pass=no-blocker              no BLOCKER-severity item was raised at all
#   pass=blockers-resolved:<n>   all <n> BLOCKER items are ACCEPT/ACCEPT-PARTIAL
#   hold=unresolved-blocker:<r>  <r> has a BLOCKER that is not resolved
#
# This replaces #1616's `_gh_pr_reply_targeted_lane_decide`, which answered a
# narrower question ("may we spend one scoped gh:pr-review re-call?") and
# needed the caller to supply `BLOCKING_REVIEWERS` off the PR's `ai-review`
# blocks. #1636 removed the re-call, so the gate no longer needs that set:
# the question is simply "did this pass leave an unresolved BLOCKER?".
#
# Two consequences of dropping the reviewer set, both deliberate:
#   - A pass with NO blocking items is `pass=no-blocker`, not "unresolved".
#     Under #1616 the same input read as unresolved because the caller had
#     already asserted that some reviewer blocked; with no such assertion,
#     "nobody raised a BLOCKER" is the ordinary clean-PR case and treating it
#     as a hold would leave every clean PR unlabelled forever.
#   - The FIRST unresolved BLOCKER decides, and its reviewer is named. One
#     unresolved item is enough — this is the fail-closed half of NF-2 and it
#     is untouched by the relaxation.
#
# Blocking severity comes from `_gh_pr_reply_severity_is_blocking`, so the
# Korean `블로커` tag counts here even though `_gh_pr_reply_origin_tally`'s
# awk only groups the ASCII spellings — counting MORE items as blocking is
# the safe direction for a gate that authorizes `review-passed`.
_gh_pr_reply_review_passed_gate() {
    local _origins _line _rev _rest _sev _verd _blocking=0

    # Read stdin whole before deciding: an early `return` mid-loop would leave
    # a piped producer facing EPIPE.
    _origins=$(cat)

    while IFS= read -r _line || [ -n "$_line" ]; do
        [ -n "$_line" ] || continue
        case "$_line" in
        *:*:*) ;;
        *)
            printf '[gh-pr-reply] malformed origin line (want <reviewer>:<severity>:<verdict>): %s\n' \
                "$_line" >&2
            return 2
            ;;
        esac
        _rev="${_line%%:*}"
        _rest="${_line#*:}"
        _sev="${_rest%%:*}"
        _verd=$(printf '%s' "${_rest#*:}" | tr '[:lower:]' '[:upper:]')

        _gh_pr_reply_severity_is_blocking "$_sev" || continue
        _blocking=$((_blocking + 1))
        case "$_verd" in
        ACCEPT | ACCEPT-PARTIAL) ;;
        *)
            printf 'hold=unresolved-blocker:%s\n' "$_rev"
            return 0
            ;;
        esac
    done <<EOF
$_origins
EOF

    if [ "$_blocking" -eq 0 ]; then
        printf 'pass=no-blocker\n'
    else
        printf 'pass=blockers-resolved:%s\n' "$_blocking"
    fi
    return 0
}

# ── The Step 7 line ─────────────────────────────────────────────────────
#
# Renders one gate token. Reporting is the ONLY thing this function does; the
# label is written by `_gh_pr_reply_apply_review_passed` below, which prints
# this line only once the write actually succeeded.
_gh_pr_reply_review_passed_report() {
    local _token="${1-}" _who
    case "$_token" in
    pass=no-blocker)
        printf '[OK] 미해결 BLOCKER 없음(BLOCKER 항목 자체가 없음) — review-passed 적용 (외부 재검토 없음, #1636)\n'
        ;;
    pass=blockers-resolved:*)
        printf '[OK] BLOCKER %s건 전부 해소 — review-blocked 해제, review-passed 적용 (외부 재검토 없음, #1636)\n' \
            "${_token#pass=blockers-resolved:}"
        ;;
    hold=unresolved-blocker:*)
        _who="${_token#hold=unresolved-blocker:}"
        printf '[BLOCKED] %s 의 블로커가 미해결 — review-passed 미부여, review-blocked 유지\n' "$_who"
        ;;
    *)
        printf '[gh-pr-reply] unknown report token: %s\n' "$_token" >&2
        return 2
        ;;
    esac
    return 0
}

# ── Applying `review-passed` from gh:pr-reply's own judgment (#1636) ─────
#
#   <origin lines> | _gh_pr_reply_apply_review_passed <pr> <repo> [host] [head-sha]
#
# Runs the gate, and on `pass=` writes `review-passed` through the shared
# `devx_pr_review_all_write_label` primitive — the same drop-opposite / safe-add
# / #1601-freshness-marker path `devx:pr-review-all` has always used. NOT
# through `devx_pr_review_all_apply_label`: that one takes a stream of reviewer
# verdict tokens, and synthesizing a fake `lgtm` line to feed it would dress
# gh:pr-reply's own judgment up as a reviewer CLI's opinion. The relaxation is
# meant to be visible in the code, not disguised (#1636).
#
# Prints one `[OK]`/`[BLOCKED]`/`[WARN]` line (plus the marker WARN on the one
# path that can produce it). Soft-fail: rc 0 for every labelling outcome — an
# unlabelled PR reads downstream as "not verified", which is the same contract
# as before. Only a usage error is rc 2.
_gh_pr_reply_apply_review_passed() {
    local _pr="${1-}" _repo="${2-}" _host="${3-}" _head_sha="${4-}"
    local _token _write _ok_line _fail_line

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        cat >/dev/null
        printf '[gh-pr-reply] usage: _gh_pr_reply_apply_review_passed <pr> <repo> [host] [head-sha]\n' >&2
        return 2
    fi

    _token=$(_gh_pr_reply_review_passed_gate) || return $?

    case "$_token" in
    hold=*)
        _gh_pr_reply_review_passed_report "$_token"
        return 0
        ;;
    esac

    if ! command -v devx_pr_review_all_write_label >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh" 2>/dev/null || :
    fi
    if ! command -v devx_pr_review_all_write_label >/dev/null 2>&1; then
        printf '[WARN] devx_pr_review_all_write_label 사용 불가 — PR #%s 무라벨 유지\n' "$_pr"
        return 0
    fi

    _write=$(devx_pr_review_all_write_label review-passed "$_pr" "$_repo" "$_host" "$_head_sha")
    # Reporting is shared with `devx_pr_review_all_apply_label`'s write path
    # (`devx_pr_review_all_report_write_result`, devx_pr_review_all.sh) — only
    # the `ok`/generic-failure lines differ between the two callers, which is
    # what the two trailing arguments supply.
    _ok_line=$(_gh_pr_reply_review_passed_report "$_token")
    _fail_line=$(printf '[WARN] PR #%s review-passed 적용 실패 — 미검증으로 취급' "$_pr")
    devx_pr_review_all_report_write_result "$_write" "$_pr" "$_repo" review-passed \
        "$_ok_line" "$_fail_line"
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
    _gh_pr_reply_review_passed_gate \
    _gh_pr_reply_review_passed_report \
    _gh_pr_reply_apply_review_passed; do
    command -v "$_gprtr_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_reply_targeted_review] BUG: %s undefined after source — the #1636 review-passed gate will not run.\n' \
        "$_gprtr_selfcheck_fn" >&2
done
unset _gprtr_selfcheck_fn
:
