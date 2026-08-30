#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_review_verdict_gate.bats
# The merge train's review verdict gate (#1564, umbrella #1527):
#   claude/skills/gh-pr-merge-train/references/review-verdict-gate.md
#   claude/skills/gh-pr-merge-train/references/routing-table.md
#   claude/skills/gh-pr-merge-train/references/report-format.md
# Source-of-truth fixture: _fixtures/gh_pr_merge_train_review_verdict_gate.sh
#
# Issue #1564 verification checklist:
#   review-blocked / no label / review-passed  -> [SKIPPED] · [SKIPPED] · proceed
#   review-blocked beats a stale review-passed
#   the gate runs AFTER _gh_pr_merge_train_filter_targets, independently of it
#   gh:label-bootstrap provisions both labels and --prune preserves them
#     (covered in tests/bats/skills/gh_label_bootstrap.bats)
#   no code path in the train parses a review comment body

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_merge_train_review_verdict_gate.sh'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# The decision table
# ---------------------------------------------------------------------

@test "gate: review-blocked -> [SKIPPED] with the blocking reason" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: no verdict label at all -> [SKIPPED] review not verified" {
    run train_verdict_gate "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# Absence is the third state and it must stay a skip. Merging an unreviewed PR
# is the failure #1527 reproduced (PR #1518 -> #1520 -> PR #1522); a skip is
# one label away from moving.
@test "gate: an unrelated label is still 'not verified'" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"enhancement"},{"name":"ai"}]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "gate: review-passed alone -> stays in the queue" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

@test "gate: review-passed alongside unrelated labels still proceeds" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"fix"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# #1563's invalidation should make this unreachable, but a gate on a merge has
# to be deterministic about a state it does not expect. Blocked wins.
@test "gate: review-blocked beats a stale review-passed" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: label order does not change the verdict" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# A `gh pr list` whose --json projection omitted `labels` must read as "not
# verified", never as a pass — the same fail-closed direction as everywhere
# else in this train.
@test "gate: a PR object with no labels field is 'not verified'" {
    run train_verdict_gate '{"number":11,"isDraft":false}'
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# ---------------------------------------------------------------------
# routing-table.md F-3 — the mid-run re-check
# ---------------------------------------------------------------------
#
# A deferred devx:pr-review-all pass can add or flip a verdict label minutes
# after Step 2 built the queue. F-3's re-query is the only thing that sees it,
# so the verdict rows have to short-circuit the D-1 table the same way
# `reply-pending` does — before `mergeStateStatus` is read at all.

@test "F-3: a mid-run review-blocked short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3: a mid-run label loss short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3: review-passed lets the PR reach the D-1 table" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# Order among the short-circuits: draft and reply-pending are answered first,
# so their (more specific) reasons are what the report shows.
@test "F-3: draft outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]' true)"
    assert_success
    assert_output 'skip:draft'
}

@test "F-3: reply-pending outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit \
        "$(verdict_pr 11 '[{"name":"reply-pending"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:reply-pending — review reply not yet complete'
}

# ---------------------------------------------------------------------
# Independence from the Step 2 array filter (#1564 verification item)
# ---------------------------------------------------------------------
#
# The two filters answer different questions and a PR must pass BOTH. The
# verdict gate deliberately does NOT live inside
# `_gh_pr_merge_train_filter_targets`: that one drops its rejects silently,
# before the queue exists, and report-format.md documents those PRs as never
# listed — which would hide this gate's entire output.

@test "independence: the array filter passes a review-blocked PR through" {
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh'
        printf '%s' '[{\"number\":11,\"updatedAt\":\"2020-01-01T00:00:00Z\",\"isDraft\":false,\"labels\":[{\"name\":\"review-blocked\"}]}]' \
          | _gh_pr_merge_train_filter_targets --now 1800000000 | jq -r '.[].number'"
    assert_success
    assert_output "11"
}

@test "independence: the gate then rejects that same PR" {
    run train_verdict_gate '{"number":11,"labels":[{"name":"review-blocked"}]}'
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# ---------------------------------------------------------------------
# Doc guards — the fixture above is only trustworthy while the docs agree
# ---------------------------------------------------------------------

@test "doc-guard: review-verdict-gate.md exists and carries the decision table" {
    run grep -q 'review-blocked — reviewer verdict is blocking' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
    run grep -q 'review not verified — no review-passed label' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

@test "doc-guard: review-verdict-gate.md states absence is blocking" {
    run grep -q 'Why absence is blocking' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

# #1564 explicitly rules a time backstop out. A future edit that adds one
# would weaken the gate rather than bound it — fail here instead.
@test "doc-guard: review-verdict-gate.md rules out a time backstop" {
    run grep -q 'Why no time backstop' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
    run grep -qE '_gh_pr_merge_train_review_(blocked|passed)_stale_minutes' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_failure
}

@test "doc-guard: no staleness window function exists for the verdict labels" {
    run grep -qE '_gh_pr_merge_train_review_(blocked|passed)_stale_minutes' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    assert_failure
}

@test "doc-guard: the board Approved gate is not revived" {
    run grep -q 'Not the board `Approved` gate' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

@test "doc-guard: SKILL.md runs the gate and names the shared predicates" {
    run grep -qF -- '_gh_pr_merge_train_has_review_blocked_label' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_has_review_passed_label' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- 'Step 3.5' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: routing-table.md re-checks both verdict labels per PR" {
    run grep -qF -- '_gh_pr_merge_train_has_review_blocked_label' \
        "${SKILL_DIR}/references/routing-table.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_has_review_passed_label' \
        "${SKILL_DIR}/references/routing-table.md"
    assert_success
}

@test "doc-guard: report-format.md tables both new [SKIPPED] reasons" {
    run grep -q 'review-blocked — reviewer verdict is blocking' \
        "${SKILL_DIR}/references/report-format.md"
    assert_success
    run grep -q 'review not verified — no review-passed label' \
        "${SKILL_DIR}/references/report-format.md"
    assert_success
}

# The failure direction is the whole design: parsing here would let a reviewer
# reformatting its verdict line silently UNLOCK the gate.
@test "doc-guard: the train never parses a review comment body" {
    run grep -rqE 'issues/[^ ]*/comments|ai-review:' "${SKILL_DIR}"
    assert_failure
}

# The producer side has to stay the only writer, or the gate becomes circular.
@test "doc-guard: the producer SSOT is linked from the gate doc" {
    run grep -q 'review-verdict-label.md' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

# Without provisioning, _gh_pr_edit_safe_label rc 3 means the producer can
# never issue either label and every PR skips forever (#326).
@test "doc-guard: the gate doc names the provisioning path" {
    run grep -q 'gh:label-bootstrap' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

# ---------------------------------------------------------------------
# Sha-freshness check for `review-passed` (#1601)
# ---------------------------------------------------------------------
#
# The label alone only proves "some head was reviewed" — its only
# invalidation path is a handful of hand-wired call sites, and a manual
# `git push --force-with-lease` or a GitHub web-UI commit advances the head
# with no hook any of them can see. `_gh_pr_merge_train_review_passed_stale`
# closes that gap by verifying a `<!-- review-verdict:review-passed:<sha> -->`
# marker (posted by `devx_pr_review_all_apply_label`) against the PR's actual
# current head, instead of trusting label presence alone.

_freshness_stub() {
    STUB_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$STUB_LOG"
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$STUB_LOG"
        case "$*" in
        *"/comments"*"--jq"*)
            [ "${STUB_COMMENTS_RC:-0}" -eq 0 ] || return "$STUB_COMMENTS_RC"
            printf '%s\n' "$STUB_COMMENTS"
            return 0
            ;;
        *)
            return "${STUB_GH_RC:-0}"
            ;;
        esac
    }
}

@test "freshness: marker_sha reads the sha out of a matching marker" {
    _freshness_stub
    STUB_COMMENTS='some review text
<!-- review-verdict:review-passed:abc1234 -->
more text'
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget
    assert_success
    assert_output 'abc1234'
}

@test "freshness: marker_sha with no marker at all yields nothing" {
    _freshness_stub
    STUB_COMMENTS='just a plain review comment, no marker here'
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget
    assert_success
    assert_output ''
}

@test "freshness: marker_sha takes the LAST marker when re-reviewed" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:1111111 -->
<!-- review-verdict:review-passed:2222222 -->'
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget
    assert_success
    assert_output '2222222'
}

@test "freshness: marker_sha pins GH_HOST on the lookup" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:abc1234 -->'
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget ghe.example.com
    assert_success
    run cat "$STUB_LOG"
    assert_output --partial '[GH_HOST=ghe.example.com]'
}

@test "freshness: a lookup failure yields nothing, not a false match" {
    _freshness_stub
    STUB_COMMENTS_RC=1
    run _gh_pr_merge_train_review_passed_marker_sha 11 acme/widget
    assert_success
    assert_output ''
}

@test "freshness: stale returns TRUE (0) when the marker sha matches nothing" {
    _freshness_stub
    STUB_COMMENTS='no marker in sight'
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef
    assert_success
}

@test "freshness: stale returns TRUE (0) when the marker sha does not match head" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:0000000 -->'
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef
    assert_success
}

@test "freshness: stale returns FALSE (1) when the marker sha matches head" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:deadbeef -->'
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef
    assert_failure
}

@test "freshness: a lookup failure is fail-closed (treated as stale)" {
    _freshness_stub
    STUB_COMMENTS_RC=1
    run _gh_pr_merge_train_review_passed_stale 11 acme/widget '' deadbeef
    assert_success
}

# ---------------------------------------------------------------------
# F-3 integration — the full per-PR form (routing-table.md)
# ---------------------------------------------------------------------

@test "F-3 freshness: review-blocked still wins over everything else" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-blocked"}]')" acme/widget '' deadbeef
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3 freshness: no verdict label at all is still 'not verified'" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[]')" acme/widget '' deadbeef
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3 freshness: a fresh review-passed marker proceeds" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:deadbeef -->'
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef
    assert_success
    assert_output 'proceed'
}

@test "F-3 freshness: a stale review-passed (head advanced) is skipped" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:0000000 -->'
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef
    assert_success
    assert_output 'skip:review-passed label stale — head advanced without invalidation'
}

@test "F-3 freshness: a review-passed label with NO marker at all is skipped" {
    # A manual push, or a repo that never wired the writer, both look like
    # this. #1601's whole point: absence of proof reads as stale, not fresh.
    _freshness_stub
    STUB_COMMENTS='plain comment, no marker'
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef
    assert_success
    assert_output 'skip:review-passed label stale — head advanced without invalidation'
}

@test "F-3 freshness: a stale PR self-heals by dropping the label" {
    _freshness_stub
    STUB_COMMENTS='<!-- review-verdict:review-passed:0000000 -->'
    train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef >/dev/null
    run cat "$STUB_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/11/labels/review-passed'
}

@test "doc-guard: routing-table.md fetches headRefOid for the freshness check" {
    run grep -qF -- 'headRefOid' "${SKILL_DIR}/references/routing-table.md"
    assert_success
}

@test "doc-guard: routing-table.md and review-verdict-gate.md name the freshness predicate" {
    run grep -qF -- '_gh_pr_merge_train_review_passed_stale' "${SKILL_DIR}/references/routing-table.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_review_passed_stale' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

@test "doc-guard: the producer's freshness marker is documented as its only writer" {
    local _producer="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/review-verdict-label.md"
    run grep -qF -- 'review-verdict:review-passed:' "$_producer"
    assert_success
    run grep -qF -- 'devx_pr_review_all_apply_label' "$_producer"
    assert_success
}
