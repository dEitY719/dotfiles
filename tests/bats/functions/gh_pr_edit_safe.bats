#!/usr/bin/env bats
# tests/bats/functions/gh_pr_edit_safe.bats
# Unit tests for _gh_pr_edit_safe_label / _gh_pr_edit_safe_body — the
# REST fallback wrappers that recover from `gh pr edit` GraphQL deprecation
# warnings on classic-Projects repos (issue #326).
#
# Network is never touched. A fake `gh` shim on PATH selects per-test
# behavior via FAKE_GH_MODE, mirroring the gh_project_status.bats pattern.

load '../test_helper'

setup() {
    setup_isolated_home
    _setup_fake_gh
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fake `gh` shim
#
# FAKE_GH_MODE controls behaviour of `gh pr edit` and `gh api`:
#   ok          — `gh pr edit` succeeds (no warning, no fallback needed)
#   deprecated  — `gh pr edit` prints deprecation warning + exit 1, then
#                 `gh api POST .../labels` succeeds
#   deprecated_body — same but for body PATCH path
#   missing_label — `gh pr edit` prints deprecation, then `gh label list`
#                   omits the label so REST fallback must be refused
#   other_error — `gh pr edit` exits 1 with an unrelated error (no
#                 deprecation marker → no fallback, error passed through)
#   rest_fail   — deprecation warning, then REST POST also fails
# A scratch log records every call for assertion: $TEST_TEMP_HOME/gh.log
# ---------------------------------------------------------------------------
_setup_fake_gh() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    GH_LOG="$TEST_TEMP_HOME/gh.log"
    : >"$GH_LOG"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Record the invocation for inspection.
{ printf 'gh'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } \
    >>"$GH_LOG"

mode="${FAKE_GH_MODE:-ok}"

# `gh repo view --json nameWithOwner --jq .nameWithOwner` — used by repo
# resolution. Keep it boring.
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    echo "fake/repo"
    exit 0
fi

# `gh label list ...` — return the labels the test expects to exist.
if [ "$1" = "label" ] && [ "$2" = "list" ]; then
    case "$mode" in
        missing_label) printf 'bug\nchore\n' ;;
        *)             printf 'bug\nchore\nfeat\nskill\n' ;;
    esac
    exit 0
fi

# `gh pr edit <N> --repo R --add-label L` or `--body-file F`
if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
    case "$mode" in
        ok)
            exit 0
            ;;
        deprecated|missing_label|rest_fail)
            echo "GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience" >&2
            exit 1
            ;;
        deprecated_body)
            # Body path uses a different mode marker so we can
            # assert different REST fallback (PATCH vs POST).
            echo "GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience" >&2
            exit 1
            ;;
        other_error)
            echo "Some other unrelated error" >&2
            exit 1
            ;;
    esac
fi

# `gh api -X POST .../labels` — REST fallback for labels
if [ "$1" = "api" ] && [ "$3" = "POST" ]; then
    case "$mode" in
        rest_fail) echo "REST POST failed" >&2; exit 1 ;;
        *)         exit 0 ;;
    esac
fi

# `gh api -X PATCH .../pulls/N --input -` — REST fallback for body
if [ "$1" = "api" ] && [ "$3" = "PATCH" ]; then
    # Drain stdin to keep the pipe quiet
    cat >/dev/null
    case "$mode" in
        rest_fail) echo "REST PATCH failed" >&2; exit 1 ;;
        *)         exit 0 ;;
    esac
fi

# Catch-all: success
exit 0
GH
    chmod +x "$STUB_BIN/gh"
}

# Run a snippet in bash with the shim on PATH and the helper sourced.
_run_helper() {
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
        export GH_LOG='${GH_LOG}'
        . '${DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh'
        ${snippet}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helpers exist after sourcing
# ---------------------------------------------------------------------------

@test "bash: _gh_pr_edit_safe_label exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                 declare -f _gh_pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_pr_edit_safe_body exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                 declare -f _gh_pr_edit_safe_body >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_pr_edit_safe_label exists" {
    run_in_zsh '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_edit_safe.sh"; \
                typeset -f _gh_pr_edit_safe_label >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "label: missing args returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage:"
}

@test "label: unknown option returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --bogus 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "unknown option: --bogus"
}

@test "label: --repo without arg returns 2" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --repo 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "--repo requires an argument"
}

@test "body: missing body-file returns 2" {
    _run_helper ok '_gh_pr_edit_safe_body 99 /nonexistent/path/abc.txt 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "body-file not found"
}

# ---------------------------------------------------------------------------
# Happy path: gh pr edit succeeds, no fallback
# ---------------------------------------------------------------------------

@test "label: ok mode — single gh pr edit call, no REST" {
    _run_helper ok '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=0"
    # Exactly one `pr edit`, zero `api ... POST`
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

@test "body: ok mode — single gh pr edit call, no REST" {
    _run_helper ok "
        BF=\$(mktemp); printf 'hi' > \"\$BF\"
        _gh_pr_edit_safe_body 99 \"\$BF\" --repo fake/repo
        rm -f \"\$BF\"
    "
    assert_output --partial "rc=0"
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*PATCH' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Fallback path: deprecation warning triggers REST
# ---------------------------------------------------------------------------

@test "label: deprecated mode — falls back to REST POST and succeeds" {
    _run_helper deprecated '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=0"
    # gh pr edit attempted, then label list (validation), then api POST
    run grep -c 'pr edit' "$GH_LOG"
    assert_output "1"
    run grep -c 'label list' "$GH_LOG"
    assert_output "1"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "1"
}

@test "body: deprecated mode — falls back to REST PATCH and succeeds" {
    _run_helper deprecated_body "
        BF=\$(mktemp); printf 'hello world' > \"\$BF\"
        _gh_pr_edit_safe_body 99 \"\$BF\" --repo fake/repo
        rm -f \"\$BF\"
    "
    assert_output --partial "rc=0"
    run grep -c 'api .*PATCH' "$GH_LOG"
    assert_output "1"
}

# ---------------------------------------------------------------------------
# Defensive guard: REST fallback must NOT auto-create labels.
# ---------------------------------------------------------------------------

@test "label: missing-label mode — refuses REST fallback (rc=3)" {
    _run_helper missing_label '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=3"
    assert_output --partial "refusing REST fallback (would auto-create)"
    # No POST should have been issued.
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Non-deprecation errors must NOT trigger fallback.
# ---------------------------------------------------------------------------

@test "label: other_error mode — passes error through (rc=1, no REST)" {
    _run_helper other_error '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "Some other unrelated error"
    run grep -c 'api .*POST' "$GH_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# REST fallback failure surfaces as rc=1
# ---------------------------------------------------------------------------

@test "label: rest_fail mode — REST POST failure surfaces as rc=1" {
    _run_helper rest_fail '_gh_pr_edit_safe_label 99 feat --repo fake/repo 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "REST POST failed"
}

# ---------------------------------------------------------------------------
# Self-check (#724) — "helper present but wrappers undefined" canary.
# Codex review on PR #725 flagged the gap: gh_pr_edit_safe.sh grew a
# multi-function self-check (verifies BOTH `_gh_pr_edit_safe_label` and
# `_gh_pr_edit_safe_body`) but there were no Bats cases proving (a) the
# warning stays silent on a healthy source and (b) it fires when either
# wrapper is undefined post-source.
# ---------------------------------------------------------------------------

@test "self-check (#724): healthy gh_pr_edit_safe source emits no BUG warning" {
    # Sanity: sourcing the real helper defines both wrappers; the tail
    # self-check should see both `command -v` checks succeed and stay
    # silent. Catches a future regression where the warning fires on
    # the happy path (false positive).
    run bash --noprofile --norc -c \
        ". \"${SHELL_COMMON}/functions/gh_pr_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "BUG: _gh_pr_edit_safe_"
}

@test "self-check (#724): regressed gh_pr_edit_safe (no wrappers) prints warning" {
    # Synthesize the failure mode #724 targets: future regression leaves
    # the file sourceable but neither wrapper gets defined. The tail
    # self-check MUST print a stderr warning while keeping rc 0 so
    # caller's `||` chains stay intact.
    cat >"$BATS_TEST_TMPDIR/regressed_edit_safe.sh" <<'STUB'
#!/bin/sh
# Simulate: future regression — both wrappers never get defined.
# Trailing self-check (copied verbatim from gh_pr_edit_safe.sh tail):
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/regressed_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_pr_edit_safe_{label,body} undefined after source"
}

@test "self-check (#724): partial wrappers (label only) still triggers warning" {
    # Multi-function check must catch the case where ONE wrapper is
    # defined but the other isn't (typo / partial sourcing). Defines
    # only `_gh_pr_edit_safe_label`; the `||` between the two
    # `command -v` clauses MUST fire on the missing `_body`.
    cat >"$BATS_TEST_TMPDIR/partial_edit_safe.sh" <<'STUB'
#!/bin/sh
# Define label wrapper only — body wrapper is missing.
_gh_pr_edit_safe_label() { return 0; }
# Trailing self-check (copied verbatim from gh_pr_edit_safe.sh tail):
if ! command -v _gh_pr_edit_safe_label >/dev/null 2>&1 \
    || ! command -v _gh_pr_edit_safe_body >/dev/null 2>&1; then
    printf '[gh_pr_edit_safe] BUG: _gh_pr_edit_safe_{label,body} undefined after source — PR edit safe-fallback will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/partial_edit_safe.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial \
        "BUG: _gh_pr_edit_safe_{label,body} undefined after source"
}
