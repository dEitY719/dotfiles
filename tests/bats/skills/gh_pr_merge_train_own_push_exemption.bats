#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_own_push_exemption.bats
# Tests for the quiet-period exemption the train grants its OWN pushes (#1708).
#
# The D-6 quiet period drops any PR whose `updatedAt` is too recent, because a
# deferred `gh:pr-reply` pass may still be inbound. But when the train ITSELF is
# what just touched the PR — a Step 4 `BEHIND`/`DIRTY` remediation pushed a
# rebase — there is nothing left to wait for, and the PR is dropped forever on
# every following tick. The fix is an ADDITIVE second pass over the same raw
# list, never a change to `_gh_pr_merge_train_filter_targets` (AC3): that filter
# is the SSOT both this skill and the cron dispatcher run, and
# tests/bats/skills/gh_pr_merge_train_quiet_period.bats still pins its behaviour
# unchanged.
#
# Same purity rule as the sibling suite: the state directory is a parameter, so
# nothing here mocks `git`, `date` or a real git-common-dir.

load '../test_helper'

HELPER="${DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
TRAIN_SKILL="${DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/SKILL.md"
TRAIN_LOOP="${DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/train-loop.md"
TRAIN_ORDERING="${DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/ordering.md"

setup() {
    _NOW=1800000000
    STATE_DIR=$(mktemp -d)
    # shellcheck source=/dev/null
    . "${HELPER}"
}

teardown() {
    [ -n "${STATE_DIR}" ] && rm -rf "${STATE_DIR}"
}

# ---------------------------------------------------------------------------
# Fixtures — same shape as gh_pr_merge_train_quiet_period.bats's `_pr`, plus
# the `headRefOid` field this pass needs (the shared filter never reads it).
# ---------------------------------------------------------------------------

# PR <1>, updated <2> minutes before _NOW, head sha <3>, draft <4> (default
# false), labels <5> (raw JSON array, default `[]`).
_pr_oid() {
    local _stamp
    _stamp=$(_epoch_to_iso "$((_NOW - $2 * 60))") \
        || fail "cannot format a timestamp on this platform"
    printf '{"number":%s,"updatedAt":"%s","headRefOid":"%s","isDraft":%s,"labels":%s,"mergeStateStatus":"CLEAN"}' \
        "$1" "${_stamp}" "$3" "${4:-false}" "${5:-[]}"
}

# RAW on stdin, `<filtered-json>` as the argument — the real call shape.
_readmit() {
    printf '%s' "$1" | _gh_pr_merge_train_readmit_own_pushes "${STATE_DIR}" "$2"
}

_readmit_numbers() {
    _readmit "$1" "$2" | jq -r '.[].number'
}

# ---------------------------------------------------------------------------
# Sanity
# ---------------------------------------------------------------------------

@test "own_push: sourcing defines all four new functions" {
    run bash -c ". '${HELPER}' && command -v _gh_pr_merge_train_record_pushed_sha && command -v _gh_pr_merge_train_pushed_sha_matches && command -v _gh_pr_merge_train_forget_pushed_sha && command -v _gh_pr_merge_train_readmit_own_pushes"
    assert_success
}

# ---------------------------------------------------------------------------
# The state store — record / match / forget
# ---------------------------------------------------------------------------

@test "own_push: a recorded sha matches itself" {
    run _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    assert_success
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 deadbeef
    assert_success
}

@test "own_push: a recorded sha does not match a different sha" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 cafebabe
    assert_failure
}

@test "own_push: no record at all does not match" {
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 deadbeef
    assert_failure
}

# A recorded sha is per-PR: PR 12's record must never answer for PR 11.
@test "own_push: a record for another PR does not match" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 12 deadbeef
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 deadbeef
    assert_failure
}

@test "own_push: an empty or null sha never matches" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 ""
    assert_failure
    # `jq -r '.headRefOid'` on a missing field emits the STRING `null` — a
    # caller's unresolved state, never evidence that this train pushed it.
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 null
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 null
    assert_failure
}

@test "own_push: recording creates the state dir when it does not exist" {
    local _nested="${STATE_DIR}/does/not/exist/yet"
    run _gh_pr_merge_train_record_pushed_sha "${_nested}" 11 deadbeef
    assert_success
    run _gh_pr_merge_train_pushed_sha_matches "${_nested}" 11 deadbeef
    assert_success
}

@test "own_push: re-recording replaces the previous sha" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 cafebabe
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 deadbeef
    assert_failure
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 cafebabe
    assert_success
}

@test "own_push: forgetting a record stops it matching" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _gh_pr_merge_train_forget_pushed_sha "${STATE_DIR}" 11
    assert_success
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" 11 deadbeef
    assert_failure
}

# Cleanup runs after a merge, best-effort — a record that was never written (or
# already gone) is not an error the train should ever notice.
@test "own_push: forgetting a nonexistent record still succeeds" {
    run _gh_pr_merge_train_forget_pushed_sha "${STATE_DIR}" 11
    assert_success
}

# ---------------------------------------------------------------------------
# Path safety — `<pr>` becomes a path component, so it is validated fail-closed
# in all three, the same posture as the login validator in
# `_gh_pr_merge_train_review_passed_marker_sha`.
# ---------------------------------------------------------------------------

@test "own_push: record rejects a non-numeric PR number" {
    run _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" "../escape" deadbeef
    assert_failure
    [ ! -e "${STATE_DIR}/../escape" ] || fail "wrote outside the state dir"
}

@test "own_push: matches rejects a non-numeric PR number" {
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" "../escape" deadbeef
    assert_failure
}

@test "own_push: forget rejects a non-numeric PR number" {
    run _gh_pr_merge_train_forget_pushed_sha "${STATE_DIR}" "11 12"
    assert_failure
}

@test "own_push: an empty PR number is rejected everywhere" {
    run _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" "" deadbeef
    assert_failure
    run _gh_pr_merge_train_pushed_sha_matches "${STATE_DIR}" "" deadbeef
    assert_failure
    run _gh_pr_merge_train_forget_pushed_sha "${STATE_DIR}" ""
    assert_failure
}

# ---------------------------------------------------------------------------
# The readmission pass
# ---------------------------------------------------------------------------

# The #1708 case itself: the train rebased and pushed this PR on an earlier
# run, so `updatedAt` is "just now" and the shared filter dropped it — but the
# sha it carries is the one the train pushed, so nothing is pending on it.
@test "own_push: a PR dropped only by the quiet period is readmitted" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers "[$(_pr_oid 11 2 deadbeef)]" '[]'
    assert_success
    assert_output "11"
}

@test "own_push: a readmitted PR passes through unchanged" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run bash -c "printf '%s' '[$(_pr_oid 11 2 deadbeef)]' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}' '[]'; } | jq -c '.[0]'"
    assert_success
    assert_output --partial '"mergeStateStatus":"CLEAN"'
    assert_output --partial '"headRefOid":"deadbeef"'
}

@test "own_push: a PR with no recorded sha stays excluded" {
    run _readmit_numbers "[$(_pr_oid 11 2 deadbeef)]" '[]'
    assert_success
    assert_output ""
}

# The head moved past what the train pushed — someone else's commit is on it
# now, so the quiet period is doing exactly its job and must stand.
@test "own_push: a stale recorded sha does not readmit" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers "[$(_pr_oid 11 2 cafebabe)]" '[]'
    assert_success
    assert_output ""
}

# AC2: the label always wins. A deferred reply pass is outstanding whatever the
# train did to the branch.
@test "own_push: reply-pending blocks the exemption" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers \
        "[$(_pr_oid 11 2 deadbeef false '[{"name":"reply-pending"}]')]" '[]'
    assert_success
    assert_output ""
}

@test "own_push: an unrelated label does not block the exemption" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers \
        "[$(_pr_oid 11 2 deadbeef false '[{"name":"enhancement"}]')]" '[]'
    assert_success
    assert_output "11"
}

# DRAFT is a skip row in the D-1 table — never a quiet-period drop, so the
# exemption has nothing to release.
@test "own_push: a draft is never readmitted" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers "[$(_pr_oid 11 2 deadbeef true)]" '[]'
    assert_success
    assert_output ""
}

@test "own_push: a PR already in the filtered array is not duplicated" {
    local _p
    _p=$(_pr_oid 11 30 deadbeef)
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run _readmit_numbers "[${_p}]" "[${_p}]"
    assert_success
    assert_output "11"
}

@test "own_push: nothing to readmit leaves the filtered array as it was" {
    run _readmit "[$(_pr_oid 11 2 deadbeef)]" '[]'
    assert_success
    assert_output "[]"
}

@test "own_push: an empty raw array leaves the filtered array as it was" {
    local _p
    _p=$(_pr_oid 12 30 cafebabe)
    run _readmit_numbers '[]' "[${_p}]"
    assert_success
    assert_output "12"
}

# The pass is additive: what the filter kept survives alongside what this
# readmits, and the D-2 sort in Step 2 runs over the union afterwards.
@test "own_push: readmitted PRs are appended to the filtered ones" {
    _gh_pr_merge_train_record_pushed_sha "${STATE_DIR}" 11 deadbeef
    run bash -c "printf '%s' '[$(_pr_oid 11 2 deadbeef),$(_pr_oid 12 30 cafebabe)]' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}' '[$(_pr_oid 12 30 cafebabe)]'; } | jq -r '.[].number' | sort"
    assert_success
    assert_output "11
12"
}

# ---------------------------------------------------------------------------
# Usage errors — rc 1, nothing on stdout (same posture as the shared filter)
# ---------------------------------------------------------------------------

@test "own_push: readmit with missing arguments fails" {
    run bash -c "printf '%s' '[]' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}'; }"
    assert_failure
}

@test "own_push: readmit refuses unparseable raw stdin" {
    run bash -c "printf '%s' 'not json' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}' '[]'; }"
    assert_failure
}

@test "own_push: readmit refuses an unparseable filtered argument" {
    run bash -c "printf '%s' '[]' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}' 'not json'; }"
    assert_failure
}

@test "own_push: readmit refuses empty stdin" {
    run bash -c "printf '' | { . '${HELPER}'; _gh_pr_merge_train_readmit_own_pushes '${STATE_DIR}' '[]'; }"
    assert_failure
}

# ---------------------------------------------------------------------------
# Drift guard — the wiring is what makes any of this reachable
# ---------------------------------------------------------------------------
#
# Both halves live in prose executed by an LLM, so a future edit can drop them
# without touching a line of shell. Same spirit as the quiet-period suite's own
# drift guard on `_gh_pr_merge_train_filter_targets`.

@test "own_push: SKILL.md Step 2 runs the readmission pass" {
    run grep -qF -- "_gh_pr_merge_train_readmit_own_pushes" "${TRAIN_SKILL}"
    assert_success
}

@test "own_push: SKILL.md still asks gh pr list for headRefOid" {
    run grep -qE -- '--json [^|]*headRefOid' "${TRAIN_SKILL}"
    assert_success
}

@test "own_push: train-loop.md records the sha the remediation pushed" {
    run grep -qF -- "_gh_pr_merge_train_record_pushed_sha" "${TRAIN_LOOP}"
    assert_success
}

@test "own_push: train-loop.md forgets the record after a merge" {
    run grep -qF -- "_gh_pr_merge_train_forget_pushed_sha" "${TRAIN_LOOP}"
    assert_success
}

@test "own_push: ordering.md documents the D-6 exemption" {
    run grep -qF -- "_gh_pr_merge_train_readmit_own_pushes" "${TRAIN_ORDERING}"
    assert_success
}

# AC3 made visible in the doc, not only true in code: the shared filter both
# callers run is untouched by this feature.
@test "own_push: ordering.md still names the shared filter as unchanged" {
    run grep -qF -- "_gh_pr_merge_train_filter_targets" "${TRAIN_ORDERING}"
    assert_success
}
