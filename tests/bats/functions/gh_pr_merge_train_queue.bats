#!/usr/bin/env bats
# tests/bats/functions/gh_pr_merge_train_queue.bats
# Issue #1707 — merge the train's PRs through GitHub's merge queue instead of
# one blocking merge + one full CI cycle per PR:
#   shell-common/functions/gh_pr_merge_train.sh                 (the predicate)
# Source-of-truth fixture: _fixtures/gh_pr_merge_train_queue.sh
#
# Only the shell-common predicates are tested here. The skill-text half (the
# gh-pr:merge Step 3 `--auto` / Step 3.5 `[QUEUED]` blocks and gh-pr:merge-train
# Step 3.6 / Step 0) moved to dEitY719/gh-pr-skills
# tests/bats/gh_pr_merge_train_queue.bats with #2219, pinned to the shipped text.
#
# The bug being fixed: merging serially means every merge advances `main`,
# which puts every remaining queued PR BEHIND, which forces a rebase + a full
# CI cycle per PR. A queue can only batch if MULTIPLE PRs are enqueued before
# any of them is waited on — so the merge has to become fire-and-forget, and
# the completion steps that used to run right after it have to move to a later
# sweep.

load '../test_helper'

FIXTURE='tests/bats/functions/_fixtures/gh_pr_merge_train_queue.sh'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
}

# One `gh pr list --json number,title,state,labels` element.
_pr_json() {
    printf '{"number":%s,"title":"fix: x","state":"%s","labels":%s}' "$1" "$2" "$3"
}

# --------------------------------------------------------------------------
# _gh_pr_merge_train_needs_finalize — the Step 0 sweep predicate
# --------------------------------------------------------------------------
#
# MERGED + `review-passed` is the signal because gh:pr-merge drops that label
# as the LAST step of a completed merge (#1636). A merged PR still carrying it
# is therefore a PR whose completion steps never ran — which is exactly what an
# enqueued (`--auto`) merge leaves behind.

@test "needs-finalize: MERGED + review-passed -> true" {
    run merge_queue_needs_finalize "$(_pr_json 51 MERGED '[{"name":"review-passed"}]')"
    assert_success
}

@test "needs-finalize: an OPEN PR carrying review-passed -> false" {
    # The ordinary pre-merge state of every train candidate. Finalizing one
    # would sync a board to Done for a PR that has not merged.
    run merge_queue_needs_finalize "$(_pr_json 51 OPEN '[{"name":"review-passed"}]')"
    assert_failure
}

@test "needs-finalize: MERGED without the label -> false (already finalized)" {
    # The ordinary immediate-merge path drops the label in the same run, so a
    # PR merged that way must never be finalized a second time.
    run merge_queue_needs_finalize "$(_pr_json 51 MERGED '[]')"
    assert_failure
}

@test "needs-finalize: MERGED with only unrelated labels -> false" {
    run merge_queue_needs_finalize "$(_pr_json 51 MERGED '[{"name":"fix"},{"name":"ai"}]')"
    assert_failure
}

@test "needs-finalize: MERGED + review-passed among other labels -> true" {
    run merge_queue_needs_finalize \
        "$(_pr_json 51 MERGED '[{"name":"fix"},{"name":"review-passed"}]')"
    assert_success
}

@test "needs-finalize: CLOSED + review-passed -> false" {
    # Closed-without-merging has no completion sequence to owe.
    run merge_queue_needs_finalize "$(_pr_json 51 CLOSED '[{"name":"review-passed"}]')"
    assert_failure
}

@test "needs-finalize: a missing state field -> false" {
    run merge_queue_needs_finalize '{"number":51,"labels":[{"name":"review-passed"}]}'
    assert_failure
}

@test "needs-finalize: a missing labels field -> false" {
    run merge_queue_needs_finalize '{"number":51,"state":"MERGED"}'
    assert_failure
}

@test "needs-finalize: malformed JSON -> false, never a crash" {
    run merge_queue_needs_finalize 'not json at all'
    assert_failure
    assert_output ''
}

@test "needs-finalize: review-blocked on a merged PR is not a finalize signal" {
    run merge_queue_needs_finalize "$(_pr_json 51 MERGED '[{"name":"review-blocked"}]')"
    assert_failure
}

@test "needs-finalize: the shared function is defined by the shipped file" {
    # #724's rule: the self-check at the bottom of gh_pr_merge_train.sh must
    # cover the new function, or a rename breaks the sweep silently.
    run grep -qF -- '_gh_pr_merge_train_needs_finalize' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    assert_success
    run bash -c "grep -c '_gh_pr_merge_train_needs_finalize' \
        '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh'"
    # header usage line + definition + self-check list = at least 3
    [ "$output" -ge 3 ]
}

# --------------------------------------------------------------------------
# _gh_pr_merge_train_finalize_targets — the array-level Step 0 filter
# --------------------------------------------------------------------------
#
# Same rule as `_gh_pr_merge_train_filter_targets` (Step 2): the sweep filters
# the whole `gh pr list --json ...` array in one `jq` pass instead of forking
# per element, and Step 0 must call this, not loop over the single-PR
# predicate above.

@test "finalize-targets: keeps only MERGED + review-passed elements" {
    local result
    result=$(merge_queue_finalize_targets \
        "[$(_pr_json 51 MERGED '[{"name":"review-passed"}]'), \
          $(_pr_json 52 OPEN '[{"name":"review-passed"}]'), \
          $(_pr_json 53 MERGED '[]')]")
    run jq -c '[.[].number]' <<<"$result"
    assert_success
    assert_output '[51]'
}

@test "finalize-targets: no matches -> empty array, not a failure" {
    run merge_queue_finalize_targets \
        "[$(_pr_json 51 OPEN '[{"name":"review-passed"}]')]"
    assert_success
    assert_output '[]'
}

@test "finalize-targets: malformed JSON -> failure, never a crash" {
    run merge_queue_finalize_targets 'not json at all'
    assert_failure
}

@test "finalize-targets: the shared function is defined by the shipped file" {
    run grep -qF -- '_gh_pr_merge_train_finalize_targets' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    assert_success
}

# --------------------------------------------------------------------------
# #1707, the change that actually shipped: strict required-status-checks is
# OFF on `main`, so a BEHIND-but-clean PR merges without a local rebase and
# without a fresh CI cycle. Doc: references/strict-mode-relaxation.md
# --------------------------------------------------------------------------

# One `repos/{repo}/rules/branches/{base}` response carrying a
# required_status_checks rule with the given strict flag.
_rules_json() {
    printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}},
             {"type":"required_status_checks","parameters":{
                "strict_required_status_checks_policy":%s,
                "required_status_checks":[{"context":"Lint (mise)"},
                                          {"context":"Shell Lint (mise)"}]}}]' "$1"
}

# One `commits/{base}/check-runs` response.
_checks_json() {
    printf '{"check_runs":[%s]}' "$1"
}

_run_json() {
    printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3"
}

@test "behind-direct: strict off -> a BEHIND PR may merge without a local rebase" {
    run train_behind_may_merge_directly "$(_rules_json false)"
    assert_success
}

@test "behind-direct: strict on -> keep the pre-#1707 local remediation" {
    run train_behind_may_merge_directly "$(_rules_json true)"
    assert_failure
}

@test "behind-direct: no required_status_checks rule -> no, not yes" {
    # "No required checks" does mean GitHub will not block the merge, but it
    # also means the Step 3.6 red-base guard has nothing to watch — so the
    # safety net justifying the shortcut is absent and the shortcut is refused.
    run train_behind_may_merge_directly '[{"type":"pull_request","parameters":{}}]'
    assert_failure
}

@test "behind-direct: an unreadable rules body fails closed" {
    # Never invert this: reading "unknown" as "strict is off" sends the PR to a
    # merge the platform then refuses, burning all three F-5 attempts on a
    # deterministic refusal that no retry can change.
    run train_behind_may_merge_directly 'not json at all'
    assert_failure
    run train_behind_may_merge_directly ''
    assert_failure
}

@test "behind-direct: a second stricter rule wins over a relaxed one" {
    # More than one ruleset can apply to a base; the shortcut is only safe if
    # EVERY applicable required_status_checks rule has strict off.
    run train_behind_may_merge_directly \
        "$(printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false}},
                    {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true}}]')"
    assert_failure
}

@test "base-ci-red: a required check that FAILED on the tip is red" {
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")" \
        'Lint (mise)' 'Shell Lint (mise)'
    assert_success
}

@test "base-ci-red: a NON-required check failing is not red" {
    # This repo's weekly `Contract + drift` audit and its paths-filtered
    # package build both land on main's tip. Halting the train on those would
    # wedge it on a failure no queued PR caused and no merge can clear.
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"'),
                          $(_run_json 'Contract + drift' completed '"failure"')")" \
        'Lint (mise)' 'Shell Lint (mise)'
    assert_failure
}

@test "base-ci-red: a still-running required check is not red" {
    # The ordinary state 30 seconds after a merge. Treating pending as red
    # would stall the train for a full CI cycle after every single merge —
    # exactly the serialisation dropping strict mode was meant to end.
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' in_progress null)")" \
        'Lint (mise)'
    assert_failure
}

@test "base-ci-red: green is a whitelist — an unfamiliar conclusion halts" {
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"startup_failure"')")" \
        'Lint (mise)'
    assert_success
}

@test "base-ci-red: neutral and skipped are green" {
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"neutral"'),
                          $(_run_json 'Shell Lint (mise)' completed '"skipped"')")" \
        'Lint (mise)' 'Shell Lint (mise)'
    assert_failure
}

@test "base-ci-red: no required contexts -> nothing to be red about" {
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    assert_failure
}

@test "base-ci-red: a context name containing a space is matched whole" {
    # `Lint (mise)` word-split would ask about `Lint` and `(mise)`, neither of
    # which exists, and the guard would silently never fire.
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")" \
        'Lint (mise)'
    assert_success
    run train_base_ci_red \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")" \
        'Lint' '(mise)'
    assert_failure
}

@test "base-ci-red: malformed and empty bodies are not 'red'" {
    # This predicate only ever answers "is there PROOF of red"; classifying an
    # unreadable response is the caller's job: the Step 3.6 block in dEitY719/gh-pr-skills
    # skills/merge-train/references/strict-mode-relaxation.md.
    run train_base_ci_red 'not json at all' 'Lint (mise)'
    assert_failure
    run train_base_ci_red '' 'Lint (mise)'
    assert_failure
}

# --------------------------------------------------------------------------
# Doc guards for the relaxation
#
# The guards on gh-pr-merge-train's own references/strict-mode-relaxation.md
# and merge-queue-investigation.md moved out with that skill in #1680. What
# stays is what this repo still ships: the workflows the safety net rests on
# and the self-check list in gh_pr_merge_train.sh.
# --------------------------------------------------------------------------

@test "doc-guard: both required checks really do run on push to the base" {
    # The entire safety net rests on this. If a future edit narrows either
    # workflow to pull_request only, the net silently disappears.
    local wf
    for wf in ci test; do
        run bash -c "sed -n '/^on:/,/^jobs:/p' \
            '${_BATS_REAL_DOTFILES_ROOT}/.github/workflows/${wf}.yml' \
            | grep -A3 'push:' | grep -q 'main'"
        assert_success
    done
}

@test "doc-guard: the new predicates are in the shipped self-check list" {
    # #724's rule: a rename that breaks Step 3.6 must be loud, not silent.
    local f="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    local fn
    for fn in _gh_pr_merge_train_behind_may_merge_directly _gh_pr_merge_train_base_ci_red; do
        run bash -c "sed -n '/^for _gh_pmt_selfcheck_fn in/,/^done/p' '$f' | grep -qF -- '$fn'"
        assert_success
    done
}

# PR #1725's codex BLOCKER 1 — the `review-passed` drop must be the LAST step
# of the post-merge completion sequence — was pinned entirely by ordering
# guards over gh-pr-merge's SKILL.md and references/*.md. Those moved to that
# skill's own repo in #1680.

# --------------------------------------------------------------------------
# PR #1725, codex BLOCKER 2 (agy FOLLOW-UP) — a failed RULES lookup must not
# silently disable the red-base safety net.
#
# The old guard was `[ "$BEHIND_DIRECT" = yes ] && [ -z "$BASE_CHECKS" ]`.
# `_gh_pr_merge_train_behind_may_merge_directly` returns rc 1 for an
# unreadable body just as it does for "strict is on", so a failed rules call
# set BEHIND_DIRECT=no and the halt could never fire — in the exact situation
# with the least information. `_gh_pr_merge_train_base_strict_confirmed`
# answers the exemption question directly instead.
# --------------------------------------------------------------------------

@test "strict-confirmed: strict on everywhere -> yes, this base is exempt" {
    run train_base_strict_confirmed "$(_rules_json true)"
    assert_success
}

@test "strict-confirmed: strict off -> no, this base depends on the net" {
    run train_base_strict_confirmed "$(_rules_json false)"
    assert_failure
}

@test "strict-confirmed: an unreadable body is NOT an exemption" {
    # The whole bug: "we could not read the rules" must never be read as
    # "strict is still on, so this base never needed the guard".
    run train_base_strict_confirmed 'not json at all'
    assert_failure
    run train_base_strict_confirmed ''
    assert_failure
}

@test "strict-confirmed: no required_status_checks rule -> not confirmed" {
    # Symmetric with behind_may_merge_directly's own `length > 0` requirement:
    # zero rules is an absence of evidence, not evidence of strictness.
    run train_base_strict_confirmed '[{"type":"pull_request","parameters":{}}]'
    assert_failure
}

@test "strict-confirmed: one relaxed rule among strict ones -> not confirmed" {
    run train_base_strict_confirmed \
        "$(printf '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true}},
                    {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false}}]')"
    assert_failure
}

@test "strict-confirmed: it is not the negation of behind_may_merge_directly" {
    # Both are rc 1 for an unreadable body and for a base with no rule. A
    # future refactor that made one `! other` would silently re-open the bug.
    local body
    for body in 'not json at all' '[{"type":"pull_request","parameters":{}}]'; do
        run train_behind_may_merge_directly "$body"
        assert_failure
        run train_base_strict_confirmed "$body"
        assert_failure
    done
}

@test "doc-guard: the new predicate is in the shipped self-check list" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    run bash -c "sed -n '/^for _gh_pmt_selfcheck_fn in/,/^done/p' '$f' \
        | grep -qF -- '_gh_pr_merge_train_base_strict_confirmed'"
    assert_success
}

# --------------------------------------------------------------------------
# PR #1725, codex BLOCKER 3 — the finalize sweep must query by LABEL, not by
# recency. `gh pr list --limit 30` lost a still-unfinalized PR forever once 30
# further merges had happened, with no error and no report line.
# --------------------------------------------------------------------------

@test "finalize-targets: gh search's lowercase \"merged\" state matches" {
    # `gh search prs --json state` answers "merged"; `gh pr list` answers
    # "MERGED". A case-sensitive compare would make the new sweep silently
    # return nothing — indistinguishable from "no leftovers".
    local result
    result=$(merge_queue_finalize_targets \
        "[$(_pr_json 51 merged '[{"name":"review-passed"}]')]")
    run jq -c '[.[].number]' <<<"$result"
    assert_success
    assert_output '[51]'
}

@test "needs-finalize: lowercase \"merged\" + review-passed -> true" {
    run merge_queue_needs_finalize "$(_pr_json 51 merged '[{"name":"review-passed"}]')"
    assert_success
}

@test "finalize-targets: lowercase \"closed\" is still not a finalize target" {
    # Search reports a closed-unmerged PR as "closed". Case-insensitivity must
    # not widen the rule beyond MERGED.
    run merge_queue_finalize_targets \
        "[$(_pr_json 51 closed '[{"name":"review-passed"}]')]"
    assert_success
    assert_output '[]'
}

@test "finalize-targets: lowercase \"open\" is still not a finalize target" {
    run merge_queue_finalize_targets \
        "[$(_pr_json 51 open '[{"name":"review-passed"}]')]"
    assert_success
    assert_output '[]'
}

# jq 1.6 exits 0 for `jq -e` on EMPTY input (1.7 exits 4), so an unreadable
# body used to read as "label present" / "shortcut allowed" (#2052).
_feed() { printf '%s' "$1" | "$2"; }

@test "jq-e predicates: empty stdin is rc 1 on every jq version (#2052)" {
    for fn in _gh_pr_merge_train_has_reply_pending_label \
              _gh_pr_merge_train_has_review_blocked_label \
              _gh_pr_merge_train_has_review_passed_label \
              _gh_pr_merge_train_behind_may_merge_directly \
              _gh_pr_merge_train_base_strict_confirmed; do
        run _feed '' "$fn"
        [ "$status" -ne 0 ] || { echo "$fn returned 0 on empty input"; return 1; }
    done
}

@test "jq-e helper: non-empty input still honours the jq -e verdict (#2052)" {
    run _feed '{"labels":[{"name":"review-passed"}]}' _gh_pr_merge_train_has_review_passed_label
    assert_success
    run _feed '{"labels":[]}' _gh_pr_merge_train_has_review_passed_label
    assert_failure
}
