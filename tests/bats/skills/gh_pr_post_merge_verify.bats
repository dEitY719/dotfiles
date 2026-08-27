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
    unset FAKE_HERDR_PRESENT FAKE_HERDR_LOG FAKE_GIT_LOG FAKE_WORKTREE_PORCELAIN \
        FAKE_WORKTREE_RC FAKE_MAIN_DIRTY FAKE_SYNC_RC \
        FAKE_HERDR_OUT_AGENT_LIST FAKE_HERDR_OUT_WORKTREE_LIST \
        FAKE_HERDR_OUT_TAB_CREATE FAKE_HERDR_OUT_AGENT_START FAKE_HERDR_OUT_AGENT_PROMPT \
        FAKE_HERDR_RC_AGENT_LIST FAKE_HERDR_RC_TAB_CREATE FAKE_HERDR_RC_TAB_CLOSE \
        FAKE_HERDR_RC_AGENT_START FAKE_HERDR_RC_AGENT_PROMPT
}

dispatch() {
    gh_pr_post_merge_verify 77 "${1:-acme/dotfiles}" github.com "$MAIN_ROOT" wt/issue-77/1 "$WATCHED"
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
    assert_output --partial "agent:  pmv-github.com-acme-dotfiles-77"
    assert_output --partial "attach: herdr agent attach pmv-github.com-acme-dotfiles-77"

    run cat "$FAKE_HERDR_LOG"
    assert_output --partial "herdr tab close wV:t42"
    assert_output --partial "herdr tab create --workspace wV --cwd ${MAIN_ROOT} --label pr-77 --no-focus"
    assert_output --partial "herdr agent start pmv-github.com-acme-dotfiles-77 --kind claude --pane wV:p99 -- --dangerously-skip-permissions"
    assert_output --partial "herdr agent prompt pmv-github.com-acme-dotfiles-77 /devx-pr-verify-merged 77 --wait --until idle"
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
    assert_output --partial "herdr agent start pmv-github.com-acme-dotfiles-77 failed"
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
    assert_output --partial "agent prompt pmv-github.com-acme-dotfiles-77"
}

@test "E-7: a failing prompt warns but the report still prints" {
    FAKE_HERDR_RC_AGENT_PROMPT=1
    FAKE_HERDR_OUT_AGENT_PROMPT='{"error":{"code":"agent_prompt_stalled"}}'
    run dispatch
    assert_success
    assert_output --partial "herdr agent prompt pmv-github.com-acme-dotfiles-77 failed (agent_prompt_stalled)"
    assert_output --partial "post-merge verification dispatched"
}

# --- unit pins on the easy-to-break pieces --------------------------------

@test "naming: the agent name is host-qualified (#1403/#1407 rationale)" {
    run pmv_agent_name github.com acme/dotfiles 77
    assert_output "pmv-github.com-acme-dotfiles-77"
    run pmv_agent_name ghe.example.com acme/dotfiles 77
    assert_output "pmv-ghe.example.com-acme-dotfiles-77"
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

@test "worktree lookup: the branch decides the path, not the directory name" {
    run pmv_worktree_for_branch wt/issue-77/1
    assert_output "$IMPL_WT"
    run pmv_worktree_for_branch main
    assert_output "$MAIN_ROOT"
    run pmv_worktree_for_branch wt/issue-99/1
    assert_output ""
}
