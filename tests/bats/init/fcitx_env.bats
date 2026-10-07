#!/usr/bin/env bats
# tests/bats/init/fcitx_env.bats
# Issue #2054 — shell-common/env/fcitx.sh autostarted the fcitx daemon from
# every test that sources bash/main.bash (run_in_bash forces init) whenever
# the developer's own env had ENABLE_FCITX=true + DISPLAY. The daemon
# inherited bats' stdin pipe and kept it open forever, so bats never saw EOF
# and the whole file hung after its last test passed. Test mode must not
# autostart, and a real autostart must not keep the caller's stdin.

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_BIN="$TEST_TEMP_HOME/bin"
    MARK="$TEST_TEMP_HOME/autostart.mark"
    mkdir -p "$FAKE_BIN"
    # fcitx must exist for the block to engage; pgrep must report "not running".
    printf '#!/bin/sh\nexit 0\n' >"$FAKE_BIN/fcitx"
    printf '#!/bin/sh\nexit 1\n' >"$FAKE_BIN/pgrep"
    # Records which file its stdin is, then exits (the real one daemonizes).
    printf '#!/bin/sh\nreadlink /proc/$$/fd/0 >"%s"\n' "$MARK" >"$FAKE_BIN/fcitx-autostart"
    chmod +x "$FAKE_BIN"/*
}

teardown() {
    teardown_isolated_home
}

# Source env/fcitx.sh with the developer-style env, its stdin a pipe the way
# bats' is (bash keeps a piped stdin for a background job — run_in_bash
# sources main.bash under bash); $1 = DOTFILES_TEST_MODE.
_source_fcitx() {
    run env PATH="$FAKE_BIN:$PATH" ENABLE_FCITX=true DISPLAY=:0 \
        DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE="$1" \
        bash -c "echo | { . '${SHELL_COMMON}/env/fcitx.sh'; wait \$!; }"
}

@test "fcitx.sh: test mode never autostarts the daemon" {
    _source_fcitx 1
    assert_success
    [ ! -e "$MARK" ]
}

@test "fcitx.sh: a real autostart does not inherit the caller's stdin" {
    [ -e /proc/self/fd/0 ] || skip "needs /proc"
    _source_fcitx ""
    assert_success
    [ -e "$MARK" ]
    assert_equal "$(cat "$MARK")" "/dev/null"
}
