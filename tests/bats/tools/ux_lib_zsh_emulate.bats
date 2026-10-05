#!/usr/bin/env bats
# tests/bats/tools/ux_lib_zsh_emulate.bats
# #1977: zsh 호출자가 `emulate -L sh` 를 켠 상태에서 ux_section / ux_divider /
# ux_divider_thick / ux_table_header 를 부르면 zsh 전용 `{1..N}` brace range 가
# 리터럴이 되어 밑줄/구분선이 문자 1개로 붕괴했다. bash, plain zsh, emulate -L sh
# zsh 세 경로의 출력이 바이트 단위로 같고 선 길이가 기대값인지 검증한다.

load '../test_helper'

setup() {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
}

# $1 = bash | zsh | zsh-emulate, $2 = ux_lib call to evaluate
_run_ux() {
    local prelude="export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 NO_COLOR=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'"
    case "$1" in
        bash) bash --noprofile --norc -c "$prelude
            $2" ;;
        zsh) zsh -f -c "$prelude
            $2" ;;
        zsh-emulate) zsh -f -c "$prelude
            _wrap() { emulate -L sh; $2; }
            _wrap" ;;
    esac
}

# Runs $1 in all three modes, asserts identical output, leaves it in $output.
_assert_same_everywhere() {
    local ref
    ref=$(_run_ux bash "$1")
    run _run_ux zsh "$1"
    assert_success
    [ "$output" = "$ref" ]
    run _run_ux zsh-emulate "$1"
    assert_success
    [ "$output" = "$ref" ]
}

# Count of char $1 in the last non-empty line of $output.
_line_len() {
    printf '%s\n' "$output" | sed '/^$/d' | tail -n 1 | tr -d ' ' | wc -m |
        awk '{print $1 - 1}'
}

@test "ux_section underline length equals title length in bash, zsh, zsh emulate -L sh" {
    _assert_same_everywhere 'ux_section "abcdef"'
    [ "$(_line_len)" -eq 6 ]
}

@test "ux_divider default and explicit width survive emulate -L sh" {
    _assert_same_everywhere 'ux_divider'
    [ "$(_line_len)" -eq 60 ]
    _assert_same_everywhere 'ux_divider 7'
    [ "$(_line_len)" -eq 7 ]
}

@test "ux_divider_thick survives emulate -L sh" {
    _assert_same_everywhere 'ux_divider_thick 9'
    [ "$(_line_len)" -eq 9 ]
}

@test "ux_table_header 2-column rule is 60 wide everywhere" {
    _assert_same_everywhere 'ux_table_header A B'
    [ "$(_line_len)" -eq 60 ]
}

@test "ux_table_header 3-column rule is 80 wide everywhere" {
    _assert_same_everywhere 'ux_table_header A B C'
    [ "$(_line_len)" -eq 80 ]
}

@test "ux_header box survives emulate -L sh identically" {
    _assert_same_everywhere 'ux_header "Hello"'
}
