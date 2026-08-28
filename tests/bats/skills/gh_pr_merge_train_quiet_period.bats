#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_quiet_period.bats
# Tests for shell-common/functions/gh_pr_merge_train.sh — the SSOT merge-train
# target filter (#1524).
#
# The filter used to exist twice: as real `jq` in the cron dispatcher and as
# English prose in `claude/skills/gh-pr-merge-train/SKILL.md`. The prose half
# was executed by an LLM, which could skip it — and did, merging PR #1522
# inside the quiet period. This suite covers the one shared implementation both
# call sites now run, plus a drift guard on the skill doc so a future edit
# cannot quietly turn the invocation back into prose.
#
# No PATH stubs: the function is pure over stdin JSON plus a caller-supplied
# `--now`, which is exactly why `--now` is required rather than defaulted to
# `date +%s`. Nothing here mocks a clock.

load '../test_helper'

HELPER="${DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
TRAIN_SKILL="${DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/SKILL.md"
TRAIN_ORDERING="${DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/ordering.md"

setup() {
    # A fixed clock, not `date +%s`: every fixture stamp below is derived from
    # it, so the whole suite is deterministic and independent of when it runs.
    _NOW=1800000000
    # shellcheck source=/dev/null
    . "${HELPER}"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# `_epoch_to_iso` is shared via test_helper.bash (`load '../test_helper'`
# above already pulls it in) — same GNU/BSD/python3 cascade
# tests/bats/tools/pr_merge_train_cron.bats uses, because README.md advertises
# macOS support.

# One `gh pr list --json` element: PR <1>, updated <2> minutes before _NOW,
# draft <3> (default false), labels <4> (raw JSON array, default `[]`).
# `mergeStateStatus` rides along on every fixture so the pass-through test has
# a field the dispatcher never reads to assert on.
_pr() {
    local _stamp
    _stamp=$(_epoch_to_iso "$((_NOW - $2 * 60))") \
        || fail "cannot format a timestamp on this platform"
    printf '{"number":%s,"updatedAt":"%s","isDraft":%s,"labels":%s,"mergeStateStatus":"CLEAN"}' \
        "$1" "${_stamp}" "${3:-false}" "${4:-[]}"
}

# An element whose `updatedAt` cannot be read — raw JSON value <2> spliced in.
_pr_raw_stamp() {
    printf '{"number":%s,"updatedAt":%s,"isDraft":false,"labels":[]}' "$1" "$2"
}

_filter() {
    printf '%s' "$1" | _gh_pr_merge_train_filter_targets --now "${_NOW}"
}

# The PR numbers that survived, one per line.
_kept_numbers() {
    _filter "$1" | jq -r '.[].number'
}

# ---------------------------------------------------------------------------
# Sanity
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: bash syntax check" {
    run bash -n "${HELPER}"
    assert_success
}

@test "gh_pr_merge_train: sourcing defines all four public functions" {
    run bash -c ". '${HELPER}' && command -v _gh_pr_merge_train_quiet_minutes && command -v _gh_pr_merge_train_reply_pending_stale_minutes && command -v _gh_pr_merge_train_filter_targets && command -v _gh_pr_merge_train_has_reply_pending_label"
    assert_success
}

# ---------------------------------------------------------------------------
# The quiet period constant (the one hardcoded 11 in the repo)
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: the quiet period defaults to 11 minutes" {
    run _gh_pr_merge_train_quiet_minutes
    assert_success
    assert_output "11"
}

@test "gh_pr_merge_train: GH_PR_MERGE_TRAIN_QUIET_MINUTES overrides the default" {
    GH_PR_MERGE_TRAIN_QUIET_MINUTES=3 run _gh_pr_merge_train_quiet_minutes
    assert_success
    assert_output "3"
}

@test "gh_pr_merge_train: a non-numeric override falls back to 11" {
    GH_PR_MERGE_TRAIN_QUIET_MINUTES=soon run _gh_pr_merge_train_quiet_minutes
    assert_success
    assert_output --partial "11"
}

# ---------------------------------------------------------------------------
# The reply-pending staleness window (the second, larger constant)
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: the reply-pending staleness window defaults to 90 minutes" {
    run _gh_pr_merge_train_reply_pending_stale_minutes
    assert_success
    assert_output "90"
}

@test "gh_pr_merge_train: GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES overrides the default" {
    GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=25 run _gh_pr_merge_train_reply_pending_stale_minutes
    assert_success
    assert_output "25"
}

@test "gh_pr_merge_train: a non-numeric staleness override falls back to 90" {
    GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=eventually run _gh_pr_merge_train_reply_pending_stale_minutes
    assert_success
    assert_output --partial "90"
}

# The two windows must not be confusable: the staleness window is the larger
# one by construction, and the whole design rests on that ordering.
@test "gh_pr_merge_train: the staleness window is larger than the quiet period" {
    local _quiet _stale
    _quiet=$(_gh_pr_merge_train_quiet_minutes)
    _stale=$(_gh_pr_merge_train_reply_pending_stale_minutes)
    [ "${_stale}" -gt "${_quiet}" ] \
        || fail "staleness ${_stale} must exceed the quiet period ${_quiet}"
}

# ---------------------------------------------------------------------------
# The filter
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: a PR outside the quiet period is kept" {
    run _kept_numbers "[$(_pr 11 30)]"
    assert_success
    assert_output "11"
}

@test "gh_pr_merge_train: a PR inside the quiet period is dropped" {
    run _kept_numbers "[$(_pr 11 2)]"
    assert_success
    assert_output ""
}

@test "gh_pr_merge_train: a draft is dropped however old it is" {
    run _kept_numbers "[$(_pr 11 300 true)]"
    assert_success
    assert_output ""
}

# The #1524 hard skip: the label wins over the quiet period, which is the whole
# point — the quiet period is only a time-based proxy for this question. 30 min
# is well outside the 11-minute quiet period and well inside the 90-minute
# staleness window, so only the label can be the reason this one is dropped.
@test "gh_pr_merge_train: a fresh reply-pending PR is dropped past the quiet period" {
    run _kept_numbers "[$(_pr 11 30 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output ""
}

# The bounded half of the same rule (PR #1545 review, codex BLOCKER): a label
# nobody ever removed must not exclude its PR forever. Past the staleness
# window the label is presumed stale and the PR is judged like any other.
@test "gh_pr_merge_train: a stale reply-pending PR becomes a target again" {
    run _kept_numbers "[$(_pr 11 300 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output "11"
}

# Exactly ON the boundary counts as stale, matching the quiet period's own
# inclusive `<= cutoff`.
@test "gh_pr_merge_train: a reply-pending PR exactly at the staleness boundary is a target" {
    run _kept_numbers "[$(_pr 11 90 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output "11"
}

@test "gh_pr_merge_train: one minute inside the staleness boundary is still dropped" {
    run _kept_numbers "[$(_pr 11 89 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output ""
}

# A stale label buys nothing on its own — the ordinary quiet-period check is
# what the PR falls through TO, not past.
@test "gh_pr_merge_train: staleness expiry does not exempt a PR from the quiet period" {
    GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=1 \
        run _kept_numbers "[$(_pr 11 2 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output ""
}

@test "gh_pr_merge_train: the staleness window is tunable by env var" {
    # 30 min old: dropped at the default 90, kept once the window shrinks to 20.
    GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES=20 \
        run _kept_numbers "[$(_pr 11 30 false '[{"name":"reply-pending"}]')]"
    assert_success
    assert_output "11"
}

# Fail-closed in the second window too: an unreadable stamp must never be read
# as "old enough to ignore the label".
@test "gh_pr_merge_train: a reply-pending PR with an unreadable stamp is dropped" {
    run bash -c ". '${HELPER}'; printf '%s' '[{\"number\":11,\"updatedAt\":null,\"isDraft\":false,\"labels\":[{\"name\":\"reply-pending\"}]}]' | _gh_pr_merge_train_filter_targets --now ${_NOW} | jq -r '.[].number'"
    assert_success
    assert_output ""
}

@test "gh_pr_merge_train: an unrelated label does not drop a PR" {
    run _kept_numbers "[$(_pr 11 30 false '[{"name":"enhancement"},{"name":"ai"}]')]"
    assert_success
    assert_output "11"
}

# Fail-closed: a timestamp the filter cannot read counts as "still inside the
# quiet period". `// empty`, never `// 0` — epoch zero is `<= cutoff` for any
# clock and would count an unreadable PR as a target.
@test "gh_pr_merge_train: a null updatedAt is dropped (fail-closed)" {
    run _kept_numbers "[$(_pr_raw_stamp 11 null)]"
    assert_success
    assert_output ""
}

@test "gh_pr_merge_train: an unparseable updatedAt is dropped (fail-closed)" {
    run _kept_numbers "[$(_pr_raw_stamp 11 '"not-a-timestamp"')]"
    assert_success
    assert_output ""
}

@test "gh_pr_merge_train: a missing updatedAt key is dropped (fail-closed)" {
    run _kept_numbers '[{"number":11,"isDraft":false,"labels":[]}]'
    assert_success
    assert_output ""
}

# Each element is judged on its own — one unreadable sibling must not take the
# whole array down with it.
@test "gh_pr_merge_train: an unreadable stamp does not mask a real target" {
    run _kept_numbers "[$(_pr_raw_stamp 11 null),$(_pr 12 30)]"
    assert_success
    assert_output "12"
}

@test "gh_pr_merge_train: a reply-pending PR does not mask a real target" {
    run _kept_numbers "[$(_pr 11 30 false '[{"name":"reply-pending"}]'),$(_pr 12 30)]"
    assert_success
    assert_output "12"
}

@test "gh_pr_merge_train: an empty array filters to an empty array" {
    run _filter '[]'
    assert_success
    assert_output "[]"
}

# The dispatcher only reads number/updatedAt/isDraft; the skill needs the D-2
# sort keys and the D-1 routing fields off the same output. A filter that
# projected fields away would silently break the skill.
@test "gh_pr_merge_train: surviving elements pass through unchanged" {
    run bash -c ". '${HELPER}'; printf '%s' '[{\"number\":7,\"updatedAt\":\"2020-01-01T00:00:00Z\",\"isDraft\":false,\"labels\":[],\"mergeStateStatus\":\"BEHIND\",\"baseRefName\":\"main\",\"title\":\"t\"}]' | _gh_pr_merge_train_filter_targets --now ${_NOW} | jq -c '.[0]'"
    assert_success
    assert_output --partial '"mergeStateStatus":"BEHIND"'
    assert_output --partial '"baseRefName":"main"'
    assert_output --partial '"title":"t"'
}

# A `gh pr list` without `labels` in its --json projection must still work:
# `.labels[]?` on a missing key yields nothing rather than erroring.
@test "gh_pr_merge_train: a PR list without a labels field still filters" {
    run bash -c ". '${HELPER}'; printf '%s' '[{\"number\":7,\"updatedAt\":\"2020-01-01T00:00:00Z\",\"isDraft\":false}]' | _gh_pr_merge_train_filter_targets --now ${_NOW} | jq -r '.[].number'"
    assert_success
    assert_output "7"
}

@test "gh_pr_merge_train: --minutes overrides the configured quiet period" {
    # 5 minutes old: dropped at the default 11, kept at 2.
    run bash -c ". '${HELPER}'; printf '%s' '$(printf '[%s]' "$(_pr 11 5)")' | _gh_pr_merge_train_filter_targets --now ${_NOW} --minutes 2 | jq -r '.[].number'"
    assert_success
    assert_output "11"
}

# ---------------------------------------------------------------------------
# _gh_pr_merge_train_has_reply_pending_label — the single-PR sibling
# routing-table.md's F-3 re-check calls, instead of hand-rolling its own jq
# match on the same question the array filter above already answers.
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: has_reply_pending_label succeeds when the label is present" {
    run bash -c ". '${HELPER}'; printf '%s' '$(_pr 11 30 false '[{"name":"reply-pending"}]')' | _gh_pr_merge_train_has_reply_pending_label"
    assert_success
}

@test "gh_pr_merge_train: has_reply_pending_label fails when the label is absent" {
    run bash -c ". '${HELPER}'; printf '%s' '$(_pr 11 30)' | _gh_pr_merge_train_has_reply_pending_label"
    assert_failure
}

@test "gh_pr_merge_train: has_reply_pending_label fails when labels is missing entirely" {
    run bash -c ". '${HELPER}'; printf '%s' '{\"number\":11}' | _gh_pr_merge_train_has_reply_pending_label"
    assert_failure
}

# ---------------------------------------------------------------------------
# Usage errors — the secondary defense (rc 1, nothing on stdout)
# ---------------------------------------------------------------------------

@test "gh_pr_merge_train: --now is required" {
    run bash -c ". '${HELPER}'; printf '%s' '[]' | _gh_pr_merge_train_filter_targets"
    assert_failure
    assert_output --partial "usage:"
}

@test "gh_pr_merge_train: a non-numeric --now is refused" {
    run bash -c ". '${HELPER}'; printf '%s' '[]' | _gh_pr_merge_train_filter_targets --now yesterday"
    assert_failure
}

@test "gh_pr_merge_train: unparseable stdin fails rather than answering" {
    run bash -c ". '${HELPER}'; printf '%s' 'not json' | _gh_pr_merge_train_filter_targets --now ${_NOW}"
    assert_failure
}

@test "gh_pr_merge_train: empty stdin fails rather than answering" {
    run bash -c ". '${HELPER}'; printf '' | _gh_pr_merge_train_filter_targets --now ${_NOW}"
    assert_failure
}

# ---------------------------------------------------------------------------
# Drift guard — the skill must CALL the filter, not describe it
# ---------------------------------------------------------------------------
#
# This is the actual fix issue #1524 is about. Reverting the SKILL.md Step 2
# block to bare prose ("drop every PR updated within the last 11 minutes")
# reintroduces the bug without touching a line of shell, so it has to fail
# here instead of drifting silently. Same spirit as the fixture-mirror tests
# that pin doc/code correspondence elsewhere in this suite.

@test "gh_pr_merge_train: the merge-train SKILL.md invokes the shared filter" {
    run grep -qF -- "_gh_pr_merge_train_filter_targets" "${TRAIN_SKILL}"
    assert_success
}

@test "gh_pr_merge_train: the merge-train SKILL.md sources the shared helper" {
    run grep -qF -- "functions/gh_pr_merge_train.sh" "${TRAIN_SKILL}"
    assert_success
}

@test "gh_pr_merge_train: ordering.md names the shared filter, not a parallel one" {
    run grep -qF -- "_gh_pr_merge_train_filter_targets" "${TRAIN_ORDERING}"
    assert_success
}

# ordering.md D-6 promises the quiet period is a backstop for a session that
# died before removing the label. That promise is only true because the hard
# skip expires, so the doc has to name the function that expires it.
@test "gh_pr_merge_train: ordering.md names the staleness window function" {
    run grep -qF -- "_gh_pr_merge_train_reply_pending_stale_minutes" "${TRAIN_ORDERING}"
    assert_success
}

# The other half of the same wedge: the label must come off on EVERY exit path
# of gh:pr-reply, so both the Step 2.5 early exit and Step 6 have to point at
# the one removal block (PR #1545 review, agy BLOCKER).
@test "gh_pr_merge_train: gh-pr-reply removes reply-pending on both exit paths" {
    local _skill="${DOTFILES_ROOT}/claude/skills/gh-pr-reply/SKILL.md"
    local _refs
    _refs=$(grep -cF -- "reply-pending-label-removal.sh.md" "${_skill}")
    [ "${_refs}" -ge 2 ] \
        || fail "gh-pr-reply SKILL.md cites the removal block ${_refs}x; both Step 2.5 and Step 6 must"
}

# 404 is the ordinary inline-run outcome, not a failure — reporting it as WARN
# is what buried real auth/network failures in routine noise.
@test "gh_pr_merge_train: the removal block reports a 404 as OK, not WARN" {
    run grep -qF -- 'HTTP 404' \
        "${DOTFILES_ROOT}/claude/skills/gh-pr-reply/references/reply-pending-label-removal.sh.md"
    assert_success
}

@test "gh_pr_merge_train: the reply-pending label name is spelled the same in all four places" {
    local _f
    for _f in "${HELPER}" \
        "${TRAIN_ORDERING}" \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/reply-pending-label.sh.md" \
        "${DOTFILES_ROOT}/claude/skills/gh-pr-reply/references/reply-pending-label-removal.sh.md"; do
        grep -qF -- "reply-pending" "${_f}" || fail "reply-pending not found in ${_f}"
    done
}

# ---------------------------------------------------------------------------
# The two verdict-label predicates (#1564) — same single-PR shape as the
# reply-pending sibling above. The gate that consumes them is a queue-level
# step, NOT another clause in the array filter: see
# claude/skills/gh-pr-merge-train/references/review-verdict-gate.md.
# ---------------------------------------------------------------------------

_has_blocked() {
    run bash -c ". '${HELPER}'; printf '%s' '$1' | _gh_pr_merge_train_has_review_blocked_label"
}

_has_passed() {
    run bash -c ". '${HELPER}'; printf '%s' '$1' | _gh_pr_merge_train_has_review_passed_label"
}

@test "gh_pr_merge_train: sourcing defines the two verdict-label predicates" {
    run bash -c ". '${HELPER}' && command -v _gh_pr_merge_train_has_review_blocked_label && command -v _gh_pr_merge_train_has_review_passed_label"
    assert_success
}

@test "gh_pr_merge_train: has_review_blocked_label succeeds when the label is present" {
    _has_blocked "$(_pr 11 30 false '[{"name":"review-blocked"}]')"
    assert_success
}

@test "gh_pr_merge_train: has_review_blocked_label fails when the label is absent" {
    _has_blocked "$(_pr 11 30 false '[{"name":"review-passed"}]')"
    assert_failure
}

@test "gh_pr_merge_train: has_review_passed_label succeeds when the label is present" {
    _has_passed "$(_pr 11 30 false '[{"name":"review-passed"}]')"
    assert_success
}

@test "gh_pr_merge_train: has_review_passed_label fails when the label is absent" {
    _has_passed "$(_pr 11 30)"
    assert_failure
}

@test "gh_pr_merge_train: both predicates fail when labels is missing entirely" {
    _has_blocked '{"number":11}'
    assert_failure
    _has_passed '{"number":11}'
    assert_failure
}

# The stale-both case: #1563's invalidation should make it unreachable, but a
# gate on a merge must be deterministic about a state it does not expect.
@test "gh_pr_merge_train: both labels present -> both predicates report present" {
    local _both='[{"name":"review-passed"},{"name":"review-blocked"}]'
    _has_blocked "$(_pr 11 30 false "$_both")"
    assert_success
    _has_passed "$(_pr 11 30 false "$_both")"
    assert_success
}

# The verdict labels must NOT be folded into the array filter: it drops its
# rejects silently, and #1564 requires a visible per-PR [SKIPPED] line.
@test "gh_pr_merge_train: the array filter does NOT drop a review-blocked PR" {
    run _kept_numbers "[$(_pr 11 30 false '[{"name":"review-blocked"}]')]"
    assert_success
    assert_output "11"
}

@test "gh_pr_merge_train: the array filter does NOT drop an unlabelled PR" {
    run _kept_numbers "[$(_pr 11 30)]"
    assert_success
    assert_output "11"
}
