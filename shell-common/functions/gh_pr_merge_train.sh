#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_merge_train.sh
# SSOT for the merge-train target filter (issue #1524).
#
# Background (issue #1524, bug B):
# The filter that decides which of your open PRs the merge train may touch used
# to exist twice — once as real `jq` inside
# `shell-common/tools/custom/pr_merge_train_cron.sh` (`_pmt_target_count`), and
# once as English prose inside `claude/skills/gh-pr-merge-train/SKILL.md`
# ("drop every PR updated within the last 11 minutes and every draft"). Prose is
# executed by an LLM, which can skip it, mis-add the minutes, or read a stale
# clock — and when it does, the train merges a PR whose deferred review-reply
# pass has not landed yet. Both call sites now call the one function below, so
# there is exactly one implementation and one place the number 11 lives.
#
# Usage:
#   _gh_pr_merge_train_quiet_minutes
#   _gh_pr_merge_train_reply_pending_stale_minutes
#   _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_reply_pending_label
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_review_blocked_label
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_review_passed_label
#
# `_gh_pr_merge_train_quiet_minutes`
#   Echo the quiet period in minutes. Default 11; override with the env var
#   GH_PR_MERGE_TRAIN_QUIET_MINUTES. This is the ONE place the number is
#   hardcoded — the cron dispatcher's usage text and
#   `claude/skills/gh-pr-merge-train/references/ordering.md` both cite it.
#   11 = the 4-minute `--defer-reply` window `gh:issue-flow` Step 2.4 schedules
#   + the reply pass's own runtime + slack (D-6).
#
# `_gh_pr_merge_train_reply_pending_stale_minutes`
#   Echo how long a `reply-pending` label is believed, in minutes. Default 90;
#   override with GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES. Same shape as
#   the quiet-period function above, and the same "one place the number lives"
#   rule. 90 is sized as "longer than any healthy deferred reply pass, shorter
#   than a wedged PR is tolerable": 4 minutes of scheduled defer + a
#   `devx:pr-review-all` fan-out + a `gh:pr-reply` pass that on a heavily
#   reviewed PR walks dozens of threads, edits files, commits and pushes —
#   generously an hour — plus slack. It is ~8x the 11-minute quiet period, so
#   the two windows can never be confused for one another, and a dead session's
#   PR rejoins the train within six 15-minute cron ticks rather than never.
#
# `_gh_pr_merge_train_filter_targets`
#   Read a JSON array on stdin — the shape `gh pr list --json ...` answers with
#   — and echo the same array on stdout with every non-target element removed.
#   A surviving element is passed through UNCHANGED, every field included: the
#   dispatcher only reads `number`/`updatedAt`/`isDraft`, but the skill also
#   needs `mergeable`/`mergeStateStatus`/`baseRefName`/`title` for the D-2 sort
#   and the D-1 routing table, so this function must never project fields away.
#
#   An element is DROPPED when any of these holds:
#     1. `.isDraft` is true               — DRAFT is a skip row in the D-1 table.
#     2. `.labels[].name` has `reply-pending` AND `.updatedAt` is newer than
#        `--now` minus the STALENESS window
#        (`_gh_pr_merge_train_reply_pending_stale_minutes`, default 90 minutes)
#                                         — a deferred `gh:pr-reply` pass is
#                                           still plausibly outstanding.
#        Labelling a PR bumps its `updatedAt`, so that stamp is also "when the
#        label was applied, at the earliest". Once it is older than the window,
#        the session that owed the removal is presumed dead and the label is
#        presumed stale: the element stops being dropped by this rule and falls
#        through to rule 3 exactly like an unlabelled PR. That fall-through IS
#        the backstop `ordering.md` D-6 promises — without it, a label nobody
#        ever removes excludes its PR from the train permanently (PR #1545
#        review, codex BLOCKER). A PR sitting exactly ON the boundary counts as
#        stale (`<=`), matching rule 3's own inclusive cutoff.
#     3. `.updatedAt` is newer than `--now` minus the quiet period, OR cannot be
#        read at all (missing / null / unparseable). The unreadable case fails
#        *closed* on purpose: `// empty` (not `// 0`) makes the `as $ts` binding
#        produce nothing and the element vanish, because `// 0` would become
#        epoch zero — `<= $cutoff` for any clock — and count an unreadable PR as
#        a target, the exact direction D-6 exists to prevent. Binding before
#        rule 2 also means an unreadable stamp can never be read as "the label
#        is stale", the same failure in the other window.
#
#   Flags:
#     --now <epoch-seconds>  REQUIRED. The caller supplies the clock reading, so
#                            this function stays pure and deterministic and the
#                            bats suite can test it without mocking `date`.
#     --minutes <n>          Override the quiet period for this call; defaults
#                            to `_gh_pr_merge_train_quiet_minutes`.
#
#   Return codes:
#     0 — filtered array on stdout (possibly `[]`).
#     1 — usage error, or stdin was empty / not parsable JSON. Nothing on
#         stdout. This is a secondary defense only: the dispatcher already ends
#         the tick when `gh pr list` itself fails, and the skill ends the run.
#
# The `reply-pending` label (issue #1524, bug A):
# The quiet period is a *time-based proxy* for "has the deferred review-reply
# pass finished", and time is a bad proxy — a slow reply pass outlives the
# window and the train merges anyway. The label is the real signal, and its
# name is a fixed literal shared by three call sites:
#   - this file      drops any PR carrying it, regardless of the quiet period,
#                    for as long as the label is fresh (see rule 2 above)
#   - devx:pr-review-all  ADDS it on the `defer` branch (Step 5)
#   - gh:pr-reply         REMOVES it when the reply pass completes (Step 6)
# The quiet period stays as the BACKSTOP: PRs opened by hand or by another tool
# never get the label, and a session that died mid-pass never removes it. That
# second case is only reachable because the label EXPIRES — the hard skip is
# bounded by the staleness window, so "the remover died" degrades to "the PR
# waits out the window", not "the PR is never merged again".
#
# `_gh_pr_merge_train_has_reply_pending_label`
#   The same "does `.labels[]` contain `reply-pending`" question, asked of ONE
#   PR object (not an array) on stdin. `_gh_pr_merge_train_filter_targets`
#   above answers it for the whole queue at Step 2; `references/routing-table.md`
#   F-3 asks it again per PR, right before acting, because a label can be
#   *added mid-run* (a deferred devx:pr-review-all pass) after Step 2 already
#   built the queue. Both call sites run this one function so the predicate
#   itself cannot drift apart the way the quiet-minutes number used to (#1524).
#
# The two verdict labels (issue #1564, umbrella #1527):
# `_gh_pr_merge_train_has_review_blocked_label` /
# `_gh_pr_merge_train_has_review_passed_label`
#   Same single-PR-object-on-stdin shape as the reply-pending predicate above,
#   asked of `review-blocked` / `review-passed`. `devx:pr-review-all` Step 3.5
#   is their ONLY writer (`devx-pr-review-all/references/review-verdict-label.md`);
#   the merge train is their only reader, and it reads NOTHING else — no
#   comment-body parsing lives here, deliberately, so a reviewer reformatting
#   its verdict line can never *unlock* the gate.
#
#   These are NOT folded into `_gh_pr_merge_train_filter_targets` above. That
#   filter drops its rejects silently, before the queue exists, and
#   `references/report-format.md` documents those PRs as never listed. #1564
#   requires the opposite: a per-PR `[SKIPPED]` line naming which of the two
#   reasons applied, in the same visibility class as the approval gate's own
#   skip. So the verdict gate is a queue-level step
#   (`references/review-verdict-gate.md`), run over what this file's array
#   filter already let through, and these predicates are what it runs.
#
#   The decision table lives in that reference; the two invariants that make
#   it deterministic are: `review-blocked` wins over a stale `review-passed`
#   if both are somehow present, and the ABSENCE of both is "not verified" —
#   a skip, never a pass. Absence-is-blocking is also why there is no
#   staleness window here to match `reply-pending`'s: that label self-expires
#   because a dead session would otherwise wedge its PR forever, whereas a
#   verdict-less PR is unwedged by one re-review or one human-added label.
#
# NOTE: This file intentionally has NO interactive guard. It is a pure
# function-defining library (no top-level side effects) sourced from two
# non-interactive contexts: the `pr_merge_train_cron.sh` cron dispatcher, and
# the `gh:pr-merge-train` skill's Bash tool calls (Claude Code runs those as
# `bash --noprofile --norc`). An interactive guard would `return 0` before
# defining either function, breaking both with `command not found` — the same
# reason the NOTE exists in gh_pr_edit_safe.sh and gh_project_status.sh
# (PR #497 / issue #720).

# D-6 quiet period, in minutes. The one hardcoded 11 in the repo.
_gh_pr_merge_train_quiet_minutes() {
    local _m="${GH_PR_MERGE_TRAIN_QUIET_MINUTES:-11}"
    case "$_m" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] GH_PR_MERGE_TRAIN_QUIET_MINUTES=%s is not a number — using 11\n' \
                "$_m" >&2
            _m=11
            ;;
    esac
    printf '%s\n' "$_m"
}

# How long a `reply-pending` label is believed, in minutes. Past this, the
# session that owed the removal is presumed dead and the label stops excluding
# its PR — see rule 2 in the header for the sizing rationale.
_gh_pr_merge_train_reply_pending_stale_minutes() {
    local _m="${GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES:-90}"
    case "$_m" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=%s is not a number — using 90\n' \
                "$_m" >&2
            _m=90
            ;;
    esac
    printf '%s\n' "$_m"
}

_gh_pr_merge_train_filter_targets() {
    local _now="" _minutes="" _cutoff _stale_minutes _stale_cutoff _json _out

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --now)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --now requires an argument\n' >&2
                    return 1
                fi
                _now="$2"
                shift 2
                ;;
            --minutes)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --minutes requires an argument\n' >&2
                    return 1
                fi
                _minutes="$2"
                shift 2
                ;;
            *)
                printf '[gh-pr-merge-train] unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    # --now is required rather than defaulted to `date +%s`: a caller that
    # cannot read the clock must decide what that means for itself (the cron
    # dispatcher ends the tick), and a default would quietly paper over it.
    case "$_now" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] usage: _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]\n' >&2
            return 1
            ;;
    esac

    if [ -z "$_minutes" ]; then
        _minutes=$(_gh_pr_merge_train_quiet_minutes)
    fi
    case "$_minutes" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] --minutes must be a non-negative integer: %s\n' "$_minutes" >&2
            return 1
            ;;
    esac

    _cutoff=$((_now - _minutes * 60))

    # No `--stale-minutes` flag to match `--minutes`: nothing needs to vary the
    # staleness window per call the way the dispatcher's usage text varies the
    # quiet period, and the env override already covers operator tuning.
    _stale_minutes=$(_gh_pr_merge_train_reply_pending_stale_minutes)
    _stale_cutoff=$((_now - _stale_minutes * 60))

    _json=$(cat)
    [ -n "$_json" ] || return 1

    # `.labels[]?.name` covers both shapes `gh` answers with: the objects
    # `--json labels` returns, and an absent `labels` key (the dispatcher used
    # to omit the field entirely) — `[]?` on a missing key yields nothing, so a
    # PR list without labels simply never matches.
    #
    # `$ts` is bound BEFORE either time test so an unreadable stamp drops the
    # element outright (an `as` binding over `empty` emits nothing) instead of
    # reaching the staleness test, where a missing value must never be allowed
    # to read as "old enough to ignore the label".
    _out=$(printf '%s' "$_json" \
        | jq --argjson cutoff "$_cutoff" --argjson stale_cutoff "$_stale_cutoff" '
        [ .[]?
          | select((.isDraft // false) | not)
          | (((.updatedAt // "") | fromdateiso8601? // empty)) as $ts
          | select(
              ([ .labels[]?.name? ] | index("reply-pending") | not)
              or ($ts <= $stale_cutoff)
            )
          | select($ts <= $cutoff)
        ]
    ' 2>/dev/null) || return 1
    [ -n "$_out" ] || return 1

    printf '%s\n' "$_out"
}

# Read one PR object (the shape `gh pr view --json labels,...` answers with,
# not an array) on stdin. 0 = it carries the `reply-pending` label, 1 =
# it does not (including malformed / missing `labels`). See the header note
# above for why this exists alongside `_gh_pr_merge_train_filter_targets`
# instead of routing-table.md re-deriving the same jq expression by hand.
_gh_pr_merge_train_has_reply_pending_label() {
    jq -e '[ .labels[]?.name? ] | index("reply-pending")' >/dev/null 2>&1
}

# The two verdict-label predicates (#1564). Same contract as the sibling
# above: one PR object on stdin, 0 = the label is present, 1 = it is not
# (including malformed / missing `labels`). See the header block for why the
# gate that consumes them is a queue-level step rather than another clause in
# `_gh_pr_merge_train_filter_targets`.
_gh_pr_merge_train_has_review_blocked_label() {
    jq -e '[ .labels[]?.name? ] | index("review-blocked")' >/dev/null 2>&1
}

_gh_pr_merge_train_has_review_passed_label() {
    jq -e '[ .labels[]?.name? ] | index("review-passed")' >/dev/null 2>&1
}

# Sha-freshness check for `review-passed` (#1601).
#
# The label alone only proves "some head was reviewed", not "THIS head was
# reviewed". Its only invalidation path is a handful of hand-wired call sites
# (`gh:pr-reply`, `gh:pr-resolve-conflict`, `gh:pr-resolve-outdated`,
# `devx:pr-review-all` Step 4) that drop the label after a push THEY made —
# any other way the head advances (a manual `git push --force-with-lease`, a
# GitHub web-UI commit, a future tool) leaves a stale `review-passed` on a
# commit nobody reviewed, and this gate would trust it. Wiring more call
# sites cannot close that gap in general: a human's local `git push` has no
# hook this repo controls. So the fix lives on the READ side instead — verify
# the label against the head it was actually issued for.
#
# `devx_pr_review_all_apply_label` (shell-common/functions/devx_pr_review_all.sh)
# is the ONLY writer of the sha marker below, posted once as a plain issue
# comment at the moment it applies `review-passed`:
#   <!-- review-verdict:review-passed:<head-sha> -->
# This is NOT the reviewer-verdict comment parsing `review-verdict-gate.md`
# forbids ("Not a comment parser") — that rule is about never re-deriving a
# LGTM/BLOCKING verdict from a reviewer CLI's free-form prose, where a
# reformat could silently unlock the gate. This marker is a fixed, machine-only
# stamp this same subsystem writes for exactly this read; nothing about a
# reviewer's output format touches it.
#
# `_gh_pr_merge_train_review_passed_marker_sha <pr> <repo> [host] <expected-login>`
#   stdout: the sha carried by the LAST such marker POSTED BY
#   `<expected-login>` among the PR's issue comments, or empty if none
#   exists. One `gh api --paginate` call.
#
#   Return code distinguishes "confirmed absent" from "could not check" —
#   load-bearing for the caller (PR #1608 review, agy round-2 BLOCKER: see
#   `_gh_pr_merge_train_review_passed_stale` below for why the distinction
#   matters):
#     0 — the lookup itself succeeded. stdout may still be empty (no
#         matching marker exists) — that is a CONFIRMED absence.
#     1 — the lookup itself failed (network, auth, rate limit, `gh` too
#         old), or `<expected-login>` was missing/invalid so no lookup was
#         even attempted. stdout is always empty here too, but this is an
#         UNDETERMINED answer, not a confirmed absence — the caller must
#         not treat rc 0 and rc 1 the same way.
#
#   `<expected-login>` is REQUIRED and load-bearing (PR #1608 review, agy
#   BLOCKER + codex BLOCKER, independently): without an author check, this
#   function originally trusted a marker string from ANY commenter, not just
#   `devx_pr_review_all_apply_label`. Any PR participant able to leave a
#   comment — a much lower bar than the label-write access needed to attach
#   `review-passed` itself — could then post
#   `<!-- review-verdict:review-passed:<current-head> -->` by hand and defeat
#   the whole freshness check this file exists to add. Filtering to the one
#   login that actually runs this automation pipeline (the same account both
#   `devx:pr-review-all` and `gh:pr-merge-train` authenticate as) closes that:
#   forging a trusted marker now requires the same access as forging the
#   label directly, which is the pre-existing, already-accepted trust
#   boundary (label-write access already gates who can attach `review-passed`
#   at all). A missing/invalid login is treated as "lookup not attempted"
#   (rc 1) rather than falling back to trusting everyone.
#
#   The login validator accepts a plain GitHub username (`[A-Za-z0-9-]+`) or
#   that same shape with a literal `[bot]` suffix (`github-actions[bot]`,
#   `dependabot[bot]`) — the form GitHub gives App-associated identities in
#   `.user.login` (PR #1608 review, agy round-2 BLOCKER: the earlier
#   character class rejected every bracket, so a pipeline authenticating as
#   any bot account could never validate a single marker and this check
#   would fail closed on every PR, permanently). Both accepted shapes are
#   still restricted to letters, digits and hyphens underneath — a login
#   containing `"`, a backslash, or anything else that could break out of the
#   double-quoted jq filter string below is rejected either way, same as
#   before.
_gh_pr_merge_train_review_passed_marker_sha() {
    local _pr="$1" _repo="$2" _host="${3-}" _login="${4-}" _raw _rc _login_base

    _login_base="$_login"
    case "$_login_base" in
        *'[bot]') _login_base="${_login_base%\[bot\]}" ;;
    esac
    case "$_login_base" in
        '' | *[!A-Za-z0-9-]*) return 1 ;;
    esac

    _raw=$( (
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        # per_page=100 (the API max) caps the round trips a busy PR costs —
        # same comments fetched, fewer HTTP calls than the 30-per-page
        # default. It does not change which marker wins: filtering and
        # picking the last match still happens below, over the full history.
        gh api --paginate -f per_page=100 "repos/$_repo/issues/$_pr/comments" \
            --jq ".[] | select(.user.login == \"$_login\") | .body"
    ) 2>/dev/null )
    _rc=$?

    printf '%s\n' "$_raw" |
        grep -oE '<!-- review-verdict:review-passed:[0-9a-f]+ -->' |
        tail -n 1 |
        sed -E 's/^<!-- review-verdict:review-passed:([0-9a-f]+) -->$/\1/'

    return "$_rc"
}

# `_gh_pr_merge_train_review_passed_stale <pr> <repo> <host> <head-oid> <expected-login>`
#   rc 0 — FRESH: the last marker posted by `<expected-login>` matches
#          `<head-oid>` exactly. Proceed normally.
#   rc 1 — STALE, MISMATCH: a marker from `<expected-login>` exists, but its
#          sha does not match `<head-oid>` — positive proof the head moved
#          past the reviewed commit (the original #1601 scenario: a
#          force-push over a reviewed head). Safe for the caller to also drop
#          the label (self-heal): the mismatch is direct evidence, not a
#          guess.
#   rc 2 — STALE, ABSENT: the lookup succeeded but `<expected-login>` never
#          posted a marker at all. Route this PR as unverified THIS TICK —
#          but do NOT self-heal (drop the label). Absence alone does not
#          prove the label is wrong for this head: a PR labeled
#          `review-passed` before this freshness check existed (or by any
#          future skill that legitimately doesn't post the marker) looks
#          identical to a forged one, and destructively stripping every such
#          PR's label the moment this feature ships was flagged
#          independently by agy across two review rounds (PR #1608) as an
#          unacceptable operational cliff — a re-review clears it exactly as
#          cheaply either way, so there is nothing to gain by deleting rather
#          than merely not trusting it.
#   rc 3 — STALE, UNDETERMINED: the underlying lookup itself failed (network,
#          auth, rate limit) or `<expected-login>` was invalid, so nothing
#          was confirmed either way. Route as unverified this tick (fail-
#          closed, same direction #1519's approval gate takes for "policy
#          unreadable") — never self-heal on a check that never completed
#          (PR #1608 review, agy round-2 BLOCKER: a transient blip must not
#          destroy an otherwise-valid label).
#
#   Only rc 1 carries enough evidence to justify deleting the label. rc 2 and
#   rc 3 both route the PR as unverified without touching it — the
#   difference between them is diagnostic only (did the check run at all),
#   not behavioral.
_gh_pr_merge_train_review_passed_stale() {
    local _pr="$1" _repo="$2" _host="$3" _head_oid="$4" _login="$5" _marker_sha _lookup_rc
    _marker_sha=$(_gh_pr_merge_train_review_passed_marker_sha "$_pr" "$_repo" "$_host" "$_login")
    _lookup_rc=$?
    if [ "$_lookup_rc" -ne 0 ]; then
        return 3
    fi
    [ -n "$_marker_sha" ] && [ "$_marker_sha" = "$_head_oid" ] && return 0
    [ -n "$_marker_sha" ] && return 1
    return 2
}

# Self-check (issue #724): catch silent breakage where this file sources
# cleanly but its public functions never get defined — an interactive-guard
# regression, a syntax error mid-file, a future rename. Both call sites treat a
# missing function as a hard failure (the dispatcher ends the tick), but the
# warning is what names the cause. rc stays 0 — sourcing must not fail.
for _gh_pmt_selfcheck_fn in \
    _gh_pr_merge_train_quiet_minutes \
    _gh_pr_merge_train_reply_pending_stale_minutes \
    _gh_pr_merge_train_filter_targets \
    _gh_pr_merge_train_has_reply_pending_label \
    _gh_pr_merge_train_has_review_blocked_label \
    _gh_pr_merge_train_has_review_passed_label \
    _gh_pr_merge_train_review_passed_marker_sha \
    _gh_pr_merge_train_review_passed_stale; do
    command -v "$_gh_pmt_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_merge_train] BUG: %s undefined after source — the merge-train target filter will not run. See dotfiles #724 / #1524.\n' \
        "$_gh_pmt_selfcheck_fn" >&2
done
unset _gh_pmt_selfcheck_fn
:
