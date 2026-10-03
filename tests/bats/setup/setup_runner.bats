#!/usr/bin/env bats
# tests/bats/setup/setup_runner.bats
# Coverage for the root ./setup.sh step runner (run_step / _setup_summary /
# _setup_resolve_choice). setup.sh only calls main() when executed, so these
# tests source it and drive run_step against stub scripts — the real
# sub-scripts and the real $HOME are never touched.

load '../test_helper'

ROOT_SETUP="${_BATS_REAL_DOTFILES_ROOT}/setup.sh"

setup() {
    setup_isolated_home
    STUBS="$(mktemp -d)"
    for s in ok ok2; do
        printf '#!/bin/sh\necho "%s ran" >>"%s/ran"\necho noisy detail\n' "$s" "$STUBS" >"$STUBS/$s.sh"
    done
    printf '#!/bin/sh\necho "bad ran" >>"%s/ran"\necho boom-detail\nexit 3\n' "$STUBS" >"$STUBS/bad.sh"
    printf '#!/bin/sh\necho "⚠️  경고: fix me with X"\necho fine\n' >"$STUBS/warn.sh"
    chmod +x "$STUBS"/*.sh
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUBS"
}

# Run a snippet with setup.sh sourced and summary-mode capture enabled.
_runner() {
    run bash -c "set -e; source '$ROOT_SETUP'; SETUP_LOG='$STUBS/log'; _STEP_OUT='$STUBS/step'; $1"
}

@test "runner: successful step prints exactly one success line, detail stays in log" {
    _runner "run_step first critical '$STUBS/ok.sh'"
    assert_success
    assert_equal "${#lines[@]}" 1
    assert_output --regexp '^✅ first \([0-9]+\.[0-9]s\)$'
    grep -q "noisy detail" "$STUBS/log"
}

@test "runner: critical failure stops immediately; later steps never run" {
    _runner "run_step a critical '$STUBS/ok.sh'; run_step b critical '$STUBS/bad.sh'; run_step c critical '$STUBS/ok2.sh'"
    assert_failure 1
    assert_output --partial "b 실패 [critical] (exit 3"
    assert_output --partial "boom-detail"
    assert_output --partial "bash -x $STUBS/bad.sh"
    assert_output --partial "setup 을 중단합니다"
    run grep -c "ok2 ran" "$STUBS/ran"
    assert_output "0"
}

@test "runner: optional failure continues and is listed in the summary" {
    _runner "run_step a optional '$STUBS/bad.sh'; run_step b critical '$STUBS/ok2.sh'; _setup_summary"
    assert_success
    assert_output --partial "a 실패 [optional]"
    assert_output --partial "✅ b"
    assert_output --partial "총 2 / 성공 1 / 경고 0 / 실패 1"
    assert_output --partial "실패 스텝(optional): a"
    grep -q "ok2 ran" "$STUBS/ran"
}

@test "runner: step printing a warning line is classified as warning with that line shown" {
    _runner "run_step w optional '$STUBS/warn.sh'; _setup_summary"
    assert_success
    assert_output --regexp '⚠️  w \([0-9]+\.[0-9]s\) — 경고 1줄'
    assert_output --partial "fix me with X"
    refute_output --partial "fine"
    assert_output --partial "경고 스텝: w"
}

@test "runner: missing script is a failure, not a silent set -e death" {
    _runner "run_step gone critical '$STUBS/nope.sh'"
    assert_failure 1
    assert_output --partial "스크립트가 없거나 실행 권한이 없음"
}

@test "runner: all-green summary is one line plus log path" {
    _runner "run_step a critical '$STUBS/ok.sh'; _setup_summary"
    assert_success
    assert_output --partial "setup 완료: 1개 스텝 모두 정상"
    assert_output --partial "전체 로그: $STUBS/log"
}

@test "choice: DOTFILES_SETUP_CHOICE wins; legacy numeric mode file is the non-tty default" {
    run bash -c "source '$ROOT_SETUP'; DOTFILES_SETUP_CHOICE=3 _setup_resolve_choice </dev/null; echo \"c=\$SETUP_CHOICE\""
    assert_output --partial "c=3"
    echo 2 >"$HOME/.dotfiles-setup-mode"
    run bash -c "source '$ROOT_SETUP'; _setup_resolve_choice </dev/null; echo \"c=\$SETUP_CHOICE\""
    assert_output --partial "c=2"
    rm "$HOME/.dotfiles-setup-mode"
    run bash -c "source '$ROOT_SETUP'; _setup_resolve_choice </dev/null"
    assert_failure
    assert_output --partial "DOTFILES_SETUP_CHOICE"
}
