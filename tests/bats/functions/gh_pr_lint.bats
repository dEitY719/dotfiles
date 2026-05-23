#!/usr/bin/env bats
# tests/bats/functions/gh_pr_lint.bats
# Unit tests for _gh_pr_lint_run — the optional pre-push lint guard
# documented in claude/skills/gh-pr/references/lint-guard.md and exercised
# from gh:pr Step 4.5 (issue #396).
#
# Network is never touched. Lint tools (tox, shellcheck, actionlint,
# pre-commit) are stubbed via PATH shims that record their invocation in
# $TOOL_LOG and honour FAKE_<TOOL>_RC for failure simulation.
#
# Each test runs inside an ephemeral git repo with a `main` base branch and
# a feature branch carrying the test's changed files, so the helper's
# `git diff --name-only main...HEAD` query returns the expected list.

load '../test_helper'

setup() {
    setup_isolated_home
    _init_test_repo
    _setup_stub_bin
}

teardown() {
    teardown_isolated_home
    unset FAKE_TOX_RC FAKE_SHELLCHECK_RC FAKE_ACTIONLINT_RC FAKE_PRECOMMIT_RC
    unset GH_PR_LINT_BYPASS GH_PR_LINT_TOOLS
}

# ---------------------------------------------------------------------------
# Per-test git scratch repo:
#   main:    initial empty commit
#   feature: HEAD — caller adds changed files here
# Caller chdirs into REPO_DIR before running _gh_pr_lint_run.
# ---------------------------------------------------------------------------
_init_test_repo() {
    REPO_DIR="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO_DIR"
    (
        cd "$REPO_DIR" || exit 1
        git init -q -b main
        git config user.email "test@example.invalid"
        git config user.name "bats"
        : >.gitkeep
        git add .gitkeep
        git commit -q -m "initial"
        git checkout -q -b feature
    )
}

# Commit one or more files to the feature branch.
#   _stage_changes path:contents [path:contents ...]
# If <path> already exists, its contents are preserved (the test wrote
# them directly) — only the staging+commit happens. Otherwise the body
# is written to <path>. Empty body is allowed.
_stage_changes() {
    (
        cd "$REPO_DIR" || exit 1
        for spec in "$@"; do
            local path="${spec%%:*}"
            local body="${spec#*:}"
            mkdir -p "$(dirname "$path")"
            if [ ! -f "$path" ]; then
                printf '%s\n' "$body" >"$path"
            fi
            git add "$path"
        done
        git commit -q -m "feature changes"
    )
}

# ---------------------------------------------------------------------------
# Stub binaries — tox/shellcheck/actionlint/pre-commit. Each records its
# argv to $TOOL_LOG (one line per call, format: `<tool> [arg1] [arg2] ...`)
# and returns FAKE_<TOOL>_RC (default 0).
#
# Implementation note: the shim template uses a single-quoted heredoc so
# that bash history expansion never touches `!` in `#!/usr/bin/env bash`
# or in `${var:-default}`. Per-shim values are substituted via sed.
#
# Tests opt in by adding $STUB_BIN to PATH; tests for "no tools detected"
# simply skip the addition.
# ---------------------------------------------------------------------------
_setup_stub_bin() {
    STUB_BIN="$TEST_TEMP_HOME/stub-bin"
    TOOL_LOG="$TEST_TEMP_HOME/tool.log"
    mkdir -p "$STUB_BIN"
    : >"$TOOL_LOG"

    for tool in tox shellcheck actionlint pre-commit; do
        local rc_var
        rc_var="FAKE_$(printf '%s' "$tool" | tr 'a-z-' 'A-Z_')_RC"
        cat >"$STUB_BIN/$tool" <<'STUB'
#!/usr/bin/env bash
{
    printf '%s' '__TOOL__'
    for a in "$@"; do printf ' [%s]' "$a"; done
    printf '\n'
} >> '__LOG__'
exit "${__RC_VAR__:-0}"
STUB
        # POSIX `sed > tmp && mv tmp` instead of `sed -i` so the test
        # is portable to BSD sed (macOS) without the `-i ''` quirk.
        sed \
            -e "s|__TOOL__|$tool|" \
            -e "s|__LOG__|$TOOL_LOG|" \
            -e "s|__RC_VAR__|$rc_var|" \
            "$STUB_BIN/$tool" > "$STUB_BIN/$tool.tmp" \
            && mv "$STUB_BIN/$tool.tmp" "$STUB_BIN/$tool"
        chmod +x "$STUB_BIN/$tool"
    done
}

# Run a snippet in bash with the helper sourced and PATH controlled.
#   _run_helper <path-mode> <snippet>
# path-mode:
#   stubs   — STUB_BIN prepended to PATH (tools resolvable)
#   no-stubs — STUB_BIN NOT on PATH (simulates "tool absent")
_run_helper() {
    local mode="$1" snippet="$2"
    local extra_path=""
    if [ "$mode" = "stubs" ]; then
        extra_path="${STUB_BIN}:"
    fi
    # Pass GH_PR_LINT_BYPASS / GH_PR_LINT_TOOLS through ONLY when the
    # parent test set them (non-empty). Empty `GH_PR_LINT_TOOLS=''` now
    # has explicit "no tools match" semantics, so accidental empty
    # exports would mask intended detection.
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${extra_path}/usr/local/bin:/usr/bin:/bin'
        export FAKE_TOX_RC='${FAKE_TOX_RC:-0}'
        export FAKE_SHELLCHECK_RC='${FAKE_SHELLCHECK_RC:-0}'
        export FAKE_ACTIONLINT_RC='${FAKE_ACTIONLINT_RC:-0}'
        export FAKE_PRE_COMMIT_RC='${FAKE_PRECOMMIT_RC:-0}'
        ${GH_PR_LINT_BYPASS:+export GH_PR_LINT_BYPASS='${GH_PR_LINT_BYPASS}'}
        ${GH_PR_LINT_TOOLS:+export GH_PR_LINT_TOOLS='${GH_PR_LINT_TOOLS}'}
        cd '${REPO_DIR}' || exit 99
        . '${DOTFILES_ROOT}/shell-common/functions/gh_pr_lint.sh'
        ${snippet}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helper exists in bash and zsh
# ---------------------------------------------------------------------------

@test "bash: _gh_pr_lint_run exists after sourcing" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_lint.sh"; \
                 declare -f _gh_pr_lint_run >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_pr_lint_run exists after sourcing" {
    run_in_zsh '. "$DOTFILES_ROOT/shell-common/functions/gh_pr_lint.sh"; \
                typeset -f _gh_pr_lint_run >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "missing base-branch arg returns 2" {
    _run_helper no-stubs '_gh_pr_lint_run 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage:"
}

# ---------------------------------------------------------------------------
# Case 1 — tox.ini detected → tox runs, individual fallbacks suppressed
# ---------------------------------------------------------------------------

@test "tox.ini detected → tox runs with declared envs, fallbacks skipped" {
    cat >"$REPO_DIR/tox.ini" <<'TOX'
[testenv:ruff]
[testenv:shellcheck]
TOX
    _stage_changes "tox.ini:added" "foo.sh:#!/bin/sh"
    _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "running tox -e ruff,shellcheck"
    assert_output --partial "tox passed"
    # tox invoked exactly once with the right env list (bracket-format log)
    run grep -cF '[-e] [ruff,shellcheck]' "$TOOL_LOG"
    assert_output "1"
    # When tox runs, the shellcheck fallback must stay silent.
    run grep -c '^shellcheck' "$TOOL_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Case 2 — no tox, shellcheck detected → shellcheck runs on changed *.sh only
# ---------------------------------------------------------------------------

@test "shellcheck detected → runs only on changed .sh files" {
    _stage_changes "foo.sh:echo hi" "bar.sh:echo bye" "README.md:doc"
    _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "running shellcheck on 2 file(s)"
    assert_output --partial "shellcheck passed"
    # The lint tool was invoked once with -x -S warning + both .sh files.
    run grep -cF '[-x] [-S] [warning]' "$TOOL_LOG"
    assert_output "1"
    run grep -cF '[bar.sh]' "$TOOL_LOG"
    assert_output "1"
    run grep -cF '[foo.sh]' "$TOOL_LOG"
    assert_output "1"
    # README.md must NOT appear in the shellcheck call
    run grep -c 'README.md' "$TOOL_LOG"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Case 3 — no lint tools detected → skip with informative log
# ---------------------------------------------------------------------------

@test "no tools detected → skip with log" {
    _stage_changes "README.md:no shell scripts here"
    _run_helper no-stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "no lint tools detected — skip"
}

# ---------------------------------------------------------------------------
# Case 4 — GH_PR_LINT_BYPASS=1 → bypass all detection, return 0
# ---------------------------------------------------------------------------

@test "GH_PR_LINT_BYPASS=1 → guard skipped entirely (no tool calls)" {
    cat >"$REPO_DIR/tox.ini" <<'TOX'
[testenv:ruff]
TOX
    _stage_changes "tox.ini:added" "foo.sh:echo hi"
    GH_PR_LINT_BYPASS=1 _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "bypassed (GH_PR_LINT_BYPASS=1)"
    # No tool was invoked
    run wc -l <"$TOOL_LOG"
    assert_output --partial "0"
}

# ---------------------------------------------------------------------------
# Case 5 — empty changed-file set → skip without invoking any tool
# ---------------------------------------------------------------------------

@test "no changed files vs base → skip" {
    # feature branch has no commits beyond main
    _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "no changed files vs main — skip"
    run wc -l <"$TOOL_LOG"
    assert_output --partial "0"
}

# ---------------------------------------------------------------------------
# Empty-string semantics for GH_PR_LINT_TOOLS — the soft-disable knob
# documented in lint-guard.md. Distinguishes empty (no tools) from unset
# (auto). Regression for PR #411 review.
# ---------------------------------------------------------------------------

@test "GH_PR_LINT_TOOLS='' → soft-disables all tools (no tool calls)" {
    _stage_changes "foo.sh:echo hi"
    GH_PR_LINT_TOOLS="" _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=0"
    assert_output --partial "no lint tools detected — skip"
    run wc -l <"$TOOL_LOG"
    assert_output --partial "0"
}

# ---------------------------------------------------------------------------
# Bonus: lint failure → rc=1 with bypass guidance (covers the hard-fail path)
# ---------------------------------------------------------------------------

@test "shellcheck failure → rc=1 + bypass guidance" {
    _stage_changes "foo.sh:echo hi"
    FAKE_SHELLCHECK_RC=1 _run_helper stubs '_gh_pr_lint_run main 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "shellcheck FAILED"
    assert_output --partial "GH_PR_LINT_BYPASS=1"
}

# ---------------------------------------------------------------------------
# Self-check (#724) — "helper present but function undefined" canary.
# Codex review on PR #725 flagged the gap: gh_pr_lint.sh grew the same
# trailing self-check as gh_project_status.sh, but there were no Bats
# cases proving (a) the warning stays silent on a healthy source and
# (b) it fires when `_gh_pr_lint_run` is undefined post-source.
# ---------------------------------------------------------------------------

@test "self-check (#724): healthy gh_pr_lint source emits no BUG warning" {
    # Sanity: sourcing the real helper defines `_gh_pr_lint_run`.
    # The tail self-check should see `command -v` succeed and stay
    # silent — guards against a false-positive warning on the happy
    # path.
    run bash --noprofile --norc -c \
        ". \"${SHELL_COMMON}/functions/gh_pr_lint.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "BUG: _gh_pr_lint_run undefined"
}

@test "self-check (#724): regressed gh_pr_lint helper triggers stderr warning" {
    # Synthesize the failure mode #724 targets: future regression (typo,
    # rename, interactive-guard early-return) leaves the file sourceable
    # but `_gh_pr_lint_run` undefined. The tail self-check MUST print a
    # stderr warning while keeping rc 0 so caller's `||` chains stay
    # intact.
    cat >"$BATS_TEST_TMPDIR/regressed_lint.sh" <<'STUB'
#!/bin/sh
# Simulate: future regression — _gh_pr_lint_run never gets defined.
# Trailing self-check (copied verbatim from gh_pr_lint.sh tail):
if ! command -v _gh_pr_lint_run >/dev/null 2>&1; then
    printf '[gh_pr_lint] BUG: _gh_pr_lint_run undefined after source — pre-push lint will silently no-op. See dotfiles #724.\n' >&2
fi
:
STUB
    run bash --noprofile --norc -c \
        ". \"$BATS_TEST_TMPDIR/regressed_lint.sh\" 2>&1; echo \"rc=\$?\""
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "BUG: _gh_pr_lint_run undefined after source"
}
