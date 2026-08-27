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

@test "gh_pr_merge_train: sourcing defines all three public functions" {
    run bash -c ". '${HELPER}' && command -v _gh_pr_merge_train_quiet_minutes && command -v _gh_pr_merge_train_filter_targets && command -v _gh_pr_merge_train_has_reply_pending_label"
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

# The #1524 hard skip: the label wins over elapsed time, which is the whole
# point — the quiet period is only a time-based proxy for this question.
@test "gh_pr_merge_train: a reply-pending PR is dropped however old it is" {
    run _kept_numbers "[$(_pr 11 300 false '[{"name":"reply-pending"}]')]"
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
    run _kept_numbers "[$(_pr 11 300 false '[{"name":"reply-pending"}]'),$(_pr 12 30)]"
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

@test "gh_pr_merge_train: the reply-pending label name is spelled the same in all four places" {
    local _f
    for _f in "${HELPER}" \
        "${TRAIN_ORDERING}" \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/reply-pending-label.sh.md" \
        "${DOTFILES_ROOT}/claude/skills/gh-pr-reply/references/reply-pending-label-removal.sh.md"; do
        grep -qF -- "reply-pending" "${_f}" || fail "reply-pending not found in ${_f}"
    done
}
