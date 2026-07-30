#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_ime.bats
#
# claude/statusline-command.sh (#1251): time segment trimmed to HH:MM:SS,
# and an IME label ("한글"/"영어") is read from `fcitx-remote` and placed
# right before it. Stubs fcitx-remote via a PATH-prepended fake bin so the
# test doesn't depend on a real fcitx daemon.

load '../test_helper'

setup() {
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
    FAKE_BIN="$(mktemp -d)"
}

teardown() {
    rm -rf "$FAKE_BIN"
}

_fake_fcitx_remote() {
    # $1: the fixed exit-state fcitx-remote should print (2/1/0), or
    # "missing" to not create the binary at all (command -v fails).
    [ "$1" = "missing" ] && return 0
    cat >"${FAKE_BIN}/fcitx-remote" <<EOF
#!/bin/sh
echo "$1"
EOF
    chmod +x "${FAKE_BIN}/fcitx-remote"
}

@test "statusline: time segment is HH:MM:SS only, no date" {
    run bash -c "echo '{}' | PATH='${FAKE_BIN}:$PATH' bash '${STATUSLINE}'"
    assert_success
    # No YY-MM-DD style date token (digits-dash-digits-dash-digits) anywhere.
    refute_output --regexp '[0-9]{2}-[0-9]{2}-[0-9]{2}'
    assert_output --regexp '[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "statusline: fcitx-remote state 2 shows 한글 before the time" {
    _fake_fcitx_remote 2
    run bash -c "echo '{}' | PATH='${FAKE_BIN}:$PATH' bash '${STATUSLINE}'"
    assert_success
    assert_output --regexp '한글 [0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "statusline: fcitx-remote state 1 shows 영어 before the time" {
    _fake_fcitx_remote 1
    run bash -c "echo '{}' | PATH='${FAKE_BIN}:$PATH' bash '${STATUSLINE}'"
    assert_success
    assert_output --regexp '영어 [0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "statusline: fcitx-remote state 0 (daemon closed) shows no IME label" {
    _fake_fcitx_remote 0
    run bash -c "echo '{}' | PATH='${FAKE_BIN}:$PATH' bash '${STATUSLINE}'"
    assert_success
    refute_output --partial '한글'
    refute_output --partial '영어'
}

@test "statusline: fcitx-remote missing shows no IME label and no crash" {
    _fake_fcitx_remote missing
    run bash -c "echo '{}' | PATH='${FAKE_BIN}:$PATH' bash '${STATUSLINE}'"
    assert_success
    refute_output --partial '한글'
    refute_output --partial '영어'
}
