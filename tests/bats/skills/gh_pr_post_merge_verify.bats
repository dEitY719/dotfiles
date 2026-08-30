#!/usr/bin/env bats
# tests/bats/skills/gh_pr_post_merge_verify.bats
# Verify the post-merge verification dispatch documented in
#   claude/skills/gh-pr-post-merge-verify/SKILL.md
#   claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md
# Source-of-truth fixture: _fixtures/gh_pr_post_merge_verify.sh.
#
# Cases are issue #1511's acceptance criteria and error cases, one test each:
#   A-1  unregistered repo      -> byte-identical to pre-#1511 (no herdr call)
#   A-2  registered repo        -> close, rebase, pr-<N> tab, verify prompt
#   A-3  main rebase conflict   -> WARN only, and NO tab is created
#   A-4  impl tab not found     -> rebase + tab + verify still run
#   A-5  herdr not installed    -> the whole skill is a silent no-op
#   E-1  registry missing       -> silent no-op (existing behavior preserved)
#   E-2  registry malformed     -> one WARN, feature skipped
#   E-3  main checkout dirty    -> WARN, abort before tab creation
#   E-4  tab create fails       -> WARN, no agent start
#   E-5  agent start fails      -> WARN, no prompt
#   E-6  agent_name_taken       -> WARN, but the existing session IS prompted
#   E-7  prompt fails           -> WARN, report still prints
# PR #1518 review hardening, one test each:
#   R-1  main checkout on the wrong branch / detached  -> WARN, no rebase
#   R-2  remote + base branch are threaded, never hardcoded origin/main
#   R-3  verify_skill is allowlisted before any herdr mutation, but only
#        once herdr itself is present (no herdr => silent, AC-5)
#   R-4  MAIN_ROOT must resolve to a git worktree root
#   R-5  a sibling path must not match the tab prefix
#   R-7  "herdr unreachable" and "nothing running" are different lines
#   R-8  no jq -> the feature is unavailable, silently
# Plus unit-level pins on the pieces that are easy to get subtly wrong:
# host-qualified agent naming, the flat-key pane scan, main-checkout
# resolution from a linked worktree, and the two ways `herdr agent list`
# matching can silently close the wrong tab (or none).

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_post_merge_verify.sh"

    WATCHED="${TEST_TEMP_HOME}/watched-repos.json"
    cat >"$WATCHED" <<'JSON'
[
  { "repo": "acme/dotfiles", "verify_skill": "devx:pr-verify-merged" },
  { "repo": "acme/webapp", "verify_skill": "devx:pr-verify-live" }
]
JSON

    MAIN_ROOT="${TEST_TEMP_HOME}/dotfiles"
    IMPL_WT="${TEST_TEMP_HOME}/dotfiles-issue-77-1"

    FAKE_HERDR_LOG="${TEST_TEMP_HOME}/herdr.log"
    FAKE_GIT_LOG="${TEST_TEMP_HOME}/git.log"
    : >"$FAKE_HERDR_LOG"
    : >"$FAKE_GIT_LOG"
    export FAKE_HERDR_LOG FAKE_GIT_LOG

    FAKE_WORKTREE_PORCELAIN="worktree ${MAIN_ROOT}
HEAD aaaa
branch refs/heads/main

worktree ${IMPL_WT}
HEAD bbbb
branch refs/heads/wt/issue-77/1
"
    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"${IMPL_WT}\",\"foreground_cwd\":\"${IMPL_WT}\",\"tab_id\":\"wV:t42\",\"pane_id\":\"wV:p42\"}]}}"
    FAKE_HERDR_OUT_WORKTREE_LIST="{\"result\":{\"source\":{\"repo_root\":\"${MAIN_ROOT}\",\"source_workspace_id\":\"wV\"},\"worktrees\":[{\"path\":\"${MAIN_ROOT}\",\"open_workspace_id\":\"wV\"}]}}"
    FAKE_HERDR_OUT_TAB_CREATE='{"result":{"tab":{"tab_id":"wV:t99"},"pane":{"pane_id":"wV:p99"}}}'
    FAKE_HERDR_OUT_AGENT_START='{"result":{"agent":{"agent_status":"idle"}}}'
    FAKE_HERDR_OUT_AGENT_PROMPT='{"result":{"agent":{"agent_status":"idle"}}}'
    export FAKE_WORKTREE_PORCELAIN FAKE_HERDR_OUT_AGENT_LIST FAKE_HERDR_OUT_WORKTREE_LIST
    export FAKE_HERDR_OUT_TAB_CREATE FAKE_HERDR_OUT_AGENT_START FAKE_HERDR_OUT_AGENT_PROMPT

    # The dispatch passes CLAUDE_CONFIG_DIR through when it is set; keep it out
    # of the argv assertions unless a test opts in.
    unset CLAUDE_CONFIG_DIR
}

teardown() {
    teardown_isolated_home
    unset PMV_PROMPT_TIMEOUT_MS PMV_SETTLE_SECONDS PMV_PROMPT_ATTEMPT_MAX
    unset FAKE_HERDR_PRESENT FAKE_JQ_PRESENT FAKE_HERDR_LOG FAKE_GIT_LOG FAKE_WORKTREE_PORCELAIN \
        FAKE_WORKTREE_RC FAKE_MAIN_DIRTY FAKE_SYNC_RC FAKE_MAIN_BRANCH FAKE_MAIN_TOPLEVEL \
        FAKE_HERDR_OUT_AGENT_LIST FAKE_HERDR_OUT_WORKTREE_LIST \
        FAKE_HERDR_OUT_TAB_CREATE FAKE_HERDR_OUT_AGENT_START FAKE_HERDR_OUT_AGENT_PROMPT \
        FAKE_HERDR_RC_AGENT_LIST FAKE_HERDR_RC_TAB_CREATE FAKE_HERDR_RC_TAB_CLOSE \
        FAKE_HERDR_RC_AGENT_START FAKE_HERDR_RC_AGENT_PROMPT FAKE_HERDR_RC_TAB_RENAME \
        FAKE_HERDR_RC_NOTIFICATION_SHOW \
        FAKE_GIT_COMMON_DIR FAKE_SCRATCH_EXISTS FAKE_SCRATCH_REGISTERED FAKE_WORKTREE_ADD_RC
}

dispatch() {
    gh_pr_post_merge_verify 77 "${1:-acme/dotfiles}" github.com "$MAIN_ROOT" wt/issue-77/1 \
        "$WATCHED" "${2-}" "${3-}"
}

# The settle waits (#1571) are recorded into the herdr log by the fixture's
# `_pmv_sleep`, so their *order* against `tab create` / `agent start` /
# `agent prompt` is assertable — a wait that lands on the wrong side of a call
# is exactly the defect, and a "did it sleep at all" check would miss it.
_pmv_log_line() { grep -n -- "$1" "$FAKE_HERDR_LOG" | head -1 | cut -d: -f1; }
_pmv_log_count() { grep -c -- "$1" "$FAKE_HERDR_LOG" || true; }

# --- F-1: the watched-repos.json gate -------------------------------------

@test "gate: a registered repo yields its verify_skill" {
    run pmv_gate "$WATCHED" acme/dotfiles
    assert_success
    assert_output "devx:pr-verify-merged"
}

@test "gate: per-repo verify_skill is honoured, not hardcoded" {
    run pmv_gate "$WATCHED" acme/webapp
    assert_success
    assert_output "devx:pr-verify-live"
}

@test "gate: an unregistered repo returns 1 with no output" {
    run pmv_gate "$WATCHED" other/repo
    [ "$status" -eq 1 ]
    assert_output ""
}

@test "gate: a missing registry returns 1 (skip), not 2 (warn)" {
    run pmv_gate "${TEST_TEMP_HOME}/nope.json" acme/dotfiles
    [ "$status" -eq 1 ]
}

@test "gate: malformed JSON returns 2 so the caller can warn" {
    printf 'not json at all\n' >"${TEST_TEMP_HOME}/bad.json"
    run pmv_gate "${TEST_TEMP_HOME}/bad.json" acme/dotfiles
    [ "$status" -eq 2 ]
}

@test "gate: an entry present but with no verify_skill is a silent no-op (#1555)" {
    # issue-watcher may track a repo gh:pr-post-merge-verify never verifies —
    # a bare {repo, path} entry with no verify_skill field at all.
    printf '[{"repo":"acme/dotfiles","path":"/x"}]\n' >"$WATCHED"
    run pmv_gate "$WATCHED" acme/dotfiles
    [ "$status" -eq 1 ]
    assert_output ""
}

@test "gate: the object-wrapped {repos:[...]} shape is read too (agy review, #1555)" {
    # issue_watcher_cron.sh has always accepted a bare array OR an object
    # with a top-level "repos" array; this skill's registry is the same file,
    # so it must accept both shapes identically, not just the array form.
    printf '{"repos":[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged"}]}\n' >"$WATCHED"
    run pmv_gate "$WATCHED" acme/dotfiles
    assert_success
    assert_output "devx:pr-verify-merged"
}

@test "main root: the object-wrapped {repos:[...]} shape resolves path too (#1555)" {
    printf '{"repos":[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged","path":"~/elsewhere"}]}\n' >"$WATCHED"
    run pmv_main_root "$WATCHED" acme/dotfiles "${MAIN_ROOT}/.git"
    assert_output "${HOME}/elsewhere"
}

# --- A-1 / A-5 / E-1 / E-2: the no-op paths -------------------------------

@test "A-1: an unregistered repo makes no herdr call at all" {
    run dispatch other/repo
    assert_success
    assert_output ""
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "E-1: a missing registry is a silent no-op" {
    WATCHED="${TEST_TEMP_HOME}/nope.json"
    run dispatch
    assert_success
    assert_output ""
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "E-2: a malformed registry warns once and skips the feature" {
    printf '{ oops\n' >"$WATCHED"
    run dispatch
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "is not valid JSON"
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "A-5: herdr not installed → the whole skill is a silent no-op" {
    FAKE_HERDR_PRESENT=0
    run dispatch
    assert_success
    assert_output ""
    run cat "$FAKE_GIT_LOG"
    assert_output ""
}

# --- A-2: the happy path ---------------------------------------------------

@test "A-2: registered repo closes the impl tab, rebases, opens pr-<N>, verifies" {
    run dispatch
    assert_success
    assert_output --partial "closed implementation tab wV:t42"
    assert_output --partial "post-merge verification dispatched"
    assert_output --partial "tab:    wV:t99 (label pr-77)"
    assert_output --partial "agent:  mv-dotfiles-pr-77"
    assert_output --partial "attach: herdr agent attach mv-dotfiles-pr-77"

    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "herdr tab close wV:t42"
    # `--cwd` is the PR's own detached worktree, never the shared main checkout
    # (#1577); the 1577 block below is where that is pinned in detail.
    assert_output --partial "herdr tab create --workspace wV --cwd ${MAIN_ROOT}/.git/pr-post-merge-verify/pr-77 --label pr-77 --no-focus"
    assert_output --partial "herdr agent start mv-dotfiles-pr-77 --kind claude --pane wV:p99 -- --dangerously-skip-permissions"
    assert_output --partial "herdr agent prompt mv-dotfiles-pr-77 /devx-pr-verify-merged 77 --wait --until idle"
}

@test "A-2: the impl tab is closed BEFORE the verification tab is created" {
    run dispatch
    assert_success
    run bash -c "grep -n 'tab close\|tab create' '$FAKE_HERDR_LOG' | head -2 | cut -d: -f2- | tr '\n' '|'"
    assert_output --partial "herdr tab close wV:t42|herdr tab create"
}

@test "A-2: the main checkout is the rebase target, never the worktree" {
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "sync ${MAIN_ROOT}"
    refute_output --partial "$IMPL_WT"
}

@test "A-2: CLAUDE_CONFIG_DIR is forwarded to the new tab when set" {
    export CLAUDE_CONFIG_DIR="${TEST_TEMP_HOME}/.claude-personal"
    run dispatch
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "--env CLAUDE_CONFIG_DIR=${TEST_TEMP_HOME}/.claude-personal"
}

@test "A-2: a -live repo is prompted with its own verify skill" {
    run gh_pr_post_merge_verify 77 acme/webapp github.com "$MAIN_ROOT" wt/issue-77/1 "$WATCHED"
    assert_success
    assert_output --partial "verify: /devx-pr-verify-live 77"
}

# --- A-4 / E-*: the impl-tab step never blocks ----------------------------

@test "A-4: impl tab already closed → remaining steps still run" {
    FAKE_HERDR_OUT_AGENT_LIST='{"result":{"agents":[]}}'
    run dispatch
    assert_success
    assert_output --partial "no live herdr tab"
    assert_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close"
    assert_output --partial "tab create"
}

@test "A-4: no local worktree for the head branch → remaining steps still run" {
    FAKE_WORKTREE_PORCELAIN="worktree ${MAIN_ROOT}
HEAD aaaa
branch refs/heads/main
"
    run dispatch
    assert_success
    assert_output --partial "no local worktree for wt/issue-77/1"
    assert_output --partial "post-merge verification dispatched"
}

@test "A-4: a failing herdr tab close warns but does not stop the dispatch" {
    FAKE_HERDR_RC_TAB_CLOSE=1
    run dispatch
    assert_success
    assert_output --partial "herdr tab close wV:t42 failed"
    assert_output --partial "post-merge verification dispatched"
}

# --- A-3 / E-3: the main checkout is a hard stop --------------------------

@test "E-3: a dirty main checkout warns and creates no tab" {
    FAKE_MAIN_DIRTY=1
    run dispatch
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "has uncommitted changes"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "sync "
}

@test "A-3: a rebase conflict warns, aborts the rebase, and creates no tab" {
    FAKE_SYNC_RC=1
    run dispatch
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "conflict not resolved"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
}

@test "A-3: the conflicted main checkout is restored, never auto-resolved" {
    FAKE_SYNC_RC=1
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "rebase-abort ${MAIN_ROOT}"
}

# --- E-4..E-7: herdr failures are soft ------------------------------------

@test "E-4: herdr tab create failure warns and skips the agent" {
    FAKE_HERDR_RC_TAB_CREATE=1
    run dispatch
    assert_success
    assert_output --partial "herdr tab create failed for label pr-77"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "agent start"
}

@test "E-4: a tab create answer with no pane counts as a failure" {
    FAKE_HERDR_OUT_TAB_CREATE='{"result":{"tab":{"tab_id":"wV:t99"}}}'
    run dispatch
    assert_success
    assert_output --partial "herdr tab create failed"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "agent start"
}

@test "E-4: an unresolvable workspace warns instead of guessing one" {
    FAKE_HERDR_OUT_WORKTREE_LIST='{"result":{"worktrees":[]}}'
    run dispatch
    assert_success
    assert_output --partial "no herdr workspace for ${MAIN_ROOT}"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
}

@test "E-5: herdr agent start failure warns and does not prompt" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"pane_not_ready"}}'
    run dispatch
    assert_success
    assert_output --partial "herdr agent start mv-dotfiles-pr-77 failed"
    assert_output --partial "pane_not_ready"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "agent prompt"
}

@test "E-6: agent_name_taken prompts the existing session instead of failing" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"agent_name_taken"}}'
    run dispatch
    assert_success
    assert_output --partial "already registered — prompting the existing session"
    assert_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "agent prompt mv-dotfiles-pr-77"
}

@test "E-7: a failing prompt warns but the report still prints" {
    FAKE_HERDR_RC_AGENT_PROMPT=1
    FAKE_HERDR_OUT_AGENT_PROMPT='{"error":{"code":"agent_prompt_stalled"}}'
    run dispatch
    assert_success
    assert_output --partial "herdr agent prompt mv-dotfiles-pr-77 failed (agent_prompt_stalled)"
    assert_output --partial "renamed tab wV:t99 to pr-77-STUCK"
    assert_output --partial "notification posted for pr-77 stall"
    assert_output --partial "post-merge verification dispatched"
}

@test "E-7: a retryable prompt failure retries twice before escalating" {
    PMV_PROMPT_ATTEMPT_MAX=3
    FAKE_HERDR_RC_AGENT_PROMPT=1
    FAKE_HERDR_OUT_AGENT_PROMPT='{"error":{"code":"timeout"}}'
    run dispatch
    assert_success
    [ "$(_pmv_log_count 'herdr agent prompt mv-dotfiles-pr-77')" -eq 3 ]
    [ "$(_pmv_log_count 'sleep 13')" -eq 4 ]
    assert_output --partial "retrying after 13s settle (1/3)"
    assert_output --partial "retrying after 13s settle (2/3)"
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "herdr tab rename wV:t99 pr-77-STUCK"
    assert_output --partial "herdr notification show post-merge verify stalled --body pr-77 verification prompt failed repeatedly — herdr agent attach mv-dotfiles-pr-77 --sound request"
}

# --- unit pins on the easy-to-break pieces --------------------------------

# The pre-#1530 name was `pmv-<host>-<owner>-<repo>-<N>` — 37 characters for
# this repo, and carrying a dot besides, so herdr refused every `agent start`
# and post-merge verification never ran once. These pin the shape herdr
# accepts, including the length budget that made truncation mandatory.
@test "naming: the agent name satisfies herdr's rule" {
    run pmv_agent_name github.com acme/dotfiles 77
    assert_output "mv-dotfiles-pr-77"
    assert_valid_herdr_name "$output"
}

@test "naming: a mixed-case owner and a long repo still fit the 32-char budget" {
    run pmv_agent_name github.com dEitY719/A-Very-Long-Repository-Name 99999
    assert_success
    assert_valid_herdr_name "$output"
    assert_output "mv-a-very-long-repo-pr-99999"
}

# The host is deliberately not in the name any more — it does not fit in 32
# characters alongside the repo. Two hosts sharing a repo name would collide;
# that trade-off, and the condition that would end it, is documented in
# shell-common/functions/herdr_agent_name.sh.
@test "naming: the host is not part of the agent name" {
    run pmv_agent_name ghe.example.com acme/dotfiles 77
    assert_output "mv-dotfiles-pr-77"
}

@test "naming: the skill id becomes a dash-form slash command" {
    run pmv_verify_prompt devx:pr-verify-merged 77
    assert_output "/devx-pr-verify-merged 77"
}

pane_of() { printf '%s' "$1" | pmv_json_first pane_id; }

@test "json: pane_id is found under either parent shape" {
    # herdr nests the pane under `.result.pane` (tab create) or
    # `.result.root_pane` (workspace create); the scan keys on the leaf name.
    run pane_of '{"result":{"pane":{"pane_id":"p1"}}}'
    assert_output "p1"
    run pane_of '{"result":{"root_pane":{"pane_id":"p2"}}}'
    assert_output "p2"
}

@test "cwd-match: an empty herdr answer is unknown, never 'nothing running'" {
    # The one mistake this signal cannot make: reading an unhealthy herdr as
    # 'no agent here' and closing/creating on that basis.
    FAKE_HERDR_OUT_AGENT_LIST=""
    run pmv_tab_for_cwd "$IMPL_WT"
    [ "$status" -eq 1 ]
}

@test "cwd-match: foreground_cwd counts too (the session that cd-ed away)" {
    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"/elsewhere\",\"foreground_cwd\":\"${IMPL_WT}/sub\",\"tab_id\":\"wV:t7\"}]}}"
    run pmv_tab_for_cwd "$IMPL_WT"
    assert_success
    assert_output "wV:t7"
}

@test "cwd-match: an empty path matches nothing (startswith guard)" {
    run pmv_tab_for_cwd ""
    [ "$status" -eq 3 ]
    assert_output ""
}

@test "main root: git's common dir resolves the original checkout from a worktree" {
    run pmv_main_root "$WATCHED" acme/dotfiles "${MAIN_ROOT}/.git"
    assert_output "$MAIN_ROOT"
}

@test "main root: an explicit path wins and expands a leading ~ (#1555)" {
    printf '[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged","path":"~/elsewhere"}]\n' >"$WATCHED"
    run pmv_main_root "$WATCHED" acme/dotfiles "${MAIN_ROOT}/.git"
    assert_output "${HOME}/elsewhere"
}

@test "main root: an entry with no path falls back to git's common dir (#1555)" {
    printf '[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged"}]\n' >"$WATCHED"
    run pmv_main_root "$WATCHED" acme/dotfiles "${MAIN_ROOT}/.git"
    assert_output "$MAIN_ROOT"
}

@test "timeout: the prompt cap defaults to 900000ms when the env var is unset" {
    run dispatch
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "--wait --until idle --timeout 900000"
}

@test "timeout: PMV_PROMPT_TIMEOUT_MS overrides the default prompt cap" {
    export PMV_PROMPT_TIMEOUT_MS=1234
    run dispatch
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "--wait --until idle --timeout 1234"
    refute_output --partial "--timeout 900000"
}

@test "worktree lookup: the branch decides the path, not the directory name" {
    run pmv_worktree_for_branch wt/issue-77/1
    assert_output "$IMPL_WT"
    run pmv_worktree_for_branch main
    assert_output "$MAIN_ROOT"
    run pmv_worktree_for_branch wt/issue-99/1
    assert_output ""
}

# --- PR #1518 review: BLOCKER-1 / BLOCKER-2, the rebase preconditions ------

@test "R-1: a main checkout parked on another branch is never rebased" {
    FAKE_MAIN_BRANCH=feature/unrelated
    run dispatch acme/dotfiles origin main
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "is on feature/unrelated, not the base branch main"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "sync "
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
}

@test "R-1: a detached HEAD stops the run instead of rebasing it" {
    FAKE_MAIN_BRANCH=HEAD
    run dispatch
    assert_success
    assert_output --partial "is on (detached HEAD), not the base branch (unknown)"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "sync "
}

@test "R-1: a detached HEAD stops even when the caller passed a base branch" {
    FAKE_MAIN_BRANCH=HEAD
    run dispatch acme/dotfiles origin main
    assert_success
    assert_output --partial "is on (detached HEAD), not the base branch main"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "sync "
}

@test "R-2: the remote positional and the PR's base branch are what get fetched" {
    FAKE_MAIN_BRANCH=develop
    run dispatch acme/dotfiles upstream develop
    assert_success
    assert_output --partial "post-merge verification dispatched"
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "sync ${MAIN_ROOT} upstream develop"
    refute_output --partial "origin"
    refute_output --partial " main"
}

@test "R-2: an empty base branch falls back to the checkout's own branch" {
    # Never a literal `main`: a watched repo may default to master/develop.
    FAKE_MAIN_BRANCH=master
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "sync ${MAIN_ROOT} origin master"
}

@test "R-2: an empty remote falls back to origin, never to an empty word" {
    run pmv_sync_main "$MAIN_ROOT" "" main
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "sync ${MAIN_ROOT} origin main"
}

# --- PR #1518 review: BLOCKER-3, the verify_skill allowlist ----------------

@test "R-3: both shipped verification skills are accepted" {
    run pmv_verify_skill_allowed devx:pr-verify-merged
    assert_success
    run pmv_verify_skill_allowed devx:pr-verify-live
    assert_success
}

@test "R-3: with no herdr, even a bad registry value stays silent (AC-5)" {
    # The allowlist sits AFTER the herdr probe on purpose: a machine that
    # cannot run the feature at all must print nothing, which is the
    # acceptance criterion "herdr 미설치 → 스킬 전체가 조용히 스킵".
    printf '{"acme/dotfiles":{"verify_skill":"evil:do-something-else"}}\n' >"$WATCHED"
    FAKE_HERDR_PRESENT=0
    run dispatch
    assert_success
    assert_output ""
}

@test "R-3: anything else is refused" {
    run pmv_verify_skill_allowed devx:pr-verify-anything
    [ "$status" -eq 1 ]
    run pmv_verify_skill_allowed ""
    [ "$status" -eq 1 ]
}

@test "R-3: a registry value off the allowlist warns before any herdr call" {
    # It is typed into a --dangerously-skip-permissions agent's prompt, so a
    # bad registry must not even get as far as closing a tab.
    printf '[{"repo":"acme/dotfiles","verify_skill":"evil:do-something-else"}]\n' >"$WATCHED"
    run dispatch
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "verify_skill \"evil:do-something-else\" for acme/dotfiles is not one of"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
    run cat "$FAKE_GIT_LOG"
    assert_output ""
}

# --- PR #1518 review: BLOCKER-4, MAIN_ROOT must be a git worktree root -----

@test "R-4: an empty main checkout is refused before anything is touched" {
    run gh_pr_post_merge_verify 77 acme/dotfiles github.com "" wt/issue-77/1 "$WATCHED"
    assert_success
    assert_output --partial "is not a git worktree root"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "R-4: a path that is not a git worktree root is refused" {
    FAKE_MAIN_TOPLEVEL=""
    run dispatch
    assert_success
    assert_output --partial "main checkout \"${MAIN_ROOT}\" is not a git worktree root"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close"
    refute_output --partial "tab create"
}

@test "R-4: a path INSIDE the checkout is not its root" {
    FAKE_MAIN_TOPLEVEL="$MAIN_ROOT"
    run gh_pr_post_merge_verify 77 acme/dotfiles github.com "${MAIN_ROOT}/git" \
        wt/issue-77/1 "$WATCHED"
    assert_success
    assert_output --partial "is not a git worktree root"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "sync "
}

# --- PR #1518 review: BLOCKER-5, the prefix needs a path boundary ----------

@test "R-5: a sibling checkout sharing a prefix is not matched" {
    # /work/repo-11 must not answer for /work/repo-1.
    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"${IMPL_WT}1\",\"foreground_cwd\":\"${IMPL_WT}1\",\"tab_id\":\"wV:tSIB\"}]}}"
    run pmv_tab_for_cwd "$IMPL_WT"
    [ "$status" -eq 3 ]
    assert_output ""
}

@test "R-5: the path itself and its subdirectories still match" {
    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"${IMPL_WT}\",\"tab_id\":\"wV:tSELF\"}]}}"
    run pmv_tab_for_cwd "$IMPL_WT"
    assert_success
    assert_output "wV:tSELF"

    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"${IMPL_WT}/sub/deep\",\"tab_id\":\"wV:tSUB\"}]}}"
    run pmv_tab_for_cwd "$IMPL_WT"
    assert_success
    assert_output "wV:tSUB"
}

@test "R-5: a sibling worktree's tab is not closed by the dispatch" {
    FAKE_HERDR_OUT_AGENT_LIST="{\"result\":{\"agents\":[{\"cwd\":\"${IMPL_WT}1\",\"tab_id\":\"wV:tSIB\"}]}}"
    run dispatch
    assert_success
    assert_output --partial "no live herdr tab on ${IMPL_WT}"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close"
}

# --- PR #1518 review: FOLLOW-UP-6/7/8 -------------------------------------

@test "R-6: the dispatch block never uses \`set --\` (it would eat \$1, \$2, ...)" {
    # The block is pasted at the top level of the caller's shell, so `set --`
    # there would destroy the caller's own arguments. Comment lines are skipped
    # — the rationale for NOT using it is allowed to name it.
    run bash -c "grep -vE '^[[:space:]]*#' '${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md' | grep -n 'set --'"
    [ "$status" -ne 0 ]
}

@test "R-7: an unreachable herdr WARNs, it does not claim 'nothing to close'" {
    FAKE_HERDR_OUT_AGENT_LIST=""
    run dispatch
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "herdr could not be queried — implementation tab on ${IMPL_WT} left alone"
    refute_output --partial "nothing to close"
    assert_output --partial "post-merge verification dispatched"
}

@test "R-7: an answered-but-empty herdr is an INFO 'nothing to close'" {
    FAKE_HERDR_OUT_AGENT_LIST='{"result":{"agents":[]}}'
    run dispatch
    assert_success
    assert_output --partial "[INFO] gh:pr-post-merge-verify: no live herdr tab on ${IMPL_WT} — nothing to close."
    refute_output --partial "could not be queried"
}

@test "R-8: no jq → the feature is unavailable, silently" {
    FAKE_JQ_PRESENT=0
    run dispatch
    assert_success
    assert_output ""
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
    run cat "$FAKE_GIT_LOG"
    assert_output ""
}

@test "R-8: both watched-repos gates carry the same jq guard" {
    # gh:pr-merge's gate and the dispatch block's step-0 gate must agree, or an
    # unregistered repo stops being byte-identical to pre-#1511.
    run grep -c 'if command -v jq >/dev/null 2>&1 && \[ -r "$WATCHED_FILE" \]; then' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/SKILL.md"
    assert_output "1"
    run grep -c 'if command -v jq >/dev/null 2>&1 && \[ -r "$WATCHED_FILE" \]; then' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md"
    assert_output "1"
}

# --- #1565: gh:pr-merge Step 5 runs the dispatch, it does not call a Skill --
#
# The dispatch used to be prose at the very tail of gh:pr-merge ("Otherwise
# call `Skill(gh:pr-post-merge-verify, "<N> <remote>")`"), inside a skill
# gh:pr-merge-train invokes in a loop. It executed 0/10 times in that loop and
# 1/1 at top level, while every pasted shell block in the same skill's Step 4
# ran 10/10. The form is the fix: a block that is there to run cannot be
# forgotten the way an instruction to call something else can.

_pmv_merge_skill() { printf '%s' "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge/SKILL.md"; }
_pmv_dispatch_doc() { printf '%s' "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md"; }

# The exact awk program gh:pr-merge Step 5 uses to take the FIRST bash fence
# out of dispatch.sh.md. Pinned here and then actually run below, so an edit to
# either side turns this suite red instead of silently extracting nothing.
_PMV_EXTRACT_AWK='$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b'

@test "1565: gh:pr-merge Step 5 no longer delegates through Skill()" {
    # Comment lines are skipped — the rationale for NOT calling it is allowed
    # to name it (same carve-out as R-6 above).
    run bash -c "grep -vE '^[[:space:]]*#' '$(_pmv_merge_skill)' | grep -n 'Skill(gh:pr-post-merge-verify'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "1565: gh:pr-merge Step 5 reads the dispatch SSOT instead of copying it" {
    run grep -qF -- 'claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md' \
        "$(_pmv_merge_skill)"
    assert_success
    # Sourced, not described.
    run grep -qF -- '. "$PMV_SH"' "$(_pmv_merge_skill)"
    assert_success
}

@test "1565: gh:pr-merge Step 5 carries the extraction program verbatim" {
    run grep -qF -- "$_PMV_EXTRACT_AWK" "$(_pmv_merge_skill)"
    assert_success
}

@test "1565: gh:pr-merge Step 5 binds the inputs the dispatch reads" {
    local _v
    for _v in PR_NUMBER HEAD_BRANCH BASE_BRANCH REMOTE; do
        run grep -qE "^${_v}=" "$(_pmv_merge_skill)"
        assert_success
    done
}

@test "1565: the extraction yields the dispatch block, not a doc snippet" {
    local _out
    _out="${TEST_TEMP_HOME}/extracted.sh"
    run bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    assert_success
    run head -n 2 "$_out"
    assert_output --partial 'WATCHED_FILE='
    run tail -n 1 "$_out"
    assert_output --partial 'attach: herdr agent attach'
    # The file's later fences are documentation — the standalone head/base ref
    # recovery must not be swept into the executed block.
    run grep -c 'gh pr view' "$_out"
    assert_output "0"
}

@test "1565: the extracted dispatch block is syntactically valid shell" {
    local _out
    _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run bash -n "$_out"
    assert_success
}

@test "1565: the extracted block returns rather than exiting when sourced" {
    # Every early exit is `return 0 2>/dev/null || exit 0` so that sourcing it
    # from Step 5 cannot kill the caller's shell mid-report.
    local _out
    _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run bash -c "grep -n 'exit 0' '${_out}' | grep -v 'return 0 2>/dev/null || exit 0'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- the soft-fail exit-code contract (PR #1567 review) --------------------
#
# Every path through the dispatch is a soft-fail: gh:pr-merge sources it after
# the merge already happened and after its own report is written, so a non-zero
# status would abort a caller running under `set -e` over work that succeeded.
# The tests above pin the *shape* of each terminator; these pin the status.

@test "1565: no path in the extracted dispatch block exits non-zero" {
    local _out
    _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    # `return N` inside the sourced lookup helper (#1569) is a helper's answer
    # to its caller, not a status the block ever leaves with — only `exit` ends
    # the dispatch.
    run bash -c "grep -nE 'exit[[:space:]]+[1-9]' '${_out}'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "1565: the extracted block exits 0 on its unregistered-repo gate" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"

    # #1555: the block reads IW_WATCHED_REPOS (or the issue-watcher default
    # under HOME), never DOTFILES_ROOT/docs/.ssot — same registry, same
    # override rule as issue_watcher_cron.sh. No DOTFILES_ROOT here: the
    # unregistered-repo gate exits before the block ever reaches
    # PMV_NAME_LIB, which is the only line that reads it.
    run env IW_WATCHED_REPOS="$WATCHED" \
        TARGET_REPO="acme/not-watched" TARGET_HOST="github.com" PR_NUMBER="7" bash "$_out"
    assert_success
    [ -z "$output" ]
}

@test "1565: the extracted block exits 0 on the paths that stop with a WARN" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    local _root="${TEST_TEMP_HOME}/fakeroot"
    mkdir -p "${_root}"
    local _reg="${TEST_TEMP_HOME}/warn-watched.json"

    # A herdr stub keeps the run off this machine's real herdr; the block only
    # needs `command -v herdr` to succeed before it reaches these stops.
    local _bin="${TEST_TEMP_HOME}/stubbin"
    mkdir -p "$_bin"
    printf '#!/bin/sh\nexit 0\n' >"${_bin}/herdr"
    chmod +x "${_bin}/herdr"

    # 1. A verify_skill outside the allowlist: WARN, stop, status 0.
    printf '[{"repo":"acme/dotfiles","verify_skill":"evil:do-something-else"}]\n' >"$_reg"
    run env PATH="${_bin}:${PATH}" IW_WATCHED_REPOS="$_reg" DOTFILES_ROOT="$_root" \
        TARGET_REPO="acme/dotfiles" TARGET_HOST="github.com" PR_NUMBER="7" bash "$_out"
    assert_success
    assert_output --partial 'is not one of devx:pr-verify-merged'

    # 2. The deliberate stale-main-checkout stop: WARN, stop, status 0. Nothing
    #    has been closed or rebased at that point, and it must stay that way.
    mkdir -p "${_root}/shell-common/functions"
    # Both SSOTs the block sources: the name helper (#1530) and the agent
    # lookup (#1569). Either one missing is its own WARN-and-stop, which would
    # pre-empt the stale-main-checkout stop this case is here to observe.
    local _lib
    for _lib in herdr_agent_name.sh herdr_agent_lookup.sh; do
        cp "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/${_lib}" \
            "${_root}/shell-common/functions/${_lib}"
    done
    printf '[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged","path":"%s"}]\n' \
        "${TEST_TEMP_HOME}/not-a-repo" >"$_reg"
    run env PATH="${_bin}:${PATH}" IW_WATCHED_REPOS="$_reg" DOTFILES_ROOT="$_root" \
        TARGET_REPO="acme/dotfiles" TARGET_HOST="github.com" PR_NUMBER="7" bash "$_out"
    assert_success
    assert_output --partial 'is not a git worktree root'
}

@test "1569: a missing agent-lookup SSOT warns and skips, it never guesses" {
    # The counterpart to the name helper's guard: the block sources the lookup
    # SSOT rather than carrying a copy of the predicate, so an unreadable
    # helper must stop the dispatch the same way — one WARN, status 0, and
    # nothing touched. Falling back to an inline match is what #1569 removed.
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"

    local _root="${TEST_TEMP_HOME}/fakeroot-nolookup"
    mkdir -p "${_root}/shell-common/functions"
    cp "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/herdr_agent_name.sh" \
        "${_root}/shell-common/functions/herdr_agent_name.sh"

    local _bin="${TEST_TEMP_HOME}/stubbin-nolookup"
    mkdir -p "$_bin"
    printf '#!/bin/sh\nexit 0\n' >"${_bin}/herdr"
    chmod +x "${_bin}/herdr"

    local _reg="${TEST_TEMP_HOME}/nolookup-watched.json"
    printf '[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged","path":"%s"}]\n' \
        "${TEST_TEMP_HOME}/not-a-repo" >"$_reg"

    run env PATH="${_bin}:${PATH}" IW_WATCHED_REPOS="$_reg" DOTFILES_ROOT="$_root" \
        TARGET_REPO="acme/dotfiles" TARGET_HOST="github.com" PR_NUMBER="7" bash "$_out"
    assert_success
    assert_output --partial 'herdr_agent_lookup.sh not readable'
    # Stopped there — the later stops never ran.
    refute_output --partial 'is not a git worktree root'
}

@test "1569: the dispatch block carries no inline agent-match predicate" {
    # The whole point of the unification: `under(` and the cwd/foreground_cwd
    # select must exist in exactly one file, and it is not this one.
    # The executed block only, not the prose fences below it — the herdr API
    # table there names `.foreground_cwd` as documentation, which is fine.
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run bash -c "grep -n -e 'def under(' -e 'foreground_cwd' '$_out'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    # …and it does source the file that has it.
    run grep -qF -- 'shell-common/functions/herdr_agent_lookup.sh' "$_out"
    assert_success
}

@test "1565: gh:pr-merge Step 5 cannot leak the staged temp file" {
    # mktemp'd, sourced, and removed — but the sourced block returns early on
    # most paths and the caller may run under `set -e`, so the removal has to
    # be armed as a trap before anything can go wrong.
    local _skill
    _skill="$(_pmv_merge_skill)"
    run grep -qF -- "trap 'rm -f \"\$PMV_SH\"' EXIT INT TERM" "$_skill"
    assert_success
    run grep -qF -- 'trap - EXIT INT TERM' "$_skill"
    assert_success
}

@test "1565: gh:pr-post-merge-verify survives as a standalone entry point" {
    # Removing the skill would take `/gh-pr-post-merge-verify <N>` — the manual
    # re-run — with it. Step 5 borrows its block; it does not absorb it.
    local _skill="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/SKILL.md"
    [ -r "$_skill" ]
    run grep -qF -- 'name: gh:pr-post-merge-verify' "$_skill"
    assert_success
    run grep -qF -- 'references/dispatch.sh.md' "$_skill"
    assert_success
    [ -r "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/references/help.md" ]
}

@test "1565: top-level gh:pr-merge behavior is otherwise untouched" {
    # The merge itself, the report, and the unwatched-repo silence are what a
    # top-level `/gh-pr-merge <N>` run is judged on — Step 5 gained a block,
    # it did not gain a gate.
    local _skill
    _skill="$(_pmv_merge_skill)"
    run grep -qF -- 'gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch' "$_skill"
    assert_success
    run grep -qF -- 'Print **only** the compact report' "$_skill"
    assert_success
    run grep -qF -- 'no output, no' "$_skill"
    assert_success
}

# --- #1571: the herdr settle waits ----------------------------------------
#
# Two calls in this dispatch bring something up that is not usable the instant
# herdr answers: `tab create` returns a pane whose shell is not interactive yet
# (`agent start` on it is refused with `agent_pane_busy`), and `agent start`
# returns `"agent_status":"idle"` for a claude TUI whose key-input loop is not
# attached yet (the prompt is swallowed and the session sits empty — the #1571
# report). ~5s was measured to fail every time and ~13s to land (#1560), so 13
# is the repo standard at both points.
#
# Observed by the recorded `sleep` calls, never by wall clock: a timing test
# that measured elapsed seconds would make the suite pay 26 real seconds per
# dispatch and still not prove where in the sequence the wait fell.

@test "1571: a fresh dispatch settles before agent start AND before the prompt" {
    run dispatch
    assert_success
    [ "$(_pmv_log_count '^sleep 13$')" -eq 2 ]
    local _tab _s1 _start _s2 _prompt
    _tab=$(_pmv_log_line 'herdr tab create')
    _start=$(_pmv_log_line 'herdr agent start')
    _prompt=$(_pmv_log_line 'herdr agent prompt')
    _s1=$(grep -n '^sleep 13$' "$FAKE_HERDR_LOG" | sed -n '1p' | cut -d: -f1)
    _s2=$(grep -n '^sleep 13$' "$FAKE_HERDR_LOG" | sed -n '2p' | cut -d: -f1)
    # tab create < settle < agent start < settle < agent prompt
    [ "$_tab" -lt "$_s1" ]
    [ "$_s1" -lt "$_start" ]
    [ "$_start" -lt "$_s2" ]
    [ "$_s2" -lt "$_prompt" ]
}

@test "1571: the agent_name_taken fallback settles the pane but not the prompt" {
    # The pane is still brand new, so the wait before `agent start` is owed
    # either way; the session the fallback prompts was started by someone else
    # and is warm by definition, so the second wait is not (#1571 D-2, the same
    # rule _pmt_launch_fresh follows).
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"agent_name_taken"}}'
    run dispatch
    assert_success
    assert_output --partial "already registered — prompting the existing session"
    [ "$(_pmv_log_count '^sleep 13$')" -eq 1 ]
    local _s _start _prompt
    _s=$(_pmv_log_line '^sleep 13$')
    _start=$(_pmv_log_line 'herdr agent start')
    _prompt=$(_pmv_log_line 'herdr agent prompt')
    [ "$_s" -lt "$_start" ]
    [ "$_prompt" -gt "$_start" ]
}

@test "1571: a failed agent start never reaches the prompt settle" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"pane_not_ready"}}'
    run dispatch
    assert_success
    assert_output --partial "herdr agent start mv-dotfiles-pr-77 failed"
    # Only the pre-start wait ran; the dispatch stopped before the prompt one.
    [ "$(_pmv_log_count '^sleep 13$')" -eq 1 ]
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "agent prompt"
}

@test "1571: a failed tab create never settles at all" {
    FAKE_HERDR_RC_TAB_CREATE=1
    run dispatch
    assert_success
    assert_output --partial "herdr tab create failed for label pr-77"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "sleep"
}

@test "1571: a repo with no derivable agent name settles neither wait" {
    # The wait sits after the name derivation on purpose: a repo that cannot
    # produce a herdr-legal name skips out, and paying 13s first would be pure
    # waste on a path that never touches the pane again.
    cat >"$WATCHED" <<'JSON'
[ { "repo": "acme/...", "verify_skill": "devx:pr-verify-merged" } ]
JSON
    run dispatch 'acme/...'
    assert_success
    assert_output --partial "cannot derive an agent name"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "sleep"
}

@test "1571: PMV_SETTLE_SECONDS=0 removes both waits" {
    # The bats suite must never sleep 13 real seconds twice per dispatch — the
    # same escape hatch _IW_IDLE_POLL_SLEEP established.
    export PMV_SETTLE_SECONDS=0
    run dispatch
    assert_success
    assert_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "agent start mv-dotfiles-pr-77"
    assert_output --partial "agent prompt mv-dotfiles-pr-77"
    refute_output --partial "sleep"
}

@test "1571: PMV_SETTLE_SECONDS overrides the duration at both points" {
    export PMV_SETTLE_SECONDS=7
    run dispatch
    assert_success
    [ "$(_pmv_log_count '^sleep 7$')" -eq 2 ]
    [ "$(_pmv_log_count '^sleep 13$')" -eq 0 ]
}

# --- #1571: the shipped block, not just the mirror -------------------------

@test "1571: dispatch.sh.md declares the settle constant with the 13s default" {
    run grep -qF -- 'PMV_SETTLE_SECONDS="${PMV_SETTLE_SECONDS:-13}"' "$(_pmv_dispatch_doc)"
    assert_success
    run grep -qF -- 'pmv_settle() { [ "$PMV_SETTLE_SECONDS" = "0" ] || sleep "$PMV_SETTLE_SECONDS"; }' \
        "$(_pmv_dispatch_doc)"
    assert_success
}

@test "1571: dispatch.sh.md settles between tab create and agent start" {
    local _doc _tab _settle _start
    _doc="$(_pmv_dispatch_doc)"
    _tab=$(grep -n 'TAB_JSON=$(herdr tab create' "$_doc" | head -1 | cut -d: -f1)
    _settle=$(grep -n '^pmv_settle$' "$_doc" | head -1 | cut -d: -f1)
    _start=$(grep -n 'herdr agent start "\$PMV_AGENT"' "$_doc" | head -1 | cut -d: -f1)
    [ -n "$_tab" ] && [ -n "$_settle" ] && [ -n "$_start" ]
    [ "$_tab" -lt "$_settle" ]
    [ "$_settle" -lt "$_start" ]
}

@test "1571: dispatch.sh.md settles between agent start and agent prompt, fresh only" {
    local _doc _start _settle _prompt
    _doc="$(_pmv_dispatch_doc)"
    _start=$(grep -n 'herdr agent start "\$PMV_AGENT"' "$_doc" | head -1 | cut -d: -f1)
    _settle=$(grep -n 'pmv_settle$' "$_doc" | awk -F: -v s="$_start" '$1 > s {print $1; exit}' | cut -d: -f1)
    _prompt=$(grep -n 'herdr agent prompt "\$PMV_AGENT"' "$_doc" | head -1 | cut -d: -f1)
    [ -n "$_start" ] && [ -n "$_settle" ] && [ -n "$_prompt" ]
    [ "$_start" -lt "$_settle" ]
    [ "$_settle" -lt "$_prompt" ]
    # The settle call sits in the `else` branch of the start guard — reached
    # only on a fresh start, never on the agent_name_taken fallback path.
    run grep -qF -- 'already registered — prompting the existing session' "$_doc"
    assert_success
}

@test "1571: dispatch.sh.md does not grow a fourth agent_pane_busy retry loop" {
    # #1569 unifies the three dispatchers' start logic; a hand-rolled retry
    # here would be a copy that unification has to undo (#1571 D-3). Comment
    # lines are skipped — the rationale for NOT retrying names the error code
    # it is about (same carve-out as R-6 above).
    run bash -c "grep -vE '^[[:space:]]*#' '$(_pmv_dispatch_doc)' | grep -n 'agent_pane_busy'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- #1571: the cross-file drift guard ------------------------------------
#
# This repo has now shipped the same defect twice by fixing two of the three
# herdr dispatchers (#1530 -> #1549, #1560 -> #1571). The comments name each
# other; this pins the values, so the third site cannot quietly stay behind.

_pmv_wait_files() {
    printf '%s\n' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh" \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/pr_merge_train_cron.sh" \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md"
}

_PMV_WAIT_ASSIGN='^(_IW_SETTLE_SECONDS|_PMT_SETTLE_SECONDS|PMV_SETTLE_SECONDS|_IW_START_RETRY_SLEEP|_PMT_START_RETRY_SLEEP)='

@test "1571: all five herdr wait constants exist across the three dispatchers" {
    local _n
    _n=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" | wc -l)
    [ "$_n" -eq 5 ]
}

@test "1571: no herdr wait constant has drifted off 13" {
    local _bad
    _bad=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" | grep -vE ':-13\}"$' || true)
    [ -z "$_bad" ] || fail "wait constant not defaulted to 13: ${_bad}"
}

@test "1571: every herdr wait constant stays env-overridable" {
    local _bad
    _bad=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" |
        grep -vE '="\$\{[A-Z_]+:-13\}"$' || true)
    [ -z "$_bad" ] || fail "wait constant is not env-overridable: ${_bad}"
}

@test "1571: the three dispatchers' wait comments name each other" {
    local _iw _pmt _doc
    _iw="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh"
    _pmt="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/pr_merge_train_cron.sh"
    _doc="$(_pmv_dispatch_doc)"
    run grep -qF -- 'PMV_SETTLE_SECONDS' "$_iw"
    assert_success
    run grep -qF -- 'PMV_SETTLE_SECONDS' "$_pmt"
    assert_success
    run grep -qF -- '_IW_SETTLE_SECONDS' "$_doc"
    assert_success
    run grep -qF -- '_PMT_SETTLE_SECONDS' "$_doc"
    assert_success
}

# --- #1554: don't leak the just-created verification tab on agent-start failure

@test "1554: an agent start failure closes the just-created verification tab" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"pane_not_ready"}}'
    run dispatch
    assert_success
    assert_output --partial "closed the empty verification tab wV:t99"
    assert_output --partial "herdr agent start mv-dotfiles-pr-77 failed"
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "tab close wV:t99"
}

@test "1554: a failing tab close warns but does not stop the dispatch" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"pane_not_ready"}}'
    FAKE_HERDR_RC_TAB_CLOSE=1
    run dispatch
    assert_success
    assert_output --partial "could not close tab wV:t99 — close it by hand"
    assert_output --partial "herdr agent start mv-dotfiles-pr-77 failed"
}

@test "1554: agent_name_taken reuses the tab instead of closing it" {
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"agent_name_taken"}}'
    run dispatch
    assert_success
    refute_output --partial "closed the empty verification tab"
    refute_output --partial "could not close tab"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close wV:t99"
}

@test "1554: a failing agent prompt leaves the live verification tab alone" {
    FAKE_HERDR_RC_AGENT_PROMPT=1
    FAKE_HERDR_OUT_AGENT_PROMPT='{"error":{"code":"agent_prompt_stalled"}}'
    run dispatch
    assert_success
    refute_output --partial "closed the empty verification tab"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close wV:t99"
}

@test "1554: an unreadable tab id is never guessed at for cleanup" {
    FAKE_HERDR_OUT_TAB_CREATE='{"result":{"pane":{"pane_id":"wV:p99"}}}'
    FAKE_HERDR_RC_AGENT_START=1
    FAKE_HERDR_OUT_AGENT_START='{"error":{"code":"pane_not_ready"}}'
    run dispatch
    assert_success
    refute_output --partial "closed the empty verification tab"
    refute_output --partial "could not close tab"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab close -"
}

@test "1554: dispatch.sh.md closes the verification tab on the same agent-start failure branch" {
    local _doc _start _close
    _doc="$(_pmv_dispatch_doc)"
    _start=$(grep -n 'herdr agent start "\$PMV_AGENT"' "$_doc" | head -1 | cut -d: -f1)
    _close=$(grep -n 'herdr tab close "\$NEW_TAB"' "$_doc" | head -1 | cut -d: -f1)
    [ -n "$_start" ] && [ -n "$_close" ]
    [ "$_start" -lt "$_close" ]
    run grep -qF -- 'closed the empty verification tab' "$_doc"
    assert_success
}

# --- #1576: an empty binding in Step 5's gate is named, never silent -------
#
# The gate looks one registry key up and does nothing when the answer is empty.
# An unwatched repo and a TARGET_REPO that was never substituted both produce
# that same empty answer, so PR #1572's missing dispatch left no trace at all:
# no pr-<N> tab, no rebase, and not one line to say which of the two happened.
# The lookup only means "unwatched" once the five values are known to be bound,
# so the binding check runs first and names the offenders. The unwatched-repo
# silence (#1511 A-1) is what must NOT change, and is pinned here too.

# Step 5's gate is the first bash fence under "## Step 5" — the one opened by
# the `# Substitute the five values` comment, not Step 3's merge command or
# Step 5's own `gh pr view`. Taken out of the shipped SKILL.md, never a copy.
_PMV_GATE_AWK='$0 == f "bash" { inb = 1; p = 0; next }
inb && $0 == f { if (p) exit; inb = 0; next }
inb && !p && $0 ~ /^# Substitute the five values/ { p = 1 }
p { print }'

_pmv_gate_block() {
    local _out="${TEST_TEMP_HOME}/gate-block.sh"
    awk -v f="$(printf '\140\140\140')" "$_PMV_GATE_AWK" "$(_pmv_merge_skill)" >"$_out"
    printf '%s' "$_out"
}

# Paste it the way Step 5 instructs: the five placeholders are replaced by the
# caller's values — an empty one is exactly the mistake under test. Quoted so
# a whitespace-only value survives the substitution instead of collapsing to
# an unquoted no-op (an unquoted `TARGET_REPO=   ` assigns empty anyway,
# which would silently retest the plain-empty case).
_pmv_gate_bind() {
    local _out="${TEST_TEMP_HOME}/gate-bound.sh"
    sed -e "s|^PR_NUMBER=<N>.*|PR_NUMBER=\"${1-}\"|" \
        -e "s|^TARGET_REPO=<owner/repo>.*|TARGET_REPO=\"${2-}\"|" \
        -e "s|^HEAD_BRANCH=<headRefName>.*|HEAD_BRANCH=\"${3-}\"|" \
        -e "s|^BASE_BRANCH=<baseRefName>.*|BASE_BRANCH=\"${4-}\"|" \
        -e "s|^REMOTE=<remote>.*|REMOTE=\"${5-}\"|" "$(_pmv_gate_block)" >"$_out"
    printf '%s' "$_out"
}

# A herdr that records instead of acting: an empty binding must never reach it.
_pmv_gate_bin() {
    local _bin="${TEST_TEMP_HOME}/gatebin"
    mkdir -p "$_bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexit 0\n' "$FAKE_HERDR_LOG" >"${_bin}/herdr"
    chmod +x "${_bin}/herdr"
    printf '%s' "$_bin"
}

# Bind and run the gate in one call, the way Step 5 pastes it: $1 is the
# registry, then the five values. Leaves `run`'s $status/$output/$lines set.
_pmv_gate_run() {
    local _reg="$1"
    shift
    run env PATH="$(_pmv_gate_bin):${PATH}" IW_WATCHED_REPOS="$_reg" \
        DOTFILES_ROOT="$_BATS_REAL_DOTFILES_ROOT" bash "$(_pmv_gate_bind "$@")"
}

@test "1576: Step 5's gate block extracts, binds, and is valid shell" {
    local _bound
    _bound="$(_pmv_gate_bind 77 acme/dotfiles wt/issue-77/1 main origin)"
    run head -n 1 "$_bound"
    assert_output --partial 'Substitute the five values'
    run tail -n 1 "$_bound"
    assert_output "fi"
    # A renamed placeholder would leave the assignments unsubstituted and make
    # every test below pass for the wrong reason.
    run grep -cE '^(PR_NUMBER|TARGET_REPO|HEAD_BRANCH|BASE_BRANCH|REMOTE)=<' "$_bound"
    assert_output "0"
    run bash -n "$_bound"
    assert_success
}

@test "1576: an empty TARGET_REPO is named instead of read as 'unwatched'" {
    _pmv_gate_run "$WATCHED" 77 "" wt/issue-77/1 main origin
    assert_success
    assert_output --partial '[WARN] gh:pr-merge:'
    assert_output --partial 'TARGET_REPO'
    # Named, and stopped: nothing may be closed or rebased on a half-bound run.
    refute_output --partial 'gh:pr-post-merge-verify'
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

# PR #1603 review (agy + codex): "non-empty" is not "correctly substituted" —
# a forgotten placeholder or a whitespace-only paste both pass a bare
# `[ -n ]` check and would silently reproduce the exact #1576 bug this gate
# exists to surface.

@test "1576: an unsubstituted placeholder is named, not read as a real value" {
    _pmv_gate_run "$WATCHED" 77 '<owner/repo>' wt/issue-77/1 main origin
    assert_success
    assert_output --partial '[WARN] gh:pr-merge:'
    assert_output --partial 'TARGET_REPO'
    refute_output --partial 'gh:pr-post-merge-verify'
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "1576: a whitespace-only value is named, not read as bound" {
    _pmv_gate_run "$WATCHED" 77 '   ' wt/issue-77/1 main origin
    assert_success
    assert_output --partial '[WARN] gh:pr-merge:'
    assert_output --partial 'TARGET_REPO'
    refute_output --partial 'gh:pr-post-merge-verify'
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "1576: whichever of the five is empty is the one the WARN names" {
    local _v
    for _v in PR_NUMBER TARGET_REPO HEAD_BRANCH BASE_BRANCH REMOTE; do
        case "$_v" in
        PR_NUMBER) _pmv_gate_run "$WATCHED" "" acme/dotfiles wt/issue-77/1 main origin ;;
        TARGET_REPO) _pmv_gate_run "$WATCHED" 77 "" wt/issue-77/1 main origin ;;
        HEAD_BRANCH) _pmv_gate_run "$WATCHED" 77 acme/dotfiles "" main origin ;;
        BASE_BRANCH) _pmv_gate_run "$WATCHED" 77 acme/dotfiles wt/issue-77/1 "" origin ;;
        REMOTE) _pmv_gate_run "$WATCHED" 77 acme/dotfiles wt/issue-77/1 main "" ;;
        esac
        assert_success
        assert_output --partial "$_v"
        [ "${#lines[@]}" -eq 1 ]
    done
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "1576: several empty bindings share one WARN line, not one each" {
    _pmv_gate_run "$WATCHED" "" "" wt/issue-77/1 main ""
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    assert_output --partial 'PR_NUMBER'
    assert_output --partial 'TARGET_REPO'
    assert_output --partial 'REMOTE'
    refute_output --partial 'HEAD_BRANCH'
    refute_output --partial 'BASE_BRANCH'
}

@test "1576: a fully bound but unwatched repo is still silent (#1511 A-1)" {
    # The regression this fix must not cause: an unregistered repo stays
    # byte-identical to its pre-#1511 behavior — no WARN, no output at all.
    _pmv_gate_run "$WATCHED" 77 other/repo wt/issue-77/1 main origin
    assert_success
    assert_output ""
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "1576: a fully bound registered repo still reaches the dispatch" {
    # The other half of the same guard: the binding check must gate nothing
    # when all five are bound. The registry points the dispatch at a path that
    # is not a git worktree root, so it stops with its own WARN before any
    # side effect — proof the staged block ran.
    local _reg="${TEST_TEMP_HOME}/bound-watched.json"
    printf '[{"repo":"acme/dotfiles","verify_skill":"devx:pr-verify-merged","path":"%s"}]\n' \
        "${TEST_TEMP_HOME}/not-a-repo" >"$_reg"
    _pmv_gate_run "$_reg" 77 acme/dotfiles wt/issue-77/1 main origin
    assert_success
    assert_output --partial '[WARN] gh:pr-post-merge-verify:'
    assert_output --partial 'is not a git worktree root'
    # codex review (PR #1603): the warning text alone doesn't prove the
    # dispatch actually ran rather than being skipped — pin that no herdr
    # call happened either, which is what this stop point guarantees.
    run cat "$FAKE_HERDR_LOG"
    assert_output ""
}

@test "1576: the binding check runs before the registry lookup" {
    local _skill _check _lookup
    _skill="$(_pmv_merge_skill)"
    _check=$(grep -n 'PMV_MISSING=""' "$_skill" | head -1 | cut -d: -f1)
    _lookup=$(grep -n 'VERIFY_SKILL=\$(jq -r --arg r' "$_skill" | head -1 | cut -d: -f1)
    [ -n "$_check" ] && [ -n "$_lookup" ]
    [ "$_check" -lt "$_lookup" ]
}

# --- #1577: the verification session lives in its own detached worktree ----
#
# The tab used to open in $MAIN_ROOT — the shared main checkout that humans and
# other AI sessions check branches out in, and that step 3 of THIS dispatch
# rebases. On back-to-back merges the N+1th dispatch moved the ground under the
# Nth session; tab `pr-1567` vanished that way (2026-08-28). Each PR now gets
# `<git-common-dir>/pr-post-merge-verify/pr-<N>`, created detached off the ref
# step 3 already fetched, reused when it is already there, and never torn down
# here (its lifetime is the tab's — cleanup timing is a later decision).

_pmv_scratch_for() { printf '%s/.git/pr-post-merge-verify/pr-%s' "$MAIN_ROOT" "$1"; }

@test "1577: the verification tab opens in the PR's own worktree, not the main checkout" {
    run dispatch
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "herdr tab create --workspace wV --cwd $(_pmv_scratch_for 77) --label pr-77 --no-focus"
    # The whole point: the shared checkout is no longer the session's home.
    refute_output --partial "--cwd ${MAIN_ROOT} --label pr-77"
}

@test "1577: the report names the worktree the session lives in" {
    run dispatch
    assert_success
    assert_output --partial "cwd:    $(_pmv_scratch_for 77)"
}

@test "1577: an absent worktree is created detached at the merged base" {
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "worktree-add ${MAIN_ROOT} $(_pmv_scratch_for 77) origin/main"
    assert_output --partial "mkdir-p ${MAIN_ROOT}/.git/pr-post-merge-verify"
}

@test "1577: the remote and base branch reach the worktree, never a hardcoded origin/main" {
    FAKE_MAIN_BRANCH=develop
    run dispatch acme/dotfiles upstream develop
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "worktree-add ${MAIN_ROOT} $(_pmv_scratch_for 77) upstream/develop"
}

@test "1577: an empty base branch reaches the worktree as step 3's own fallback" {
    # `origin/` with nothing after it would detach at whatever that resolves to.
    FAKE_MAIN_BRANCH=master
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "worktree-add ${MAIN_ROOT} $(_pmv_scratch_for 77) origin/master"
    refute_output --partial "origin/ "
}

@test "1577: an existing worktree is reused, never added a second time" {
    FAKE_SCRATCH_EXISTS=1
    run dispatch
    assert_success
    assert_output --partial "reusing verification worktree $(_pmv_scratch_for 77)"
    assert_output --partial "post-merge verification dispatched"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "worktree-add"
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "--cwd $(_pmv_scratch_for 77) --label pr-77"
}

@test "1605 review: a directory that exists but is not a registered worktree is wiped and recreated" {
    FAKE_SCRATCH_EXISTS=1
    FAKE_SCRATCH_REGISTERED=0
    run dispatch
    assert_success
    refute_output --partial "reusing verification worktree"
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "rm-rf $(_pmv_scratch_for 77)"
    assert_output --partial "worktree-add ${MAIN_ROOT} $(_pmv_scratch_for 77) origin/main"
}

@test "1605 review: the stale directory is removed before worktree-add runs, not after" {
    FAKE_SCRATCH_EXISTS=1
    FAKE_SCRATCH_REGISTERED=0
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    _rm_line=$(printf '%s\n' "$output" | grep -n "^rm-rf " | head -1 | cut -d: -f1)
    _add_line=$(printf '%s\n' "$output" | grep -n "^worktree-add " | head -1 | cut -d: -f1)
    [ -n "$_rm_line" ]
    [ -n "$_add_line" ]
    [ "$_rm_line" -lt "$_add_line" ]
}

@test "1605 review: a registered worktree is reused without ever being removed" {
    FAKE_SCRATCH_EXISTS=1
    FAKE_SCRATCH_REGISTERED=1
    run dispatch
    assert_success
    assert_output --partial "reusing verification worktree $(_pmv_scratch_for 77)"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "rm-rf"
    refute_output --partial "worktree-add"
}

@test "1577: two PRs get two different worktrees" {
    run gh_pr_post_merge_verify 77 acme/dotfiles github.com "$MAIN_ROOT" wt/issue-77/1 "$WATCHED"
    assert_success
    run gh_pr_post_merge_verify 88 acme/dotfiles github.com "$MAIN_ROOT" wt/issue-88/1 "$WATCHED"
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "--cwd $(_pmv_scratch_for 77) --label pr-77"
    assert_output --partial "--cwd $(_pmv_scratch_for 88) --label pr-88"
    [ "$(_pmv_scratch_for 77)" != "$(_pmv_scratch_for 88)" ]
}

@test "1577: step 3 still rebases the main checkout, never the scratch worktree" {
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    assert_output --partial "sync ${MAIN_ROOT} origin main"
    refute_output --partial "sync $(_pmv_scratch_for 77)"
}

@test "1577: the workspace lookup still asks about the main checkout" {
    # WS_ID only groups the tab; a worktree created seconds ago has no herdr
    # workspace of its own on a first dispatch, so asking about it answers
    # nothing. Grouping is the main checkout's, the working directory is not.
    run dispatch
    assert_success
    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "herdr worktree list --cwd ${MAIN_ROOT} --json"
}

@test "1577: a worktree that cannot be created stops before the tab" {
    FAKE_WORKTREE_ADD_RC=1
    run dispatch
    assert_success
    assert_output --partial "could not create the verification worktree $(_pmv_scratch_for 77)"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
}

@test "1577: an unresolvable git common dir never falls back to the main checkout" {
    FAKE_GIT_COMMON_DIR=""
    run dispatch
    assert_success
    assert_output --partial "cannot resolve the git common dir of ${MAIN_ROOT}"
    refute_output --partial "post-merge verification dispatched"
    run cat "$FAKE_HERDR_LOG"
    refute_output --partial "tab create"
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "worktree-add"
}

@test "1577: nothing here tears the worktree down" {
    # Decided out of scope: the worktree's lifetime is the tab's, and the tab
    # is closed by the operator after reading the result. A teardown here would
    # delete a directory a live session is standing in.
    run dispatch
    assert_success
    run cat "$FAKE_GIT_LOG"
    refute_output --partial "worktree-remove"
}

@test "1577: dispatch.sh.md opens the tab on the scratch worktree, both argv forms" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run grep -c -- 'herdr tab create --workspace "$WS_ID" --cwd "$PMV_SCRATCH"' "$_out"
    assert_output "2"
    run grep -c -- 'herdr tab create --workspace "$WS_ID" --cwd "$MAIN_ROOT"' "$_out"
    assert_output "0"
}

@test "1577: dispatch.sh.md derives the path per PR under the git common dir" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run grep -qF -- 'PMV_SCRATCH="${PMV_COMMON_DIR}/pr-post-merge-verify/pr-${PR_NUMBER}"' "$_out"
    assert_success
    # `--path-format=absolute` (git 2.31+): a bare --git-common-dir prints a
    # path relative to the cwd, which would place the worktree anywhere.
    run grep -qF -- 'rev-parse --path-format=absolute --git-common-dir' "$_out"
    assert_success
}

@test "1577: dispatch.sh.md creates it detached, off the ref step 3 already fetched" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run grep -qF -- 'worktree add --detach "$PMV_SCRATCH" "${REMOTE}/${BASE_BRANCH}"' "$_out"
    assert_success
    # A second fetch would be redundant: step 3's is the only one in the block.
    run grep -c -- 'git -C "$MAIN_ROOT" fetch' "$_out"
    assert_output "1"
}

@test "1577: dispatch.sh.md reuses an existing worktree and tears none down" {
    local _out="${TEST_TEMP_HOME}/extracted.sh"
    bash -c "awk -v f=\"\$(printf '\\140\\140\\140')\" '${_PMV_EXTRACT_AWK}' \
        '$(_pmv_dispatch_doc)' > '${_out}'"
    run grep -qF -- 'if [ -d "$PMV_SCRATCH" ]; then' "$_out"
    assert_success
    run grep -c -- 'worktree remove' "$_out"
    assert_output "0"
}
