#!/usr/bin/env bats
# tests/bats/tools/ux_lib_spinner.bats
# #1983: ux_spinner's zsh branch used `cut -f$((i+2))` (cut is external, so the
# field number must not depend on the shell): zsh skipped the first frame and
# printed an empty frame at i=9. Re-declaring `local frame_char` inside the
# loop also made zsh print `frame_char=...` every tick. bash, plain zsh and
# `emulate -L sh` zsh must print the same frame sequence with no empty frame.
# ux_menu's fallback must list one line per argument in every shell too.

load '../test_helper'

setup() {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
}

# $1 = bash | zsh | zsh-emulate, $2 = ux_lib call to evaluate
_run_ux() {
    local prelude="export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 NO_COLOR=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        tput() { :; }"
    case "$1" in
        bash) bash --noprofile --norc -c "$prelude
            $2" ;;
        zsh) zsh -f -c "$prelude
            $2" ;;
        zsh-emulate) zsh -f -c "$prelude
            _wrap() { emulate -L sh; $2; }
            _wrap" ;;
    esac </dev/null
}

# Frames printed by a spinner over a stub job that never exits on its own:
# `kill -0` is stubbed to succeed 12 times (12 ticks, wraps past frame 10).
_spinner_frames() {
    _run_ux "$1" 'n=0
        kill() { n=$((n + 1)); [ "$n" -le 12 ]; }
        sleep() { :; }
        ux_spinner 1 msg' | tr '\r' '\n' | sed -n 's/ msg\.\.\.$//p'
}

@test "ux_spinner prints the same 12 non-empty frames in bash, zsh, zsh emulate -L sh" {
    local ref
    ref=$(_spinner_frames bash)
    [ "$(printf '%s\n' "$ref" | wc -l)" -eq 12 ]
    [ "$(printf '%s\n' "$ref" | sed -n 1p)" = "⠋" ]
    [ "$(printf '%s\n' "$ref" | sed -n 10p)" = "⠏" ]
    [ "$(printf '%s\n' "$ref" | sed -n 11p)" = "⠋" ]
    refute grep -qx '' <<<"$ref"
    [ "$(_spinner_frames zsh)" = "$ref" ]
    [ "$(_spinner_frames zsh-emulate)" = "$ref" ]
}

@test "ux_spinner prints no stray typeset output in zsh" {
    run _run_ux zsh 'n=0
        kill() { n=$((n + 1)); [ "$n" -le 3 ]; }
        sleep() { :; }
        ux_spinner 1 msg'
    assert_success
    refute_output --partial 'frame_char='
}

@test "ux_menu fallback lists one line per argument in bash, zsh, zsh emulate -L sh" {
    local call='command() { return 1; }
        printf "2\n" | ux_menu "Pick" "a b" "c" 2>&1'
    local ref
    ref=$(_run_ux bash "$call")
    printf '%s\n' "$ref" | grep -q '1) a b'
    printf '%s\n' "$ref" | grep -q '2) c'
    printf '%s\n' "$ref" | tail -n 1 | grep -q 'Select: 1$'
    [ "$(_run_ux zsh "$call")" = "$ref" ]
    [ "$(_run_ux zsh-emulate "$call")" = "$ref" ]
}

@test "ux_menu fallback prints only the 0-based index on stdout (#1990)" {
    local call='command() { return 1; }
        printf "2\n" | ux_menu "Pick" "a b" "c" 2>/dev/null' _sh
    for _sh in bash zsh zsh-emulate; do
        [ "$(_run_ux "$_sh" "$call")" = "1" ]
    done
}
