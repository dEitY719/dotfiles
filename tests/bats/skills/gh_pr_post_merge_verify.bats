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
{
  "$doc": { "purpose": "metadata, never a repo slug" },
  "acme/dotfiles": { "verify_skill": "devx:pr-verify-merged" },
  "acme/webapp": { "verify_skill": "devx:pr-verify-live" }
}
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
    unset PMV_PROMPT_TIMEOUT_MS
    unset FAKE_HERDR_PRESENT FAKE_JQ_PRESENT FAKE_HERDR_LOG FAKE_GIT_LOG FAKE_WORKTREE_PORCELAIN \
        FAKE_WORKTREE_RC FAKE_MAIN_DIRTY FAKE_SYNC_RC FAKE_MAIN_BRANCH FAKE_MAIN_TOPLEVEL \
        FAKE_HERDR_OUT_AGENT_LIST FAKE_HERDR_OUT_WORKTREE_LIST \
        FAKE_HERDR_OUT_TAB_CREATE FAKE_HERDR_OUT_AGENT_START FAKE_HERDR_OUT_AGENT_PROMPT \
        FAKE_HERDR_RC_AGENT_LIST FAKE_HERDR_RC_TAB_CREATE FAKE_HERDR_RC_TAB_CLOSE \
        FAKE_HERDR_RC_AGENT_START FAKE_HERDR_RC_AGENT_PROMPT
}

dispatch() {
    gh_pr_post_merge_verify 77 "${1:-acme/dotfiles}" github.com "$MAIN_ROOT" wt/issue-77/1 \
        "$WATCHED" "${2-}" "${3-}"
}

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

@test "gate: the shipped SSOT registers this repo for devx:pr-verify-merged" {
    # No running app to point a browser at, so the proof must come from a
    # fresh clone of the merge commit — -merged, not -live.
    run pmv_gate "${_BATS_REAL_DOTFILES_ROOT}/docs/.ssot/watched-repos.json" dEitY719/dotfiles
    assert_success
    assert_output "devx:pr-verify-merged"
}

@test "gate: the SSOT's \$-prefixed metadata key is not mistaken for a repo" {
    run pmv_gate "${_BATS_REAL_DOTFILES_ROOT}/docs/.ssot/watched-repos.json" '$doc'
    [ "$status" -eq 1 ]
    assert_output ""
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
    assert_output --partial "herdr tab create --workspace wV --cwd ${MAIN_ROOT} --label pr-77 --no-focus"
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
    assert_output --partial "post-merge verification dispatched"
}

# --- unit pins on the easy-to-break pieces --------------------------------

# The pre-#1530 name was `pmv-<host>-<owner>-<repo>-<N>` — 37 characters for
# this repo, and carrying a dot besides, so herdr refused every `agent start`
# and post-merge verification never ran once. These pin the shape herdr
# accepts, including the length budget that made truncation mandatory.
@test "naming: the agent name satisfies herdr's rule" {
    run pmv_agent_name github.com acme/dotfiles 77
    assert_output "mv-dotfiles-pr-77"
    [[ "$output" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] \
        || fail "not a valid herdr agent name: '$output'"
}

@test "naming: a mixed-case owner and a long repo still fit the 32-char budget" {
    run pmv_agent_name github.com dEitY719/A-Very-Long-Repository-Name 99999
    assert_success
    [[ "$output" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] \
        || fail "not a valid herdr agent name: '$output'"
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

@test "main root: an explicit main_checkout wins and expands a leading ~" {
    printf '{"acme/dotfiles":{"verify_skill":"devx:pr-verify-merged","main_checkout":"~/elsewhere"}}\n' >"$WATCHED"
    run pmv_main_root "$WATCHED" acme/dotfiles "${MAIN_ROOT}/.git"
    assert_output "${HOME}/elsewhere"
}

@test "main root: the shipped SSOT points this repo at its original checkout" {
    run pmv_main_root "${_BATS_REAL_DOTFILES_ROOT}/docs/.ssot/watched-repos.json" \
        dEitY719/dotfiles "${MAIN_ROOT}/.git"
    assert_output "${HOME}/dotfiles"
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
    printf '{"acme/dotfiles":{"verify_skill":"evil:do-something-else"}}\n' >"$WATCHED"
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
