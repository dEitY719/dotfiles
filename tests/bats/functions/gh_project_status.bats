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

# ---------------------------------------------------------------------------
# Verify pair + Approved fail-closed guard — issue #393
# ---------------------------------------------------------------------------
#
# These cases drive the full `_gh_project_status_sync` path (auto-detect →
# discovery query → mutate → verify) plus the Approved guard branch.
#
# The fake `gh` here multiplexes four call shapes by inspecting argv:
#   1. `gh pr view <num> --json reviewDecision --jq ...` → echoes
#      $FAKE_REVIEW_DECISION (default APPROVED). Exits 1 when
#      $FAKE_REVIEW_FAIL=1 to model a network/permission failure.
#   2. `gh repo view --json owner,name --jq ...` → echoes "owner reponame".
#   3. `gh api graphql ... query: mutation(...)` → mutation. Outcome (ok/fail)
#      driven by $FAKE_MUTATE_SEQUENCE (pipe-separated, defaults to all-ok).
#   4. `gh api graphql ... query: query(...) options(names:` → discovery
#      query; emits one synthetic record so the sync loop iterates once.
#   5. `gh api graphql ... query: query(...) fieldValueByName` (no options)
#      → verify-current query; emits the next entry of
#      $FAKE_VERIFY_SEQUENCE (pipe-separated; missing entries → empty).
#
# All call shapes append a tag to $FAKE_GH_LOG for assertions.

_setup_fake_gh_full() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    FAKE_GH_LOG="$TEST_TEMP_HOME/fake_gh_log"
    FAKE_MUTATE_IDX="$TEST_TEMP_HOME/fake_mutate_idx"
    FAKE_VERIFY_IDX="$TEST_TEMP_HOME/fake_verify_idx"
    mkdir -p "$STUB_BIN"
    : >"$FAKE_GH_LOG"
    echo 0 >"$FAKE_MUTATE_IDX"
    echo 0 >"$FAKE_VERIFY_IDX"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Multiplexed fake gh — see _setup_fake_gh_full comment in bats file.
LOG="${FAKE_GH_LOG:?FAKE_GH_LOG not set}"

case "$1 $2" in
    "pr view")
        echo "pr-view" >>"$LOG"
        if [ "${FAKE_REVIEW_FAIL:-0}" = "1" ]; then
            exit 1
        fi
        # gh's --jq applies a default when reviewDecision is null. The helper
        # uses `// "REVIEW_REQUIRED"`; we emit the raw decision here and let
        # the helper's jq do the substitution.
        echo "${FAKE_REVIEW_DECISION:-APPROVED}"
        exit 0
        ;;
    "repo view")
        echo "repo-view" >>"$LOG"
        echo "owner reponame"
        exit 0
        ;;
    "api graphql")
        # Inspect the rest of argv to tell mutation / discovery / verify apart.
        # The query body is passed as the value following `-f query=`.
        all_args="$*"
        if [[ "$all_args" == *"mutation("* ]]; then
            echo "mutate" >>"$LOG"
            idx=$(cat "$FAKE_MUTATE_IDX")
            idx=$((idx + 1))
            echo "$idx" >"$FAKE_MUTATE_IDX"
            # Pipe-separated outcomes: ok|fail|ok ...; missing entries default ok.
            IFS='|' read -ra out <<<"${FAKE_MUTATE_SEQUENCE:-ok}"
            slot="${out[$((idx - 1))]:-ok}"
            if [ "$slot" = "fail" ]; then
                echo "graphql: mutation failed" >&2
                exit 1
            fi
            exit 0
        elif [[ "$all_args" == *"options(names:"* ]]; then
            echo "discover" >>"$LOG"
            # One synthetic project item with empty current Status. Fields are
            # joined with `|` to match the helper's --jq output shape:
            #   project.id | item.id | field.id | option.id | current_status
            echo "proj1|item1|field1|opt1|"
            exit 0
        elif [[ "$all_args" == *"fieldValueByName"* ]]; then
            echo "verify" >>"$LOG"
            idx=$(cat "$FAKE_VERIFY_IDX")
            idx=$((idx + 1))
            echo "$idx" >"$FAKE_VERIFY_IDX"
            IFS='|' read -ra seq <<<"${FAKE_VERIFY_SEQUENCE:-}"
            val="${seq[$((idx - 1))]:-}"
            [ -n "$val" ] && echo "$val"
            exit 0
        else
            echo "graphql-other" >>"$LOG"
            exit 0
        fi
        ;;
esac
exit 0
GH
    chmod +x "$STUB_BIN/gh"
}

# Run an arbitrary snippet in bash with the full fake gh on PATH.
# All sleep knobs default to 0 so tests don't pause.
_run_full_bash() {
    local snippet="$1"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_LOG='${FAKE_GH_LOG}'
        export FAKE_MUTATE_IDX='${FAKE_MUTATE_IDX}'
        export FAKE_VERIFY_IDX='${FAKE_VERIFY_IDX}'
        export FAKE_REVIEW_DECISION='${FAKE_REVIEW_DECISION:-APPROVED}'
        export FAKE_REVIEW_FAIL='${FAKE_REVIEW_FAIL:-0}'
        export FAKE_MUTATE_SEQUENCE='${FAKE_MUTATE_SEQUENCE:-}'
        export FAKE_VERIFY_SEQUENCE='${FAKE_VERIFY_SEQUENCE:-}'
        export _GH_PROJECT_STATUS_RETRY_SLEEP=0
        export _GH_PROJECT_STATUS_VERIFY_SLEEP=0
        export _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS='${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS:-0}'
        source '${DOTFILES_ROOT}/bash/main.bash'
        ${snippet}
    "
}

@test "bash: _gh_project_status_query_current helper exists" {
    run_in_bash 'declare -f _gh_project_status_query_current >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_project_status_query_current helper exists" {
    run_in_zsh 'typeset -f _gh_project_status_query_current >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_project_status_set_and_verify helper exists" {
    run_in_bash 'declare -f _gh_project_status_set_and_verify >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ------- verify pair -------------------------------------------------------

@test "verify: happy path — single mutation, '(verified)' log" {
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="In review" \
        _run_full_bash '_gh_project_status_sync pr 42 "In review" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial '-> "In review" (verified)'
    refute_output --partial "(after 1 retry)"
    refute_output --partial "(verified after re-set)"
    refute_output --partial "ERROR"
    # Exactly one mutation, one verify call.
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 1 ]
    [ "$(grep -c '^verify$' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "verify: race revert — re-set + second verify, '(verified after re-set)'" {
    # First verify reads the builtin's overwrite ("In progress"); re-set
    # mutation lands; second verify reads the target. Two mutations total.
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="In progress|In review" \
        _run_full_bash '_gh_project_status_sync pr 42 "In review" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial 'reverted to "In progress", re-setting'
    assert_output --partial '(verified after re-set)'
    refute_output --partial "ERROR"
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 2 ]
    [ "$(grep -c '^verify$' "$FAKE_GH_LOG")" -eq 2 ]
}

@test "verify: persistent revert — fail loud after 2 verifies, return 0" {
    # Both verifies disagree with the target. Helper logs ERROR but still
    # returns 0 — best-effort policy preserved.
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="In progress|In progress" \
        _run_full_bash '_gh_project_status_sync pr 42 "In review" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial 'reverted to "In progress", re-setting'
    assert_output --partial 'ERROR: pr #42 verify failed twice'
    assert_output --partial 'target="In review"'
    assert_output --partial 'actual="In progress"'
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 2 ]
    [ "$(grep -c '^verify$' "$FAKE_GH_LOG")" -eq 2 ]
}

@test "verify: mutation flake then recovery — '(verified after 1 retry)'" {
    # First mutation 500s, retry succeeds, verify matches. Two mutations
    # plus one verify call.
    _setup_fake_gh_full
    FAKE_MUTATE_SEQUENCE="fail|ok" \
    FAKE_VERIFY_SEQUENCE="In review" \
        _run_full_bash '_gh_project_status_sync pr 42 "In review" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial '(verified after 1 retry)'
    refute_output --partial "ERROR"
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 2 ]
    [ "$(grep -c '^verify$' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "verify: VERIFY_SLEEP override is honored (no pause in tests)" {
    # Sanity check: when _GH_PROJECT_STATUS_VERIFY_SLEEP=0 the helper still
    # runs the verify call (otherwise the rest of the suite would be lying
    # about coverage). Time the call — must finish well under 1 second.
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="In review" \
        _run_full_bash '
            t0=$(date +%s)
            _gh_project_status_sync pr 42 "In review" >/dev/null 2>&1
            t1=$(date +%s)
            echo "elapsed=$((t1 - t0))"
        '
    assert_success
    assert_output --partial "elapsed=0"
    [ "$(grep -c '^verify$' "$FAKE_GH_LOG")" -eq 1 ]
}

# ------- Approved fail-closed guard ----------------------------------------

@test "guard: target=Approved + decision=APPROVED → mutation runs" {
    _setup_fake_gh_full
    FAKE_REVIEW_DECISION="APPROVED" \
    FAKE_VERIFY_SEQUENCE="Approved" \
        _run_full_bash '_gh_project_status_sync pr 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial '-> "Approved" (verified)'
    refute_output --partial "refusing"
    [ "$(grep -c '^pr-view$' "$FAKE_GH_LOG")" -eq 1 ]
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "guard: target=Approved + decision=REVIEW_REQUIRED → exit 2, no mutation" {
    _setup_fake_gh_full
    FAKE_REVIEW_DECISION="REVIEW_REQUIRED" \
        _run_full_bash '_gh_project_status_sync pr 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial 'refusing PR #42 -> "Approved": reviewDecision=REVIEW_REQUIRED'
    assert_output --partial "_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1"
    [ "$(grep -c '^pr-view$' "$FAKE_GH_LOG")" -eq 1 ]
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 0 ]
    [ "$(grep -c '^discover$' "$FAKE_GH_LOG")" -eq 0 ]
}

@test "guard: target=Approved + decision=CHANGES_REQUESTED → exit 2, no mutation" {
    _setup_fake_gh_full
    FAKE_REVIEW_DECISION="CHANGES_REQUESTED" \
        _run_full_bash '_gh_project_status_sync pr 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial 'reviewDecision=CHANGES_REQUESTED'
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 0 ]
}

@test "guard: target=Approved + gh pr view fails → UNKNOWN → exit 2" {
    # Safe default: when gh can't tell us the decision, refuse rather than
    # risk an incorrect mutation.
    _setup_fake_gh_full
    FAKE_REVIEW_FAIL=1 \
        _run_full_bash '_gh_project_status_sync pr 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial 'reviewDecision=UNKNOWN'
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 0 ]
}

@test "guard: target=Approved + bypass=1 → guard skipped, mutation runs" {
    _setup_fake_gh_full
    FAKE_REVIEW_DECISION="REVIEW_REQUIRED" \
    FAKE_VERIFY_SEQUENCE="Approved" \
    _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
        _run_full_bash '_gh_project_status_sync pr 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial '-> "Approved" (verified)'
    refute_output --partial "refusing"
    # gh pr view must NOT have been called when bypass is on.
    [ "$(grep -c '^pr-view$' "$FAKE_GH_LOG")" -eq 0 ]
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "guard: target=In review → guard does not fire (no pr-view call)" {
    # The guard only inspects "Approved". Other targets must skip the
    # gh pr view round-trip entirely.
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="In review" \
        _run_full_bash '_gh_project_status_sync pr 42 "In review" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    [ "$(grep -c '^pr-view$' "$FAKE_GH_LOG")" -eq 0 ]
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "guard: kind=issue + target=Approved → guard does not fire" {
    # Guard is PR-only — issues never have a reviewDecision.
    _setup_fake_gh_full
    FAKE_VERIFY_SEQUENCE="Approved" \
        _run_full_bash '_gh_project_status_sync issue 42 "Approved" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    [ "$(grep -c '^pr-view$' "$FAKE_GH_LOG")" -eq 0 ]
    [ "$(grep -c '^mutate$' "$FAKE_GH_LOG")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Self-check (#724) — "helper present but function undefined" canary
# ---------------------------------------------------------------------------

@test "self-check (#724): healthy source emits no BUG warning to stderr" {
    # Sanity: the real helper defines `_gh_project_status_sync`. The
    # tail-of-file self-check should see `command -v` succeed and stay
    # silent. Catches future regressions where the warning fires on
    # the happy path (false positive).
    run bash --noprofile --norc -c \
        ". \"${SHELL_COMMON}/functions/gh_project_status.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "BUG: _gh_project_status_sync undefined"
}

@test "self-check (#724): typo'd/missing function still triggers stderr warning" {
    # Synthesize the failure mode that #724 documents: a helper file
    # whose top-level guards / typos / partial sourcing prevent the
    # canonical function from ever getting defined. The self-check
    # snippet (mirroring the trailer in gh_project_status.sh) MUST
    # print a stderr warning and the file MUST still return rc 0 so
    # callers' `|| true` chains stay intact.
    cat >"$BATS_TEST_TMPDIR/regressed_helper.sh" <<'STUB'
#!/bin/sh
# Simulate: future regression — function definition removed/renamed.
# Trailing self-check (copied verbatim from gh_project_status.sh tail):
if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
    printf '[gh_project_status] BUG: _gh_project_status_sync undefined after source — board sync will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/regressed_helper.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_project_status_sync undefined after source"
}
