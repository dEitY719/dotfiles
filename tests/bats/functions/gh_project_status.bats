#!/usr/bin/env bats
# tests/bats/functions/gh_project_status.bats
# Unit tests for the shared _gh_project_status_sync helper extracted from
# gh_flow.sh. Network-dependent paths (the actual GraphQL query + mutation)
# are not exercised — fixturing live projectV2 state is impractical. We
# cover loading, opt-out guards, arg validation, --only-from option
# parsing, and the _gh_project_status_in_list membership helper.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fake `gh` shim used by the _gh_pr_closing_issue_numbers cases below.
# Behaviour is selected by FAKE_GH_MODE so a single stub covers every case
# we need (#264): zero closing issues, one, many, and the GraphQL-failure
# path that proves the helper stays silent and returns 0.
# ---------------------------------------------------------------------------
_setup_fake_gh() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Only the `gh api graphql ... --jq <expr>` shape is exercised here.
case "${FAKE_GH_MODE:-zero}" in
    zero)  exit 0 ;;
    one)   echo 248 ; exit 0 ;;
    many)  printf '248\n239\n241\n' ; exit 0 ;;
    error) echo "graphql: Unknown JSON field" >&2 ; exit 1 ;;
    *)     exit 0 ;;
esac
GH
    chmod +x "$STUB_BIN/gh"
}

# Run _gh_pr_closing_issue_numbers in a bash subshell that has the fake gh
# on PATH and FAKE_GH_MODE set. We can't reuse run_in_bash because it does
# not forward PATH/env into the subshell.
_run_closing_issues_bash() {
    local mode="$1" args="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_MODE='${mode}'
        source '${DOTFILES_ROOT}/bash/main.bash'
        _gh_pr_closing_issue_numbers ${args}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helper available in both bash and zsh after main.* sources it
# ---------------------------------------------------------------------------

@test "bash: _gh_project_status_sync helper exists" {
    run_in_bash 'declare -f _gh_project_status_sync >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_project_status_sync helper exists" {
    run_in_zsh 'typeset -f _gh_project_status_sync >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_project_status_in_list helper exists" {
    run_in_bash 'declare -f _gh_project_status_in_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_project_status_mutate helper exists" {
    # Extracted in #244 so the mutation can be retried once on flake.
    run_in_bash 'declare -f _gh_project_status_mutate >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_project_status_mutate helper exists" {
    run_in_zsh 'typeset -f _gh_project_status_mutate >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_project_status_resolve_owner_repo helper exists" {
    # Extracted in #341 so the auto-detect step can be retried once on flake.
    run_in_bash 'declare -f _gh_project_status_resolve_owner_repo >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_project_status_resolve_owner_repo helper exists" {
    run_in_zsh 'typeset -f _gh_project_status_resolve_owner_repo >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Opt-out guards
# ---------------------------------------------------------------------------

@test "opt-out: GH_PROJECT_STATUS_SYNC=0 returns silently" {
    run_in_bash 'GH_PROJECT_STATUS_SYNC=0 _gh_project_status_sync issue 1 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

@test "opt-out: legacy GH_FLOW_PROJECT_STATUS_SYNC=0 still honored" {
    # Backwards-compat: callers that exported the old name in their env or
    # CI config keep working without churn.
    run_in_bash 'GH_FLOW_PROJECT_STATUS_SYNC=0 _gh_project_status_sync issue 1 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

# ---------------------------------------------------------------------------
# Arg validation (early returns, no network)
# ---------------------------------------------------------------------------

@test "validation: missing args returns silently" {
    run_in_bash '_gh_project_status_sync 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

@test "validation: invalid kind returns 0 with warning" {
    run_in_bash '_gh_project_status_sync bogus 42 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "invalid kind=bogus"
}

# ---------------------------------------------------------------------------
# --only-from option parsing
# ---------------------------------------------------------------------------

@test "only-from: unknown option rejected with stderr warning" {
    run_in_bash '_gh_project_status_sync issue 42 "In progress" --bogus 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "unknown option: --bogus"
}

@test "only-from: missing value rejected" {
    run_in_bash '_gh_project_status_sync issue 42 "In progress" --only-from 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "--only-from requires an argument"
}

# ---------------------------------------------------------------------------
# _gh_project_status_in_list membership semantics
# ---------------------------------------------------------------------------

@test "in_list: single-item match" {
    run_in_bash '_gh_project_status_in_list "Backlog" "Backlog" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: comma-separated match (first)" {
    run_in_bash '_gh_project_status_in_list "Backlog" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: comma-separated match (last)" {
    run_in_bash '_gh_project_status_in_list "In progress" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: no match returns 1" {
    run_in_bash '_gh_project_status_in_list "In review" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

@test "in_list: empty current value never matches" {
    # Important guard: items with no Status set should not satisfy
    # --only-from "" or any non-empty whitelist.
    run_in_bash '_gh_project_status_in_list "" "Backlog" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

@test "in_list: status names with internal spaces are preserved" {
    # Regression: a naive trim or word-split would break "In progress".
    run_in_bash '_gh_project_status_in_list "In progress" "In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

# ---------------------------------------------------------------------------
# _gh_pr_closing_issue_numbers — issue #264 (gh pr view --json missing field)
# ---------------------------------------------------------------------------

@test "bash: _gh_pr_closing_issue_numbers helper exists" {
    run_in_bash 'declare -f _gh_pr_closing_issue_numbers >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_pr_closing_issue_numbers helper exists" {
    run_in_zsh 'typeset -f _gh_pr_closing_issue_numbers >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "closing-issues: missing pr arg returns silently" {
    run_in_bash '_gh_pr_closing_issue_numbers "" "owner/repo" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
}

@test "closing-issues: missing repo arg returns silently" {
    run_in_bash '_gh_pr_closing_issue_numbers 99 "" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
}

@test "closing-issues: malformed repo without slash returns silently" {
    # Guards against feeding a bare project name to gh, which would surface
    # as a noisy GraphQL error in the merge report.
    run_in_bash '_gh_pr_closing_issue_numbers 99 "no-slash" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "248"
}

@test "closing-issues: zero closing issues prints nothing, rc=0" {
    _setup_fake_gh
    _run_closing_issues_bash zero '99 owner/repo'
    assert_success
    assert_output --partial "rc=0"
    refute_output --regexp '^[0-9]+$'
}

@test "closing-issues: one closing issue emits its number" {
    _setup_fake_gh
    _run_closing_issues_bash one '99 owner/repo'
    assert_success
    assert_output --partial "248"
    assert_output --partial "rc=0"
}

@test "closing-issues: multiple closing issues each on their own line" {
    _setup_fake_gh
    _run_closing_issues_bash many '99 owner/repo'
    assert_success
    assert_output --partial "248"
    assert_output --partial "239"
    assert_output --partial "241"
    assert_output --partial "rc=0"
}

@test "closing-issues: gh failure stays silent and returns 0" {
    # This is the regression for #264: when the graphql call (or the older
    # `gh pr view --json closingIssuesReferences` it replaces) errors out,
    # the helper must swallow the error so the merge report is not blocked.
    _setup_fake_gh
    _run_closing_issues_bash error '99 owner/repo'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "Unknown JSON field"
}

# ---------------------------------------------------------------------------
# _gh_project_status_resolve_owner_repo — issue #341 (auto-detect retry)
# ---------------------------------------------------------------------------
#
# A stateful fake `gh` covers the retry-on-flake path. The shim records each
# invocation in a counter file so a single bash subprocess sees deterministic
# pass/fail sequences, mirroring how a real graphql connection-reset would be
# observed by the helper (one transient failure followed by recovery).

_setup_fake_gh_repo_view() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    FAKE_GH_COUNTER="$TEST_TEMP_HOME/fake_gh_calls"
    mkdir -p "$STUB_BIN"
    : >"$FAKE_GH_COUNTER"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Only the `gh repo view --json owner,name --jq ...` shape used by
# _gh_project_status_resolve_owner_repo is exercised here.
COUNTER="${FAKE_GH_COUNTER:?FAKE_GH_COUNTER not set}"
n=$(wc -l <"$COUNTER" 2>/dev/null | tr -d ' ')
n=$((n + 1))
echo "$n" >>"$COUNTER"
case "${FAKE_GH_REPO_MODE:-ok}" in
    ok)            echo "owner reponame" ; exit 0 ;;
    empty)         exit 0 ;;
    error)         echo "graphql: connection reset" >&2 ; exit 1 ;;
    flake_then_ok) [ "$n" -ge 2 ] && { echo "owner reponame" ; exit 0 ; } ; exit 1 ;;
    flake_twice)   exit 1 ;;
    *)             exit 0 ;;
esac
GH
    chmod +x "$STUB_BIN/gh"
}

# Run a snippet in a bash subshell with fake gh on PATH and counter env wired.
# Mirrors _run_closing_issues_bash but exposes FAKE_GH_REPO_MODE +
# FAKE_GH_COUNTER and forwards the counter so cross-call state is visible.
_run_resolve_bash() {
    local mode="$1" snippet="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_REPO_MODE='${mode}'
        export FAKE_GH_COUNTER='${FAKE_GH_COUNTER}'
        export _GH_PROJECT_STATUS_RETRY_SLEEP=0
        source '${DOTFILES_ROOT}/bash/main.bash'
        ${snippet}
    "
}

@test "resolve: prints owner repo on success" {
    _setup_fake_gh_repo_view
    _run_resolve_bash ok '_gh_project_status_resolve_owner_repo; echo "rc=$?"'
    assert_success
    assert_output --partial "owner reponame"
    assert_output --partial "rc=0"
}

@test "resolve: empty gh output returns failure" {
    _setup_fake_gh_repo_view
    _run_resolve_bash empty '_gh_project_status_resolve_owner_repo; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=1"
}

@test "resolve: gh non-zero exit returns failure" {
    _setup_fake_gh_repo_view
    _run_resolve_bash error '_gh_project_status_resolve_owner_repo 2>/dev/null; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=1"
}

@test "sync auto-detect: retries once and recovers on transient failure" {
    # Regression for #341 — first `gh repo view` fails (simulated socket
    # reset), second succeeds. With the retry in place the helper should
    # proceed past auto-detect into the graphql query stage; that stage
    # is faked to return zero records so the sync exits with the
    # "not in any project" branch (proves we got past auto-detect).
    _setup_fake_gh_repo_view
    _run_resolve_bash flake_then_ok '_gh_project_status_sync issue 42 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "could not determine owner/repo"
    # Counter records each gh invocation: 2 for repo view (fail+ok) plus 1
    # for the graphql query that fakes back empty.
    run cat "$FAKE_GH_COUNTER"
    [ "${#lines[@]}" -ge 2 ]
}

@test "sync auto-detect: stays fail-quiet when both attempts fail" {
    _setup_fake_gh_repo_view
    _run_resolve_bash flake_twice '_gh_project_status_sync issue 42 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "could not determine owner/repo, skipping"
    # Counter must show exactly 2 invocations — one initial, one retry.
    run cat "$FAKE_GH_COUNTER"
    [ "${#lines[@]}" -eq 2 ]
}
