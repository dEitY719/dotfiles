#!/usr/bin/env bats
# tests/bats/functions/safe_source.bats
# Regression coverage for issue #1504 / PR #1543 review feedback:
#
# safe_source() originally redirected a sourced file's stderr to /dev/null
# unconditionally, which also swallowed WARN output written by a
# *successfully* sourced file (e.g. #1454's foreign-checkout guard) whenever
# it ran through the interactive loader path (bash/main.bash, zsh/main.zsh)
# instead of being sourced directly.
#
# The first fix captured stderr to a per-call mktemp file and replayed it
# conditionally on the exit code. agy + codex review on PR #1543 flagged that
# as a real startup-latency regression (one mktemp+rm subprocess pair per
# sourced file, dozens of times per shell start) and a stderr timing/ordering
# change. The current implementation instead decides the redirect target up
# front from the path pattern + DEBUG_DOTFILES alone — no buffering, no temp
# files, no timing change — so this suite is organized around that
# classification: "important" paths (functions/tools-integrations/env) always
# stream stderr live; ".local.sh" always redirects; any other path redirects
# unless DEBUG_DOTFILES=1. Both bash and zsh get success/failure/debug
# coverage per category (codex flagged the original zsh coverage as
# happy-path-only).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

_ss_snippet() {
    local target="$1" error_msg="$2" extra_env="${3-}"
    printf '%s\n' "
        export DOTFILES_FORCE_INIT=1
        ${extra_env}
        declare -gi SOURCED_FILES_COUNT=0 2>/dev/null || typeset -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${target}' '${error_msg}'
        printf 'exit=%s\n' \"\$?\"
        printf 'count=%s\n' \"\$SOURCED_FILES_COUNT\"
    "
}

run_ss_bash() { run bash --noprofile --norc -c "$(_ss_snippet "$1" "$2" "${3-}")"; }
run_ss_zsh() { run zsh -f -c "$(_ss_snippet "$1" "$2" "${3-}")"; }

# ---------------------------------------------------------------------------
# Missing file
# ---------------------------------------------------------------------------

@test "bash: a missing file is silently skipped (no stderr, counter unchanged)" {
    run_ss_bash "$TEST_TEMP_HOME/does-not-exist.sh" "msg"
    assert_success
    refute_output --partial "msg"
    assert_output --partial "count=0"
}

# ---------------------------------------------------------------------------
# Important category (*/functions/*, */tools/integrations/*, */env/*):
# never redirected — stderr always streams live, success or failure.
# ---------------------------------------------------------------------------

@test "bash: important-category file — success — stderr streams live" {
    local dir="$TEST_TEMP_HOME/functions" target
    mkdir -p "$dir"
    target="$dir/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_bash "$target" "should not error"
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "zsh: important-category file — success — stderr streams live" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local dir="$TEST_TEMP_HOME/functions" target
    mkdir -p "$dir"
    target="$dir/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_zsh "$target" "should not error"
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "bash: important-category file — failure — error message and its own stderr both shown" {
    local dir="$TEST_TEMP_HOME/functions" target
    mkdir -p "$dir"
    target="$dir/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_bash "$target" "load failed"
    assert_output --partial "load failed"
    assert_output --partial "boom detail"
    assert_output --partial "exit=1"
}

@test "zsh: important-category file — failure — error message and its own stderr both shown" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local dir="$TEST_TEMP_HOME/functions" target
    mkdir -p "$dir"
    target="$dir/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_zsh "$target" "load failed"
    assert_output --partial "load failed"
    assert_output --partial "boom detail"
    assert_output --partial "exit=1"
}

# This is the exact scenario issue #1504 reports: a file loaded through the
# real interactive loader path (functions/*, via safe_source) writes a WARN
# to stderr on success and it must now be visible, not just when the same
# file is sourced directly (already covered by
# tests/bats/functions/gh_pr_review.bats's #1454 zsh test).
@test "bash: gh_pr_review.sh's #1454 foreign-checkout WARN survives safe_source" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    local foreign_home="$TEST_TEMP_HOME/foreign-home"
    mkdir -p "$foreign_home/dotfiles"
    git -C "$foreign_home/dotfiles" init -q -b main
    git -C "$foreign_home/dotfiles" -c user.email=t@t -c user.name=t \
        commit --allow-empty -q -m init

    HOME="$foreign_home" run_ss_bash \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh" \
        "load failed"
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
}

# ---------------------------------------------------------------------------
# .local.sh: always redirected to /dev/null — success or failure, regardless
# of DEBUG_DOTFILES. Matches the pre-#1504 behavior exactly; never widened.
# ---------------------------------------------------------------------------

@test "bash: .local.sh — success — its own stderr stays silent" {
    local target="$TEST_TEMP_HOME/env.local.sh"
    printf '%s\n' 'echo "should stay hidden" >&2' >"$target"

    run_ss_bash "$target" "should not print"
    assert_success
    refute_output --partial "should stay hidden"
    assert_output --partial "count=1"
}

@test "bash: .local.sh — failure — stays fully silent, including its own stderr" {
    local target="$TEST_TEMP_HOME/env.local.sh"
    printf '%s\n' 'echo "should stay hidden" >&2; return 1' >"$target"

    run_ss_bash "$target" "should not print"
    assert_success
    refute_output --partial "should not print"
    refute_output --partial "should stay hidden"
}

@test "zsh: .local.sh — failure — stays fully silent, including its own stderr" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/env.local.sh"
    printf '%s\n' 'echo "should stay hidden" >&2; return 1' >"$target"

    run_ss_zsh "$target" "should not print"
    assert_success
    refute_output --partial "should not print"
    refute_output --partial "should stay hidden"
}

# ---------------------------------------------------------------------------
# Other category (anything not .local.sh / important): redirected unless
# DEBUG_DOTFILES=1 — the escape hatch issue #1504 itself proposed as an
# acceptable fallback when full universal coverage is too costly.
# ---------------------------------------------------------------------------

@test "bash: other-category file, DEBUG_DOTFILES unset — success — stderr stays silent" {
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_bash "$target" "should not print"
    assert_success
    refute_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "zsh: other-category file, DEBUG_DOTFILES unset — success — stderr stays silent" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_zsh "$target" "should not print"
    assert_success
    refute_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "bash: other-category file, DEBUG_DOTFILES unset — failure — stays fully silent" {
    local target="$TEST_TEMP_HOME/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_bash "$target" "should not print"
    refute_output --partial "should not print"
    refute_output --partial "boom detail"
}

@test "zsh: other-category file, DEBUG_DOTFILES unset — failure — stays fully silent" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_zsh "$target" "should not print"
    refute_output --partial "should not print"
    refute_output --partial "boom detail"
}

@test "bash: other-category file, DEBUG_DOTFILES=1 — success — stderr revealed" {
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_bash "$target" "should not print" "export DEBUG_DOTFILES=1"
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "zsh: other-category file, DEBUG_DOTFILES=1 — success — stderr revealed" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run_ss_zsh "$target" "should not print" "export DEBUG_DOTFILES=1"
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "bash: other-category file, DEBUG_DOTFILES=1 — failure — error message and stderr revealed" {
    local target="$TEST_TEMP_HOME/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_bash "$target" "load failed" "export DEBUG_DOTFILES=1"
    assert_output --partial "load failed"
    assert_output --partial "boom detail"
    assert_output --partial "exit=1"
}

@test "zsh: other-category file, DEBUG_DOTFILES=1 — failure — error message and stderr revealed" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run_ss_zsh "$target" "load failed" "export DEBUG_DOTFILES=1"
    assert_output --partial "load failed"
    assert_output --partial "boom detail"
    assert_output --partial "exit=1"
}
