#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_queue.bats
# Issue #1707 — merge the train's PRs through GitHub's merge queue instead of
# one blocking merge + one full CI cycle per PR:
#   claude/skills/gh-pr-merge/SKILL.md                          (Step 1/3/3.5)
#   claude/skills/gh-pr-merge/references/finalize-merged-pr.sh.md
#   claude/skills/gh-pr-merge-train/SKILL.md                    (Step 0 sweep)
#   claude/skills/gh-pr-merge-train/references/report-format.md ([QUEUED])
#   shell-common/functions/gh_pr_merge_train.sh                 (the predicate)
# Source-of-truth fixture: _fixtures/gh_pr_merge_queue.sh
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
    MERGE_SKILL="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge"
    TRAIN_SKILL="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train"
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
# Doc guards — the blocks above exist only as prose in a SKILL.md
# --------------------------------------------------------------------------

@test "doc-guard: SKILL.md Step 3 and the fixture have not drifted apart" {
    local pat f
    for pat in \
        '"$STRATEGY_FLAG" --delete-branch --auto 2>&1); then' \
        '[INFO] gh:pr-merge: --auto refused (%s) — retrying the plain merge.' \
        '[QUEUED] PR #' \
        'added to merge queue — not yet merged' \
        '  Branch:  ' \
        '  URL:     '; do
        for f in "${MERGE_SKILL}/SKILL.md" \
            "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_queue.sh"; do
            run grep -F -- "$pat" "$f"
            assert_success
        done
    done
}

@test "doc-guard: gh:pr-merge documents both new flags" {
    local f
    for f in "${MERGE_SKILL}/SKILL.md" "${MERGE_SKILL}/references/help.md"; do
        run grep -qF -- '--auto' "$f"
        assert_success
        run grep -qF -- '--finalize' "$f"
        assert_success
    done
}

@test "doc-guard: --finalize refuses a PR that is not MERGED" {
    run grep -qF -- 'expected MERGED' "${MERGE_SKILL}/SKILL.md"
    assert_success
}

@test "doc-guard: the finalize sequence has one SSOT, cited by both callers" {
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    [ -r "$doc" ]
    run grep -qF -- 'references/finalize-merged-pr.sh.md' "${MERGE_SKILL}/SKILL.md"
    assert_success
    run grep -qF -- 'finalize-merged-pr.sh.md' "${TRAIN_SKILL}/SKILL.md"
    assert_success
}

@test "doc-guard: the finalize SSOT names every step of the sequence" {
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    local pat
    for pat in \
        'references/project-board-sync.md' \
        'references/herdr-tab-notify.sh.md' \
        'references/review-passed-cleanup.sh.md' \
        'references/ai-metrics-comment.sh.md' \
        'dispatch.sh.md'; do
        run grep -qF -- "$pat" "$doc"
        assert_success
    done
}

@test "doc-guard: the finalize SSOT is an index, not a second copy of the blocks" {
    # #1524's rule in the other direction: this file must not grow its own
    # copies of blocks that already have an SSOT, or there are two again.
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    run bash -c "grep -c -e '_gh_pr_drop_label' -e '_gh_project_status_sync' -e 'gh api' '$doc' || true"
    assert_output "0"
}

@test "doc-guard: the train routes CLEAN through --auto" {
    run grep -qF -- 'Skill(gh:pr-merge, "<N> rebase <remote> --auto")' \
        "${TRAIN_SKILL}/references/routing-table.md"
    assert_success
    run grep -qF -- '--auto' "${TRAIN_SKILL}/references/train-loop.md"
    assert_success
}

@test "doc-guard: no train call site still passes the bare '<N>' merge form" {
    # The regression this would be: one row left blocking, and the whole
    # batching benefit is gone for any queue it lands in.
    local f
    for f in "${TRAIN_SKILL}/SKILL.md" \
        "${TRAIN_SKILL}/references/routing-table.md" \
        "${TRAIN_SKILL}/references/train-loop.md" \
        "${TRAIN_SKILL}/references/github-target.md"; do
        run grep -F -- 'Skill(gh:pr-merge, "<N>")' "$f"
        assert_failure
    done
}

@test "doc-guard: report-format documents [QUEUED] and [FINALIZED]" {
    local doc="${TRAIN_SKILL}/references/report-format.md"
    run grep -qF -- '[QUEUED]' "$doc"
    assert_success
    run grep -qF -- '[FINALIZED]' "$doc"
    assert_success
    run grep -qF -- 'not yet merged' "$doc"
    assert_success
}

@test "doc-guard: the train's Step 0 runs the shared predicate, not a paraphrase" {
    local skill="${TRAIN_SKILL}/SKILL.md"
    run grep -qF -- '_gh_pr_merge_train_needs_finalize' "$skill"
    assert_success
    run grep -qF -- 'Skill(gh:pr-merge, "<N> rebase <remote> --finalize")' "$skill"
    assert_success
}

@test "doc-guard: the train's Step 0 makes no GitHub write of its own" {
    # constraints.md's corollary. The sweep may only READ; every mutation
    # belongs to gh:pr-merge --finalize.
    local skill="${TRAIN_SKILL}/SKILL.md"
    run bash -c "grep -n 'gh api\|-X POST\|-X DELETE\|-X PATCH\|gh pr edit' '$skill'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "doc-guard: BEHIND still has a local-remediation branch to fall back to" {
    # The shortcut is conditional on the base, so the pre-#1707 path must stay
    # documented and reachable — a base with strict still on needs it.
    run grep -qF -- 'gh:pr-resolve-outdated' "${TRAIN_SKILL}/references/routing-table.md"
    assert_success
    run grep -qF -- '$BEHIND_DIRECT' "${TRAIN_SKILL}/references/routing-table.md"
    assert_success
}

@test "doc-guard: ordering.md says the queue does not move D-2/D-3" {
    run grep -qF -- 'does not change D-2 or D-3' \
        "${TRAIN_SKILL}/references/ordering.md"
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
# --------------------------------------------------------------------------

@test "doc-guard: the strict-relaxation doc exists and states the rollback" {
    local doc="${TRAIN_SKILL}/references/strict-mode-relaxation.md"
    [ -r "$doc" ]
    run grep -qF -- 'strict_required_status_checks_policy' "$doc"
    assert_success
    run grep -qF -- 'ruleset-before.json' "$doc"
    assert_success
    run grep -qF -- 'rulesets/16849266' "$doc"
    assert_success
}

@test "doc-guard: the accepted risk is stated, not buried" {
    # The user's approval was conditioned on this being prominent.
    local doc="${TRAIN_SKILL}/references/strict-mode-relaxation.md"
    run grep -qF -- 'never itself run through' "$doc"
    assert_success
    run grep -qF -- 'textually' "$doc"
    assert_success
}

@test "doc-guard: the doc does not oversell CI as running the test suite" {
    # #754 removed `Test (mise)` from CI; both the pre- and post-merge gates
    # are lint-only. Claiming otherwise would make the net look stronger than
    # it is, which is the one thing this page must not do.
    local doc="${TRAIN_SKILL}/references/strict-mode-relaxation.md"
    run grep -qF -- '#754' "$doc"
    assert_success
    run grep -qF -- 'lint-only' "$doc"
    assert_success
}

@test "doc-guard: the safety net names the push-triggered workflows" {
    local doc="${TRAIN_SKILL}/references/strict-mode-relaxation.md"
    local pat
    for pat in '.github/workflows/ci.yml' 'test.yml' 'Lint (mise)' 'Shell Lint (mise)'; do
        run grep -qF -- "$pat" "$doc"
        assert_success
    done
}

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

@test "doc-guard: Step 3.6 runs the shared predicates, not a paraphrase" {
    local skill="${TRAIN_SKILL}/SKILL.md"
    run grep -qF -- '_gh_pr_merge_train_behind_may_merge_directly' "$skill"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_base_ci_red' "$skill"
    assert_success
    run grep -qF -- 'strict-mode-relaxation.md' "$skill"
    assert_success
}

@test "doc-guard: Step 3.6 is a per-base lookup, never per-PR" {
    # The whole point of #1707 is removing per-PR round trips; a guard that
    # added one back would be self-defeating.
    run grep -qF -- 'once per distinct `baseRefName`' "${TRAIN_SKILL}/SKILL.md"
    assert_success
}

@test "doc-guard: the Step 3.6 block and the fixture have not drifted apart" {
    local pat f
    for pat in \
        '_gh_pr_merge_train_behind_may_merge_directly && BEHIND_DIRECT=yes' \
        '_gh_pr_merge_train_base_strict_confirmed && BASE_STRICT_CONFIRMED=yes' \
        "printf '%s' \"\$BASE_RULES\" | jq -e 'type == \"array\"' >/dev/null 2>&1 || BASE_RULES=''" \
        "printf '%s' \"\$BASE_CHECKS\" | jq -e 'has(\"check_runs\")' >/dev/null 2>&1 || BASE_CHECKS=''" \
        'if [ "$BASE_STRICT_CONFIRMED" = no ] && { [ -z "$BASE_RULES" ] || [ -z "$BASE_CHECKS" ]; }; then' \
        '[SKIPPED] base health unreadable on $BASE — not merging onto an unverified base' \
        '[SKIPPED] $BASE is red — halting the merge phase until it is green'; do
        for f in "${TRAIN_SKILL}/references/strict-mode-relaxation.md" \
            "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_queue.sh"; do
            run grep -F -- "$pat" "$f"
            assert_success
        done
    done
}

@test "doc-guard: DIRTY is never routed around by the relaxation" {
    # The one line that must survive every future edit to this row.
    local f
    for f in "${TRAIN_SKILL}/references/routing-table.md" \
        "${TRAIN_SKILL}/references/strict-mode-relaxation.md" \
        "${TRAIN_SKILL}/SKILL.md"; do
        run grep -qF -- 'gh:pr-resolve-conflict' "$f"
        assert_success
    done
    run grep -qF -- '`DIRTY` is completely unaffected' \
        "${TRAIN_SKILL}/references/routing-table.md"
    assert_success
}

@test "doc-guard: the two #1707 docs cross-reference each other" {
    # A reader must land on the right one: the investigation is why the merge
    # queue is blocked, the relaxation is what actually shipped.
    run grep -qF -- 'strict-mode-relaxation.md' \
        "${TRAIN_SKILL}/references/merge-queue-investigation.md"
    assert_success
    run grep -qF -- 'merge-queue-investigation.md' \
        "${TRAIN_SKILL}/references/strict-mode-relaxation.md"
    assert_success
}

@test "doc-guard: the investigation doc no longer claims strict is on" {
    run grep -F -- '`strict_required_status_checks_policy: true`** is currently on' \
        "${TRAIN_SKILL}/references/merge-queue-investigation.md"
    assert_failure
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

@test "doc-guard: the investigation doc exists and is flagged manual-only" {
    local doc="${TRAIN_SKILL}/references/merge-queue-investigation.md"
    [ -r "$doc" ]
    run grep -qF -- 'merge-queue-investigation.md' "${TRAIN_SKILL}/SKILL.md"
    assert_success
    run grep -qF -- '16849266' "$doc"
    assert_success
    run grep -qF -- 'merge_queue' "$doc"
    assert_success
}

@test "doc-guard: the investigation doc corrects the 404 premise" {
    local doc="${TRAIN_SKILL}/references/merge-queue-investigation.md"
    run grep -qF -- '404' "$doc"
    assert_success
    run grep -qF -- 'branches/main/protection' "$doc"
    assert_success
}

@test "doc-guard: nothing in this change executes the ruleset PATCH" {
    # The activation is a human's deliberate act on live infrastructure: a
    # 5-minute cron drives this train, and flipping the rule from inside the
    # code that depends on it would break the running pipeline mid-flight.
    local f
    for f in "${TRAIN_SKILL}/SKILL.md" \
        "${TRAIN_SKILL}/references/routing-table.md" \
        "${TRAIN_SKILL}/references/train-loop.md" \
        "${MERGE_SKILL}/SKILL.md"; do
        run grep -F -- 'rulesets/16849266' "$f"
        assert_failure
    done
}

# --------------------------------------------------------------------------
# PR #1725, codex BLOCKER 1 — the `review-passed` drop must be the LAST step
# of the post-merge completion sequence, not the third of six.
#
# The label is the ONLY thing `_gh_pr_merge_train_needs_finalize` matches on.
# While it is on, an unfinished PR is findable by the next tick's Step 0
# sweep; the moment it comes off, that PR is invisible forever. So no step
# that can still be owed may run after the drop — and until #1725 two did
# (the ai-metrics comment and the post-merge-verify dispatch).
# --------------------------------------------------------------------------

# First line number carrying a fixed string, or empty if absent.
_line_of() {
    grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1
}

@test "drop-last: the finalize SSOT orders the label drop after ai-metrics" {
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    local metrics drop
    metrics=$(_line_of "$doc" 'references/ai-metrics-comment.sh.md')
    drop=$(_line_of "$doc" 'references/review-passed-cleanup.sh.md')
    [ -n "$metrics" ]
    [ -n "$drop" ]
    [ "$drop" -gt "$metrics" ]
}

@test "drop-last: the finalize SSOT orders the label drop after the PMV dispatch" {
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    local dispatch drop
    dispatch=$(_line_of "$doc" 'dispatch.sh.md')
    drop=$(_line_of "$doc" 'references/review-passed-cleanup.sh.md')
    [ -n "$dispatch" ]
    [ "$drop" -gt "$dispatch" ]
}

@test "drop-last: the finalize SSOT numbers the label drop 6 of 6" {
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    run grep -qE '^\| 6 \|.*review-passed' "$doc"
    assert_success
}

@test "drop-last: the SSOT prose no longer claims the drop is step 3" {
    # The exact false statement #1725 found: the doc said "Step 3 is last among
    # the writes on purpose" while sitting 3rd of 6 with two writes after it.
    local doc="${MERGE_SKILL}/references/finalize-merged-pr.sh.md"
    run grep -F -- 'Step 3 is **last among the writes on purpose**' "$doc"
    assert_failure
}

@test "drop-last: gh:pr-merge runs the drop after ai-metrics and after the dispatch" {
    local skill="${MERGE_SKILL}/SKILL.md"
    local metrics dispatch drop
    metrics=$(_line_of "$skill" 'references/ai-metrics-comment.sh.md')
    dispatch=$(_line_of "$skill" 'gh-pr-post-merge-verify/references/dispatch.sh.md')
    drop=$(_line_of "$skill" 'references/review-passed-cleanup.sh.md')
    [ -n "$metrics" ]
    [ -n "$dispatch" ]
    [ -n "$drop" ]
    [ "$drop" -gt "$metrics" ]
    [ "$drop" -gt "$dispatch" ]
}

@test "drop-last: gh:pr-merge Step 4 explicitly says the drop is not there" {
    # A reader following Step 4 top to bottom must not re-add it in place.
    run grep -qF -- 'is **not** dropped here' "${MERGE_SKILL}/SKILL.md"
    assert_success
}

@test "drop-last: the cleanup SSOT states where in the sequence it runs" {
    local doc="${MERGE_SKILL}/references/review-passed-cleanup.sh.md"
    run grep -qF -- 'step 6 of 6' "$doc"
    assert_success
    run grep -qF -- '#1725' "$doc"
    assert_success
}

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
    local f
    for f in "${TRAIN_SKILL}/references/strict-mode-relaxation.md" \
        "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_queue.sh"; do
        run grep -F -- '[ "$BEHIND_DIRECT" = yes ] && [ -z "$BASE_CHECKS" ]' "$f"
        assert_failure
    done
}

@test "doc-guard: the new predicate is in the shipped self-check list" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    run bash -c "sed -n '/^for _gh_pmt_selfcheck_fn in/,/^done/p' '$f' \
        | grep -qF -- '_gh_pr_merge_train_base_strict_confirmed'"
    assert_success
}

@test "doc-guard: Step 3.6 names the exemption predicate, not a paraphrase" {
    run grep -qF -- '_gh_pr_merge_train_base_strict_confirmed' "${TRAIN_SKILL}/SKILL.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_base_strict_confirmed' \
        "${TRAIN_SKILL}/references/strict-mode-relaxation.md"
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

@test "sweep: Step 0 queries the search index by label, not gh pr list" {
    local skill="${TRAIN_SKILL}/SKILL.md"
    run grep -qF -- 'gh search prs --repo "$TARGET_REPO" --author @me' "$skill"
    assert_success
    run grep -qF -- '--merged --label review-passed' "$skill"
    assert_success
}

@test "sweep: the recency-capped call is gone" {
    # `--limit 30` may still be NAMED in the prose that explains the bug; what
    # must be gone is the invocation. Assert on the command, not the mention.
    local skill="${TRAIN_SKILL}/SKILL.md"
    run grep -F -- 'gh pr list --repo "$TARGET_REPO" --author @me --state merged' "$skill"
    assert_failure
    run grep -qF -- '--limit 100 --json number,title,state,labels' "$skill"
    assert_success
}

@test "sweep: the prose no longer calls an aged-out leftover a human's problem" {
    # That sentence justified the bug. It must not survive the fix.
    run grep -F -- "is a human's problem, not a loop's" "${TRAIN_SKILL}/SKILL.md"
    assert_failure
}

@test "sweep: --author @me survives the switch to search (D-7)" {
    # Never sweep — and therefore never finalize — a colleague's PR.
    run grep -qF -- '--author @me' "${TRAIN_SKILL}/SKILL.md"
    assert_success
}

@test "sweep: the shared filter still runs over the search result" {
    # The query and the filter now encode the same rule; the filter is what
    # keeps that rule in ONE place and normalises `state` across both sources.
    local skill="${TRAIN_SKILL}/SKILL.md"
    run grep -qF -- '| _gh_pr_merge_train_finalize_targets' "$skill"
    assert_success
}

@test "sweep: the sweep is still read-only (constraints.md corollary)" {
    local skill="${TRAIN_SKILL}/SKILL.md"
    run bash -c "grep -n 'gh api\|-X POST\|-X DELETE\|-X PATCH\|gh pr edit' '$skill'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "sweep: constraints.md describes the same call the skill makes" {
    run grep -qF -- 'gh search prs --merged --label' \
        "${TRAIN_SKILL}/references/constraints.md"
    assert_success
    run grep -F -- 'one `gh pr list --state merged`' \
        "${TRAIN_SKILL}/references/constraints.md"
    assert_failure
}
