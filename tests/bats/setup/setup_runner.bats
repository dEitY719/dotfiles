#!/usr/bin/env bats
# tests/bats/setup/setup_runner.bats
# Coverage for the shared step runner (shell-common/tools/ux_lib/step_runner.sh:
# step_init / step_run / step_summary, #2126) as ./setup.sh wires it, plus
# _setup_resolve_choice. setup.sh only calls main() when executed, so these
# tests source it and drive step_run against stub scripts — the real
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
    run bash -c "set -e; source '$ROOT_SETUP'; STEP_LOG='$STUBS/log'; STEP_OUT='$STUBS/step'; $1"
}

@test "runner: successful step prints exactly one success line, detail stays in log" {
    _runner "step_run first critical '$STUBS/ok.sh'"
    assert_success
    assert_equal "${#lines[@]}" 1
    assert_output --regexp '^✅ first \([0-9]+\.[0-9]s\)$'
    grep -q "noisy detail" "$STUBS/log"
}

@test "runner: critical failure stops immediately; later steps never run" {
    _runner "step_run a critical '$STUBS/ok.sh'; step_run b critical '$STUBS/bad.sh'; step_run c critical '$STUBS/ok2.sh'"
    assert_failure 1
    assert_output --partial "b 실패 [critical] (exit 3"
    assert_output --partial "boom-detail"
    assert_output --partial "bash -x $STUBS/bad.sh"
    assert_output --partial "setup 을 중단합니다"
    run grep -c "ok2 ran" "$STUBS/ran"
    assert_output "0"
}

@test "runner: optional failure continues and is listed in the summary" {
    _runner "step_run a optional '$STUBS/bad.sh'; step_run b critical '$STUBS/ok2.sh'; step_summary setup"
    assert_success
    assert_output --partial "a 실패 [optional]"
    assert_output --partial "✅ b"
    assert_output --partial "총 2 / 성공 1 / 경고 0 / 실패 1"
    assert_output --partial "실패 스텝(optional): a"
    grep -q "ok2 ran" "$STUBS/ran"
}

@test "runner: step printing a warning line is classified as warning with that line shown" {
    _runner "step_run w optional '$STUBS/warn.sh'; step_summary setup"
    assert_success
    assert_output --regexp '⚠️  w \([0-9]+\.[0-9]s\) — 경고 1줄'
    assert_output --partial "fix me with X"
    refute_output --partial "fine"
    assert_output --partial "경고 스텝: w"
}

@test "runner: missing script is a failure, not a silent set -e death" {
    _runner "step_run gone critical '$STUBS/nope.sh'"
    assert_failure 1
    assert_output --partial "스크립트가 없거나 실행 권한이 없음"
}

@test "runner: all-green summary is one line plus log path" {
    _runner "step_run a critical '$STUBS/ok.sh'; step_summary setup"
    assert_success
    assert_output --partial "setup 완료: 1개 스텝 모두 정상"
    assert_output --partial "전체 로그: $STUBS/log"
}

@test "runner: ux_lib fallback WARN:/ERR: lines count as warnings" {
    printf '#!/bin/sh\necho "WARN: dirty repo"\necho "ERR: soft error" >&2\necho fine\n' >"$STUBS/fb.sh"
    chmod +x "$STUBS/fb.sh"
    _runner "step_run fb optional '$STUBS/fb.sh'"
    assert_success
    assert_output --partial "fb ("
    assert_output --partial "경고 2줄"
    assert_output --partial "WARN: dirty repo"
    assert_output --partial "ERR: soft error"
}

@test "runner: optional failure leaves its exit code in STEP_LAST_RC" {
    _runner "step_run a optional '$STUBS/bad.sh'; rc=\$STEP_LAST_RC; step_run b optional '$STUBS/ok.sh'; echo \"rc=\$rc last=\$STEP_LAST_RC\""
    assert_success
    assert_output --partial "rc=3 last=0"
}

@test "runner: STEP_DIGEST_FN appends a digest to a clean success line" {
    _runner "_dg() { STEP_DIGEST=\"갱신 0 / 최신 \$(grep -c noisy \"\$STEP_OUT\")\"; }; STEP_DIGEST_FN=_dg; step_run d critical '$STUBS/ok.sh'"
    assert_success
    assert_output --regexp '^✅ d \([0-9]+\.[0-9]s\) — 갱신 0 / 최신 1$'
}

@test "runner: unwritable TMPDIR falls back to verbose with one warning" {
    run bash -c "source '$ROOT_SETUP'; TMPDIR='$STUBS/no/such/dir' step_init t 0; echo \"v=\$STEP_VERBOSE log=\$STEP_LOG\""
    assert_success
    assert_output --partial "전체 출력 모드로 전환"
    assert_output --partial "v=1 log=/dev/null"
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
