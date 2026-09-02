#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_queue.bats
# Issue #1707 — merge the train's PRs through GitHub's merge queue instead of
# one blocking merge + one full CI cycle per PR:
#   shell-common/functions/gh_pr_merge_train.sh                 (the predicate)
# Source-of-truth fixture: _fixtures/gh_pr_merge_queue.sh
#
# #1680: the gh-pr-merge and gh-pr-merge-train skills moved to their own
# marketplace repos, taking every doc guard that pinned this fixture to their
# SKILL.md / references/*.md with them. The mirror below is unpinned in this
# repo — behaviour is still tested, drift against the skill text is not.
#
# The bug being fixed: merging serially means every merge advances `main`,
# which puts every remaining queued PR BEHIND, which forces a rebase + a full
# CI cycle per PR. A queue can only batch if MULTIPLE PRs are enqueued before
# any of them is waited on — so the merge has to become fire-and-forget, and
# the completion steps that used to run right after it have to move to a later
# sweep.

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_merge_queue.sh'

setup() {
    setup_isolated_home
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    FINALIZE_LOG="${BATS_TEST_TMPDIR}/finalize.log"
    : >"$GH_LOG"
    : >"$FINALIZE_LOG"
    export GH_LOG FINALIZE_LOG
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
    unset -f gh 2>/dev/null || true
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
# gh:pr-merge Step 3 — the `--auto` command
# --------------------------------------------------------------------------

_stub_gh_merge_ok() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        return 0
    }
}

# `--auto` is refused — the state of any repo with allow_auto_merge=false,
# which is dEitY719/dotfiles today. The plain merge must still happen.
_stub_gh_auto_refused() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        case "$*" in
        *--auto*)
            printf 'Auto merge is not allowed for this repository\n' >&2
            return 1
            ;;
        esac
        return 0
    }
}

# Both forms fail — a genuinely unmergeable PR. The SECOND failure is the one
# that surfaces, i.e. exactly what the pre-#1707 skill would have reported.
_stub_gh_both_fail() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        printf 'Pull request is not mergeable\n' >&2
        return 1
    }
}

@test "step3: --auto is in the merge command" {
    _stub_gh_merge_ok
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_success
    run cat "$GH_LOG"
    assert_output --partial 'pr merge 51 --repo acme/widget --rebase --delete-branch --auto'
}

@test "step3: --delete-branch survives the --auto form" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --rebase
    run cat "$GH_LOG"
    assert_output --partial '--delete-branch'
}

@test "step3: the strategy flag is passed through unchanged, never swapped" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --squash
    run cat "$GH_LOG"
    assert_output --partial '--squash --delete-branch --auto'
    refute_output --partial '--rebase'
}

@test "step3: a successful --auto never runs the plain merge too" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --rebase
    run bash -c "grep -c 'pr merge' '$GH_LOG'"
    assert_output "1"
}

@test "step3: a refused --auto falls back to the plain merge" {
    # The load-bearing backward-compatibility guarantee: on a repo where
    # auto-merge is not available, the flag must be a no-op, not a breakage.
    _stub_gh_auto_refused
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_success
    run cat "$GH_LOG"
    assert_output --partial '--rebase --delete-branch --auto'
    assert_output --partial 'pr merge 51 --repo acme/widget --rebase --delete-branch'
}

@test "step3: the fallback merge carries no --auto" {
    _stub_gh_auto_refused
    merge_step3_auto 51 acme/widget github.com --rebase
    run bash -c "grep -c -- '--auto' '$GH_LOG'"
    assert_output "1"
}

@test "step3: the fallback says why it retried" {
    _stub_gh_auto_refused
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_output --partial '[INFO] gh:pr-merge: --auto refused'
    assert_output --partial 'retrying the plain merge'
    assert_output --partial 'Auto merge is not allowed'
}

@test "step3: when both forms fail the failure is not swallowed" {
    _stub_gh_both_fail
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_failure
}

@test "step3: the target host is pinned on both attempts (#1403 / #1407)" {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        case "$*" in
        *--auto*) return 1 ;;
        esac
        return 0
    }
    merge_step3_auto 51 acme/widget ghe.example.com --rebase
    run bash -c "grep -c 'GH_HOST=ghe.example.com' '$GH_LOG'"
    assert_output "2"
}

# --------------------------------------------------------------------------
# gh:pr-merge Step 3.5 — the third outcome
# --------------------------------------------------------------------------

# `gh pr view --json state,...` answers OPEN: accepted by the queue, not merged.
_stub_gh_view_state() {
    # A global, not a `local`: the `gh` function below runs after this helper
    # has returned, so a dynamically-scoped local would already be gone.
    FAKE_PR_STATE="$1"
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        printf '{"state":"%s","mergedAt":null,"headRefName":"wt/issue-1707/1","baseRefName":"main","url":"https://github.com/acme/widget/pull/51"}\n' \
            "$FAKE_PR_STATE"
        return 0
    }
}

@test "step3.5: an OPEN PR after --auto prints the [QUEUED] report" {
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    assert_success
    assert_line --index 0 '[QUEUED] PR #51 added to merge queue — not yet merged'
    assert_line --index 1 '  Branch:  wt/issue-1707/1 → main'
    assert_line --index 2 '  URL:     https://github.com/acme/widget/pull/51'
    [ "${#lines[@]}" -eq 3 ]
}

@test "step3.5: a QUEUED PR runs NONE of the completion sequence" {
    # The whole point: syncing the board, posting ai-metrics, dispatching a
    # post-merge verification or dropping `review-passed` here would all be
    # claims about a merge that has not happened.
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    assert_success
    run cat "$FINALIZE_LOG"
    assert_output ''
}

@test "step3.5: a QUEUED PR is neither [OK] nor [FAIL]" {
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    refute_output --partial '[OK]'
    refute_output --partial '[FAIL]'
}

@test "step3.5: a MERGED PR runs the completion sequence exactly as before" {
    _stub_gh_view_state MERGED
    run merge_step3_5 51 acme/widget github.com
    assert_success
    assert_output --partial '[OK] PR #51 merged'
    run cat "$FINALIZE_LOG"
    assert_output 'finalize:51'
}

@test "step3.5: a CLOSED PR is a failure, not a queue entry" {
    _stub_gh_view_state CLOSED
    run merge_step3_5 51 acme/widget github.com
    assert_output --partial '[FAIL] PR #51 not merged'
    run cat "$FINALIZE_LOG"
    assert_output ''
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
    # unreadable response is the caller's job (train_step3_6 below).
    run train_base_ci_red 'not json at all' 'Lint (mise)'
    assert_failure
    run train_base_ci_red '' 'Lint (mise)'
    assert_failure
}

# --------------------------------------------------------------------------
# Step 3.6 — the per-base guard as a whole
# --------------------------------------------------------------------------

@test "step3.6: relaxed base, green tip -> proceed with the shortcut on" {
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"'),
                          $(_run_json 'Shell Lint (mise)' completed '"success"')")"
    assert_line 'BEHIND_DIRECT=yes'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a red required check halts the merge phase for that base" {
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED] main is red'
    assert_output --partial 'halting the merge phase'
}

@test "step3.6: the halt is a SKIP, never a FAILED" {
    # NF-2 leaves no way to clear a [FAILED], so a red base must never produce
    # one — the next tick proceeds the moment main goes green again.
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    refute_output --partial '[FAILED]'
}

@test "step3.6: an unreadable check-runs body halts a RELAXED base" {
    run train_step3_6 main "$(_rules_json false)" ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: an unreadable check-runs body does NOT halt a strict base" {
    # A base that never relaxed strict mode never depended on this net, and
    # must not start being blocked by a lookup it never needed.
    run train_step3_6 main "$(_rules_json true)" ''
    assert_line 'BEHIND_DIRECT=no'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a strict base with a red tip still halts" {
    # The guard is about the base being broken, not about the shortcut.
    run train_step3_6 main "$(_rules_json true)" \
        "$(_checks_json "$(_run_json 'Shell Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED] main is red'
}

@test "step3.6: an unreadable rules body cannot enable the shortcut" {
    run train_step3_6 main 'not json' "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_line 'BEHIND_DIRECT=no'
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

@test "step3.6: BOTH lookups failing halts — the correlated-outage case" {
    # codex FOLLOW-UP #2. Before #1725 this printed nothing at all: the first
    # branch needed BEHIND_DIRECT=yes (impossible with unreadable rules) and
    # the elif's base_ci_red is rc 1 on an empty body by its own contract.
    run train_step3_6 main '' ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: an unreadable rules body alone halts, even with readable checks" {
    # Not defensive padding: with no rules body, BASE_CONTEXTS is empty, so
    # base_ci_red has nothing to match and a red base reads as green.
    run train_step3_6 main '' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: a MALFORMED body is as unreadable as a failed call" {
    # `-z` alone only catches the `|| BASE_RULES=''` path. A 200 carrying a
    # proxy interstitial is non-empty, and every predicate reading it answers
    # its own fail-closed rc 1 — which is silence, not a halt. Hence the
    # normalisation to the same empty sentinel.
    run train_step3_6 main 'not json' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_output --partial '[SKIPPED] base health unreadable on main'

    run train_step3_6 main "$(_rules_json false)" 'not json either'
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: rules unreadable + checks genuinely RED still halts" {
    # The OR must not let a red base through just because the other call failed.
    run train_step3_6 main 'not json' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED]'
    refute_output --partial '[FAILED]'
}

@test "step3.6: a confirmed-strict base is still exempt from the unreadable halt" {
    # The preserved rule: a base that never relaxed strict mode never depended
    # on this net and must not start being blocked by a lookup it never needed.
    run train_step3_6 main "$(_rules_json true)" ''
    assert_line 'BEHIND_DIRECT=no'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a relaxed base with unreadable checks halts, as before" {
    run train_step3_6 main "$(_rules_json false)" ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: a base with no required-checks rule halts when checks are unreadable" {
    # It cannot be proven strict, so it is not exempt — and with no contexts
    # the red check could never speak for it either.
    run train_step3_6 main '[{"type":"pull_request","parameters":{}}]' ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: the halt never depends on BEHIND_DIRECT any more" {
    # BEHIND_DIRECT is the ROUTING answer; conflating it with safety-net
    # eligibility is the bug. Assert the guard does not mention it.
    # The doc side of this pair (references/strict-mode-relaxation.md) left
    # with the skill in #1680; the fixture is what this repo still ships.
    run grep -F -- '[ "$BEHIND_DIRECT" = yes ] && [ -z "$BASE_CHECKS" ]' \
        "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_queue.sh"
    assert_failure
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
