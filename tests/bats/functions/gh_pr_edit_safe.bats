#!/usr/bin/env bats
# tests/bats/functions/gh_pr_edit_safe.bats
# Unit tests for the _pr_edit_safe_label / _pr_edit_safe_body wrappers
# extracted as a fix for issue #326 (Bug B). The real `gh` binary is
# never invoked — a fake shim selected by FAKE_GH_MODE drives every
# code path:
#
#   ok                — gh pr edit succeeds, no fallback path taken
#   classic-deprec    — gh pr edit fails with the Projects(classic)
#                       deprecation warning on stderr → REST fallback runs
#   other-failure     — gh pr edit fails with an unrelated error → no
#                       REST fallback, error is forwarded to caller
#   resolve-repo      — `gh repo view --json nameWithOwner -q ...` echoes
#                       owner/repo for the repo-resolution path
#
# Network-dependent paths (the actual REST POST/PATCH) are not exercised
# directly — the fake shim only confirms the helper *picked the right
# command*, recorded via FAKE_GH_LOG. This matches how
# gh_project_status.bats covers its mutation helper.

load '../test_helper'

setup() {
    setup_isolated_home
    _setup_fake_gh
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fake `gh` shim. Selects behavior by FAKE_GH_MODE; every call appends a
# one-line trace to FAKE_GH_LOG so assertions can inspect what the helper
# actually invoked.
# ---------------------------------------------------------------------------
_setup_fake_gh() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    : > "$TEST_TEMP_HOME/gh.log"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Trace every invocation regardless of mode for assertion clarity.
echo "gh $*" >> "${FAKE_GH_LOG:-/dev/null}"

# `gh repo view --json nameWithOwner -q .nameWithOwner` is used by the
# repo-resolution fallback. Always succeed regardless of FAKE_GH_MODE.
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    echo "owner/repo"
    exit 0
fi

case "${FAKE_GH_MODE:-ok}" in
    ok)
        # gh pr edit / gh api both succeed silently.
        exit 0
        ;;
    classic-deprec)
        if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
            echo "GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience" >&2
            exit 1
        fi
        # gh api retry path succeeds.
        exit 0
        ;;
    classic-deprec-then-rest-fail)
        if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
            echo "GraphQL: Projects (classic) is being deprecated" >&2
            exit 1
        fi
        if [ "$1" = "api" ]; then
            echo "REST 500" >&2
            exit 22
        fi
        exit 0
        ;;
    other-failure)
        if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
            echo "HTTP 404: Not Found" >&2
            exit 1
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
GH
    chmod +x "$STUB_BIN/gh"
}

# Run a snippet through bash with the fake gh on PATH and dotfiles loaded.
_run_with_fake_gh() {
    local mode="$1" snippet="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_MODE='${mode}'
        export FAKE_GH_LOG='${TEST_TEMP_HOME}/gh.log'
        source '${DOTFILES_ROOT}/bash/main.bash'
        ${snippet}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helpers available in both bash and zsh after main.* sources them
# ---------------------------------------------------------------------------

@test "bash: _pr_edit_safe_label helper exists" {
    run_in_bash 'declare -f _pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _pr_edit_safe_body helper exists" {
    run_in_bash 'declare -f _pr_edit_safe_body >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _pr_edit_safe_label helper exists" {
    run_in_zsh 'typeset -f _pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _pr_edit_safe_body helper exists" {
    run_in_zsh 'typeset -f _pr_edit_safe_body >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Arg validation — must return early before touching gh
# ---------------------------------------------------------------------------

@test "label: missing args prints usage and returns 2" {
    run_in_bash '_pr_edit_safe_label 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "usage: _pr_edit_safe_label"
    assert_output --partial "rc=2"
}

@test "label: missing label arg returns 2 without calling gh" {
    _run_with_fake_gh ok '_pr_edit_safe_label 99'
    assert_output --partial "usage: _pr_edit_safe_label"
    assert_output --partial "rc=2"
    refute [ -s "$TEST_TEMP_HOME/gh.log" ]
}

@test "body: missing args prints usage and returns 2" {
    run_in_bash '_pr_edit_safe_body 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "usage: _pr_edit_safe_body"
    assert_output --partial "rc=2"
}

@test "body: unreadable body file rejected before any gh call" {
    _run_with_fake_gh ok '_pr_edit_safe_body 99 /nonexistent/file --repo owner/repo'
    assert_output --partial "body file not readable"
    assert_output --partial "rc=2"
    refute [ -s "$TEST_TEMP_HOME/gh.log" ]
}

@test "label: --repo without value returns 2" {
    _run_with_fake_gh ok '_pr_edit_safe_label 99 enhancement --repo'
    assert_output --partial "--repo requires an argument"
    assert_output --partial "rc=2"
}

# ---------------------------------------------------------------------------
# Happy path — gh pr edit succeeds, no REST fallback
# ---------------------------------------------------------------------------

@test "label: success path calls only gh pr edit, no REST" {
    _run_with_fake_gh ok '_pr_edit_safe_label 99 enhancement --repo owner/repo'
    assert_output --partial "rc=0"
    run bash -c "grep -c 'gh pr edit' '$TEST_TEMP_HOME/gh.log' || true"
    assert_output "1"
    run bash -c "grep -c 'gh api -X' '$TEST_TEMP_HOME/gh.log' || true"
    assert_output "0"
}

@test "body: success path calls only gh pr edit, no REST" {
    body_file="$TEST_TEMP_HOME/body.md"
    echo "## Hello" > "$body_file"
    _run_with_fake_gh ok "_pr_edit_safe_body 99 '$body_file' --repo owner/repo"
    assert_output --partial "rc=0"
    run bash -c "grep -c 'gh pr edit' '$TEST_TEMP_HOME/gh.log' || true"
    assert_output "1"
    run bash -c "grep -c 'gh api -X' '$TEST_TEMP_HOME/gh.log' || true"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Bug B regression — Projects(classic) deprecation triggers REST fallback
# ---------------------------------------------------------------------------

@test "label: classic-deprecation triggers REST fallback (#326 Bug B)" {
    _run_with_fake_gh classic-deprec '_pr_edit_safe_label 99 enhancement --repo owner/repo'
    assert_output --partial "Projects(classic) deprecation"
    assert_output --partial "rc=0"
    # Confirm both paths were tried in order: gh pr edit first, gh api second.
    run grep -c "gh pr edit" "$TEST_TEMP_HOME/gh.log"
    assert_success
    assert_output "1"
    run grep -E "gh api -X POST repos/owner/repo/issues/99/labels" "$TEST_TEMP_HOME/gh.log"
    assert_success
}

@test "body: classic-deprecation triggers REST fallback" {
    body_file="$TEST_TEMP_HOME/body.md"
    echo "Updated body content" > "$body_file"
    _run_with_fake_gh classic-deprec "_pr_edit_safe_body 99 '$body_file' --repo owner/repo"
    assert_output --partial "Projects(classic) deprecation"
    assert_output --partial "rc=0"
    run grep -E "gh api -X PATCH repos/owner/repo/pulls/99" "$TEST_TEMP_HOME/gh.log"
    assert_success
}

@test "label: REST fallback failure surfaces as non-zero rc" {
    _run_with_fake_gh classic-deprec-then-rest-fail '_pr_edit_safe_label 99 enhancement --repo owner/repo'
    refute_output --partial "rc=0"
    assert_output --partial "Projects(classic) deprecation"
}

# ---------------------------------------------------------------------------
# Non-deprecation failures must NOT trigger REST fallback
# ---------------------------------------------------------------------------

@test "label: unrelated gh failure forwards stderr and skips REST" {
    _run_with_fake_gh other-failure '_pr_edit_safe_label 99 enhancement --repo owner/repo'
    assert_output --partial "HTTP 404"
    refute_output --partial "Projects(classic) deprecation"
    refute_output --partial "rc=0"
    run bash -c "grep -c 'gh api -X' '$TEST_TEMP_HOME/gh.log' || true"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Repo resolution: --repo > $GH_REPO > gh repo view
# ---------------------------------------------------------------------------

@test "label: --repo flag wins over GH_REPO env" {
    _run_with_fake_gh ok 'GH_REPO=other/wrong _pr_edit_safe_label 99 enhancement --repo owner/repo'
    assert_output --partial "rc=0"
    run grep -E "gh pr edit 99 --repo owner/repo --add-label enhancement" "$TEST_TEMP_HOME/gh.log"
    assert_success
}

@test "label: GH_REPO env used when --repo absent" {
    _run_with_fake_gh ok 'GH_REPO=env/repo _pr_edit_safe_label 99 enhancement'
    assert_output --partial "rc=0"
    run grep -E "gh pr edit 99 --repo env/repo --add-label enhancement" "$TEST_TEMP_HOME/gh.log"
    assert_success
}

@test "label: falls back to gh repo view when neither --repo nor GH_REPO set" {
    _run_with_fake_gh ok 'unset GH_REPO; _pr_edit_safe_label 99 enhancement'
    assert_output --partial "rc=0"
    # Helper called `gh repo view ...` to resolve the repo.
    run grep -E "gh repo view" "$TEST_TEMP_HOME/gh.log"
    assert_success
}
