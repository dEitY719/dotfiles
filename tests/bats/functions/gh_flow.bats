#!/usr/bin/env bats
# tests/bats/functions/gh_flow.bats
# Unit tests for gh_flow subcommands and post-condition helpers. The worker
# pipeline itself (Step 2: implement → commit → pr) is not exercised here —
# it needs claude / gh / gwt and is covered by manual integration testing.
# Project-board sync coverage moved to tests/bats/functions/gh_project_status.bats
# when the helper was extracted to its own module.

load '../test_helper'

# ---------------------------------------------------------------------------
# Fake repo + state directory helpers
# ---------------------------------------------------------------------------

# Build a minimal git repo at $HOME/repo and cd there via $REPO_DIR. We need
# an actual repo because _gh_flow_repo_name / _gh_flow_state_root key off
# `git rev-parse --show-toplevel`.
_setup_fake_repo() {
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
        GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    REPO_DIR="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO_DIR"
    git -C "$REPO_DIR" init --initial-branch=main -q
    echo base >"$REPO_DIR/base.txt"
    git -C "$REPO_DIR" add base.txt
    git -C "$REPO_DIR" commit -q -m "base"
}

# Seed one gh_flow state dir. Args: <issue> <state> [worktree_path] [pid]
_seed_state() {
    local _issue="$1" _state="$2" _wt="${3:-}" _pid="${4:-}"
    local _dir="$HOME/.local/state/gh-flow/repo/$_issue"
    mkdir -p "$_dir"
    printf '%s\n' "$_state" >"$_dir/state"
    if [ -n "$_wt" ]; then printf '%s\n' "$_wt" >"$_dir/worktree.path"; fi
    if [ -n "$_pid" ]; then printf '%s\n' "$_pid" >"$_dir/pid"; fi
    return 0
}

setup() {
    setup_isolated_home
    _setup_fake_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# help output
# ---------------------------------------------------------------------------

@test "help: mentions new status and prune subcommands" {
    run_in_bash "gh_flow --help"
    assert_success
    assert_output --partial "gh-flow status"
    assert_output --partial "gh-flow prune"
    assert_output --partial "--ai"
    assert_output --partial "claude (default) | codex | gemini"
    # New distinct failure states must be documented.
    assert_output --partial "failed:committing"
    assert_output --partial "failed:opening-pr"
    # Pre-flight gh-auth state and its recovery hint (issue #378).
    assert_output --partial "failed:precondition:gh-auth"
    assert_output --partial "gh auth login"
}

# ---------------------------------------------------------------------------
# gh_flow status
# ---------------------------------------------------------------------------

@test "status: empty repo — prints 'no state' and exits 0" {
    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "no state"
}

@test "status: lists each seeded entry with its state" {
    _seed_state 13 "polling" "" "99999"
    _seed_state 42 "failed:committing" "$TEST_TEMP_HOME/repo-issue-42-1" "12345"
    _seed_state 88 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#13"
    assert_output --partial "polling"
    assert_output --partial "#42"
    assert_output --partial "failed:committing"
    assert_output --partial "repo-issue-42-1"
    assert_output --partial "#88"
    assert_output --partial "done"
}

@test "status: pid liveness — current shell pid shown as alive" {
    _seed_state 77 "polling" "" "$$"

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#77"
    assert_output --partial "polling"
    # $$ from the bats shell is definitely alive while this test runs.
    assert_output --partial "alive"
}

@test "status: pid liveness — unreachable pid shown as dead" {
    # PID 1 is init — reachable by root but not by us. Fine for 'dead' check
    # only if we're non-root; most CI runs are non-root, but to be safe use an
    # unlikely huge pid.
    _seed_state 55 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-55-1" "9999999"

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#55"
    assert_output --partial "dead"
}

# ---------------------------------------------------------------------------
# gh_flow prune
# ---------------------------------------------------------------------------

@test "prune: removes 'done' state dirs and keeps 'failed:*' ones" {
    _seed_state 10 "done" "" ""
    _seed_state 20 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-20-1" "12345"
    _seed_state 30 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "#10"
    assert_output --partial "#30"
    assert_output --partial "#20"
    assert_output --partial "failed:implementing"

    # Done dirs gone.
    [ ! -d "$HOME/.local/state/gh-flow/repo/10" ]
    [ ! -d "$HOME/.local/state/gh-flow/repo/30" ]
    # Failed dir preserved.
    [ -d "$HOME/.local/state/gh-flow/repo/20" ]
}

@test "prune: failed entry shows the gwt teardown hint when worktree exists" {
    mkdir -p "$TEST_TEMP_HOME/repo-issue-42-1"
    _seed_state 42 "failed:opening-pr" "$TEST_TEMP_HOME/repo-issue-42-1" "12345"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "repo-issue-42-1"
    assert_output --partial "gwt teardown"
}

@test "prune: failed entry with no worktree shows scoped --force hint" {
    _seed_state 51 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-51-1" "12345"
    # worktree.path points somewhere that does not exist on disk — simulates
    # a worker that died after its own teardown or after the user manually
    # cleaned up the tree.

    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "#51"
    assert_output --partial "gh-flow prune --force 51"
    # State preserved when --force absent.
    [ -d "$HOME/.local/state/gh-flow/repo/51" ]
}

@test "prune --force: removes failed:* state when worktree is already gone" {
    _seed_state 61 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-61-1" "12345"
    _seed_state 62 "failed:opening-pr" "" "12346"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune --force"
    assert_success
    assert_output --partial "#61"
    assert_output --partial "worktree gone"
    assert_output --partial "#62"
    # Both orphan-state entries removed.
    [ ! -d "$HOME/.local/state/gh-flow/repo/61" ]
    [ ! -d "$HOME/.local/state/gh-flow/repo/62" ]
    # Counter reflects the cleanup.
    assert_output --partial "cleaned up 2 failed entr(ies)"
}

@test "prune: empty state tree — 'nothing to prune' and exits 0" {
    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "nothing to prune"
}

@test "prune: rejects unknown flags" {
    run_in_bash "cd '$REPO_DIR' && gh_flow prune --bogus 2>&1"
    assert_failure
    assert_output --partial "unknown arg"
}

# ---------------------------------------------------------------------------
# dispatcher: subcommand vs integer
# ---------------------------------------------------------------------------

@test "dispatcher: 'status' is not parsed as an invalid issue number" {
    # Regression: early code validated every arg as a positive integer before
    # dispatching subcommands. 'status' would trigger the integer-validation
    # error path.
    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    refute_output --partial "invalid issue number"
}

@test "dispatcher: garbage arg still errors with a useful hint" {
    run_in_bash "cd '$REPO_DIR' && gh_flow not-a-number 2>&1"
    assert_failure
    assert_output --partial "invalid issue number"
    # The error should point users to the subcommands.
    assert_output --partial "status"
    assert_output --partial "prune"
}

@test "dispatcher: invalid --ai value fails before worker spawn" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --ai not-supported 2>&1"
    assert_failure
    assert_output --partial "invalid --ai value"
    assert_output --partial "claude, codex, gemini"
}

@test "dispatcher: --ai without value fails with clear message" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --ai 2>&1"
    assert_failure
    assert_output --partial "--ai requires a value"
}

# ---------------------------------------------------------------------------
# --user option (multi-account, issue #365)
# ---------------------------------------------------------------------------

@test "dispatcher: --user without value fails with clear message" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --user 2>&1"
    assert_failure
    assert_output --partial "--user requires a value"
}

@test "dispatcher: --user <unknown> is rejected with available list" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --user nope 2>&1"
    assert_failure
    assert_output --partial "Unknown account: nope"
    assert_output --partial "Available:"
}

@test "dispatcher: --user with --ai codex is rejected (claude-only)" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --user personal --ai codex 2>&1"
    assert_failure
    assert_output --partial "--user is only supported with --ai claude"
}

@test "dispatcher: --user personal parses (parser accepts known account)" {
    run_in_bash "cd '$REPO_DIR' && gh_flow 13 --user personal 2>&1 || true"
    refute_output --partial "Unknown account"
    refute_output --partial "--user requires a value"
    refute_output --partial "only supported with --ai claude"
}

@test "help: documents --user option" {
    run_in_bash "gh_flow_help"
    assert_success
    assert_output --partial "--user"
}

# ---------------------------------------------------------------------------
# post-condition helpers (the ones the worker uses between Step 2 sub-steps)
# ---------------------------------------------------------------------------

@test "helper: has_work_for_commit — true when tree has uncommitted changes" {
    echo new >"$REPO_DIR/new.txt"
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_work_for_commit && echo YES || echo NO"
    assert_success
    assert_output --partial "YES"
}

@test "helper: has_work_for_commit — false on clean tree" {
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_work_for_commit && echo YES || echo NO"
    assert_success
    assert_output --partial "NO"
}

@test "helper: has_branch_commits — false when HEAD == origin/main base" {
    # This fake repo has no 'origin' remote; helper falls back to 'origin/main'
    # which also doesn't exist — git rev-list errors → count=0 → false.
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_branch_commits && echo YES || echo NO"
    assert_success
    assert_output --partial "NO"
}

@test "helper: has_branch_commits — true when branch has commits ahead of origin/HEAD" {
    # Build a real origin so rev-list has something to compare against.
    local origin="$TEST_TEMP_HOME/origin.git"
    git init --bare --initial-branch=main -q "$origin"
    git -C "$REPO_DIR" remote add origin "$origin"
    git -C "$REPO_DIR" push -q origin main
    git -C "$REPO_DIR" remote set-head origin main >/dev/null 2>&1 || true

    # Add one more commit on main — it's now ahead of origin/main.
    echo extra >"$REPO_DIR/extra.txt"
    git -C "$REPO_DIR" add extra.txt
    git -C "$REPO_DIR" commit -q -m "extra"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_branch_commits && echo YES || echo NO"
    assert_success
    assert_output --partial "YES"
}

# ---------------------------------------------------------------------------
# verdict matrix (issue #252)
# ---------------------------------------------------------------------------

# Install a tiny `gh` stub on PATH so _gh_flow_pr_view has predictable input.
# $1 = state token returned by `gh pr view <n> --json state[,reviewDecision]`.
# $2 = optional reviewDecision (empty by default) — appended on the
#      "--json state,reviewDecision" path used by _gh_flow_pr_view (issue #501).
# Empty $1 → simulate gh failure (exit 1) so verdict treats it as UNREACHABLE.
_install_gh_stub() {
    local _state="${1:-}"
    local _decision="${2:-}"
    mkdir -p "$TEST_TEMP_HOME/bin"
    if [ -z "$_state" ]; then
        printf '#!/usr/bin/env bash\nexit 1\n' >"$TEST_TEMP_HOME/bin/gh"
    else
        cat >"$TEST_TEMP_HOME/bin/gh" <<STUB
#!/usr/bin/env bash
# minimal gh pr view stub. The state,reviewDecision branch must come BEFORE
# the bare --json state branch — both contain "--json state" as a substring,
# so case-glob ordering matters.
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
    case "\$*" in
    *"--json state,reviewDecision"*) printf '%s\n%s' "$_state" "$_decision" ;;
    *"--json state"*) printf '%s' "$_state" ;;
    *"--json mergedAt"*) printf '%s' "2026-04-26" ;;
    *"--json closedAt"*) printf '%s' "2026-04-26" ;;
    esac
    exit 0
fi
exit 0
STUB
    fi
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
}

@test "verdict: done → 'safe to prune' + scoped prune action" {
    _seed_state 100 "done" "" ""
    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 100"
    assert_success
    assert_line --index 0 "done — safe to prune"
    assert_line --index 1 "gh-flow prune 100"
}

@test "verdict: polling + MERGED PR + alive pid → stuck poller + --force action" {
    _install_gh_stub "MERGED"
    _seed_state 201 "polling" "" "$$"
    printf '999\n' >"$HOME/.local/state/gh-flow/repo/201/pr.number"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 201"
    assert_success
    assert_output --partial "stuck poller"
    assert_output --partial "gh-flow prune --force 201"
}

@test "verdict: polling + OPEN + no reply.done + no decision → awaiting first review" {
    _install_gh_stub "OPEN" ""
    _seed_state 202 "polling" "" "$$"
    printf '888\n' >"$HOME/.local/state/gh-flow/repo/202/pr.number"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 202"
    assert_success
    assert_output --partial "awaiting first review"
    assert_output --partial "still working"
}

# Issue #501 polling/OPEN matrix: (reply.done, reviewDecision) → verdict.

@test "verdict: polling + OPEN + no reply.done + CHANGES_REQUESTED → comments arrived" {
    _install_gh_stub "OPEN" "CHANGES_REQUESTED"
    _seed_state 220 "polling" "" "$$"
    printf '500\n' >"$HOME/.local/state/gh-flow/repo/220/pr.number"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 220"
    assert_success
    assert_output --partial "comments arrived"
    assert_output --partial "/gh-pr-reply"
    assert_output --partial "still working"
}

@test "verdict: polling + OPEN + no reply.done + APPROVED → about to merge" {
    _install_gh_stub "OPEN" "APPROVED"
    _seed_state 221 "polling" "" "$$"
    printf '501\n' >"$HOME/.local/state/gh-flow/repo/221/pr.number"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 221"
    assert_success
    assert_output --partial "approved"
    assert_output --partial "about to merge"
}

@test "verdict: polling + OPEN + reply.done + no decision → awaiting Approve (replied)" {
    _install_gh_stub "OPEN" ""
    _seed_state 222 "polling" "" "$$"
    printf '502\n' >"$HOME/.local/state/gh-flow/repo/222/pr.number"
    touch "$HOME/.local/state/gh-flow/repo/222/reply.done"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 222"
    assert_success
    assert_output --partial "awaiting reviewer Approve"
    assert_output --partial "already replied"
    refute_output --partial "awaiting first review"
}

@test "verdict: polling + OPEN + reply.done + CHANGES_REQUESTED → additional changes after reply" {
    _install_gh_stub "OPEN" "CHANGES_REQUESTED"
    _seed_state 223 "polling" "" "$$"
    printf '503\n' >"$HOME/.local/state/gh-flow/repo/223/pr.number"
    touch "$HOME/.local/state/gh-flow/repo/223/reply.done"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 223"
    assert_success
    assert_output --partial "additional changes requested after reply"
}

@test "verdict: polling + OPEN + reply.done + APPROVED → about to merge" {
    _install_gh_stub "OPEN" "APPROVED"
    _seed_state 224 "polling" "" "$$"
    printf '504\n' >"$HOME/.local/state/gh-flow/repo/224/pr.number"
    touch "$HOME/.local/state/gh-flow/repo/224/reply.done"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 224"
    assert_success
    assert_output --partial "approved"
    assert_output --partial "about to merge"
}

@test "verdict: polling + no pr.number → stuck pre-PR" {
    _seed_state 203 "polling" "" "$$"
    # No pr.number file → _gh_flow_pr_state returns EMPTY → falls through.

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 203"
    assert_success
    assert_output --partial "stuck pre-PR"
    assert_output --partial "review"
}

@test "verdict: failed:* + worktree absent → state-only cleanup" {
    _seed_state 301 "failed:committing" "" "12345"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 301"
    assert_success
    assert_output --partial "dead failure"
    assert_output --partial "gh-flow prune 301"
}

@test "verdict: failed:* + worktree present → gwt teardown first" {
    mkdir -p "$TEST_TEMP_HOME/repo-issue-302-1"
    _seed_state 302 "failed:opening-pr" "$TEST_TEMP_HOME/repo-issue-302-1" "12345"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 302"
    assert_success
    assert_output --partial "worktree alive"
    assert_output --partial "gwt teardown --force"
}

# ---------------------------------------------------------------------------
# scoped prune (issue #252)
# ---------------------------------------------------------------------------

@test "prune <N>: rejects when worker pid is alive" {
    _seed_state 401 "polling" "" "$$"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune 401 2>&1"
    assert_failure
    assert_output --partial "#401"
    assert_output --partial "still alive"
    assert_output --partial "--force"
    [ -d "$HOME/.local/state/gh-flow/repo/401" ]
}

@test "prune <N>: rejects when worktree dir is present" {
    mkdir -p "$TEST_TEMP_HOME/repo-issue-402-1"
    _seed_state 402 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-402-1" "9999999"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune 402 2>&1"
    assert_failure
    assert_output --partial "#402"
    assert_output --partial "worktree exists"
    assert_output --partial "gwt teardown --force"
    [ -d "$HOME/.local/state/gh-flow/repo/402" ]
}

@test "prune --force <N>: still rejects when worktree dir is present" {
    mkdir -p "$TEST_TEMP_HOME/repo-issue-403-1"
    _seed_state 403 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-403-1" "9999999"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune --force 403 2>&1"
    assert_failure
    assert_output --partial "worktree exists"
    [ -d "$HOME/.local/state/gh-flow/repo/403" ]
}

@test "prune --force <N>: kills alive pid and removes state dir" {
    sleep 60 &
    local _victim=$!
    _seed_state 404 "polling" "" "$_victim"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune --force 404"
    assert_success
    [ ! -d "$HOME/.local/state/gh-flow/repo/404" ]
    # Worker should be gone (SIGTERM, 1s grace, SIGKILL).
    run kill -0 "$_victim" 2>/dev/null
    assert_failure
    wait "$_victim" 2>/dev/null || true
}

@test "prune <N>: accepts '#N' form (strips leading #)" {
    _seed_state 405 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow prune '#405'"
    assert_success
    [ ! -d "$HOME/.local/state/gh-flow/repo/405" ]
}

@test "prune <N>: rejects non-integer issue arg" {
    run_in_bash "cd '$REPO_DIR' && gh_flow prune abc 2>&1"
    assert_failure
    assert_output --partial "invalid issue number"
}

# ---------------------------------------------------------------------------
# per-issue status (issue #252)
# ---------------------------------------------------------------------------

@test "status <N>: prints header + Verdict + Next action" {
    _seed_state 501 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow status 501"
    assert_success
    assert_output --partial "gh-flow status #501"
    assert_output --partial "State"
    assert_output --partial "done"
    assert_output --partial "Verdict"
    assert_output --partial "Next action"
}

@test "status <N>: '#N' form also accepted" {
    _seed_state 502 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow status '#502'"
    assert_success
    assert_output --partial "#502"
}

@test "status <N>: missing state dir → warning, exits 0" {
    run_in_bash "cd '$REPO_DIR' && gh_flow status 503"
    assert_success
    assert_output --partial "no state for #503"
}

@test "status <N>: rejects multiple positional args" {
    run_in_bash "cd '$REPO_DIR' && gh_flow status 504 505 2>&1"
    assert_failure
    assert_output --partial "only one issue number"
}

@test "status <N>: OPEN PR with no decision shows 'Review: pending' (issue #501)" {
    _install_gh_stub "OPEN" ""
    _seed_state 510 "polling" "" "$$"
    printf '700\n' >"$HOME/.local/state/gh-flow/repo/510/pr.number"

    run_in_bash "cd '$REPO_DIR' && gh_flow status 510"
    assert_success
    assert_output --partial "PR"
    assert_output --partial "Review"
    assert_output --partial "pending"
}

@test "status <N>: OPEN PR with APPROVED decision shows 'Review: APPROVED' (issue #501)" {
    _install_gh_stub "OPEN" "APPROVED"
    _seed_state 511 "polling" "" "$$"
    printf '701\n' >"$HOME/.local/state/gh-flow/repo/511/pr.number"

    run_in_bash "cd '$REPO_DIR' && gh_flow status 511"
    assert_success
    assert_output --partial "Review"
    assert_output --partial "APPROVED"
}

@test "status <N>: MERGED PR omits the Review row (issue #501)" {
    # Review decision is irrelevant once the PR is merged — the row should
    # not appear so the status table stays terse for resolved PRs.
    _install_gh_stub "MERGED" ""
    _seed_state 512 "polling" "" "$$"
    printf '702\n' >"$HOME/.local/state/gh-flow/repo/512/pr.number"

    run_in_bash "cd '$REPO_DIR' && gh_flow status 512"
    assert_success
    assert_output --partial "MERGED"
    refute_output --partial "Review"
}

# ---------------------------------------------------------------------------
# pre-flight gh auth check (issue #378)
# ---------------------------------------------------------------------------

# Install a `gh` stub on PATH that controls only the `gh api` exit code.
# Other subcommands return 0 with no output so unrelated callers don't break.
# $1 = "ok" (auth valid) or "fail" (auth invalid → exit 1).
_install_gh_api_stub() {
    local _mode="${1:-ok}"
    mkdir -p "$TEST_TEMP_HOME/bin"
    if [ "$_mode" = "ok" ]; then
        cat >"$TEST_TEMP_HOME/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
    printf 'mockuser\n'
    exit 0
fi
exit 0
STUB
    else
        cat >"$TEST_TEMP_HOME/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
    printf 'gh api: token invalid\n' >&2
    exit 1
fi
exit 0
STUB
    fi
    chmod +x "$TEST_TEMP_HOME/bin/gh"
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
}

@test "pre-flight: _gh_flow_check_gh_auth returns 0 when gh api user succeeds" {
    _install_gh_api_stub ok
    run_in_bash "_gh_flow_check_gh_auth && echo OK || echo FAIL"
    assert_success
    assert_output --partial "OK"
}

@test "pre-flight: _gh_flow_check_gh_auth returns non-zero when gh api user fails" {
    _install_gh_api_stub fail
    run_in_bash "_gh_flow_check_gh_auth && echo OK || echo FAIL"
    assert_success
    assert_output --partial "FAIL"
}

@test "verdict: failed:precondition:gh-auth → re-auth Next action" {
    _seed_state 601 "failed:precondition:gh-auth" "" ""

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 601"
    assert_success
    assert_line --index 0 "precondition failed — gh auth invalid"
    assert_output --partial "gh auth login"
    assert_output --partial "gh-flow 601"
}

@test "verdict: failed:precondition:gh-auth distinct from generic failed:* dead-failure verdict" {
    # Same shape as 601 but a generic failed:implementing — must NOT collapse
    # into the precondition branch. Guards the case-statement ordering
    # (precondition entry must come before failed:* glob).
    _seed_state 602 "failed:implementing" "" ""

    run_in_bash "cd '$REPO_DIR' && _gh_flow_verdict 602"
    assert_success
    assert_output --partial "dead failure"
    refute_output --partial "precondition failed"
}

# Project-board sync helper tests live in
# tests/bats/functions/gh_project_status.bats.
