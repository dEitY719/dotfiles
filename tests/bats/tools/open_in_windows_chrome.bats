#!/usr/bin/env bats
# tests/bats/tools/open_in_windows_chrome.bats
# Thin wrapper that xdg-open's .desktop entry and update-alternatives
# x-www-browser both point at, so all three browser paths land on the same
# Windows-side Chrome (issue #1408).

load '../test_helper'

setup() {
    setup_isolated_home
    SCRIPT="${SHELL_COMMON}/tools/custom/open_in_windows_chrome.sh"
    CHROME="${TEST_TEMP_HOME}/chrome.exe"
    DESKTOP="${TEST_TEMP_HOME}/applications/windows-chrome.desktop"
}

teardown() {
    teardown_isolated_home
}

_stub_chrome() {
    printf '#!/bin/sh\nprintf "stub:%%s\\n" "$*"\n' > "$CHROME"
    chmod +x "$CHROME"
}

_run_script() {
    run env \
        DOTFILES_TEST_MODE=1 \
        HOME="$TEST_TEMP_HOME" \
        XDG_DATA_HOME="$TEST_TEMP_HOME" \
        WINDOWS_CHROME_EXE="${WINDOWS_CHROME_EXE:-}" \
        WINDOWS_CHROME_DRIVE="${TEST_TEMP_HOME}/no-such-drive" \
        bash "$SCRIPT" "$@"
}

# --- help ---

@test "--help exits 0 and documents usage" {
    _run_script --help
    assert_success
    assert_output --partial "open_in_windows_chrome.sh"
    assert_output --partial "--register"
}

@test "-h is accepted as help" {
    _run_script -h
    assert_success
    assert_output --partial "open_in_windows_chrome.sh"
}

# --- open ---

@test "forwards the URL to the resolved Chrome executable" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script "https://example.com"
    assert_success
    assert_output "stub:https://example.com"
}

@test "forwards multiple arguments unchanged" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script --new-window "https://example.com"
    assert_success
    assert_output "stub:--new-window https://example.com"
}

@test "fails with a message when Chrome cannot be located" {
    _run_script "https://example.com"
    assert_failure
    assert_output --partial "Chrome"
}

@test "a broken WINDOWS_CHROME_EXE is reported as an override problem" {
    # Plant a Chrome the default search WOULD find, so this proves both that
    # an explicit override never falls back and that the message names the
    # right one of the two failures.
    CHROME="${TEST_TEMP_HOME}/no-such-drive/Program Files/Google/Chrome/Application/chrome.exe"
    mkdir -p "$(dirname "$CHROME")"
    _stub_chrome
    WINDOWS_CHROME_EXE="${TEST_TEMP_HOME}/gone.exe" _run_script "https://example.com"
    assert_failure
    assert_output --partial "WINDOWS_CHROME_EXE"
}

# --- register ---

@test "--register --dry-run reports the plan without touching the system" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register --dry-run
    assert_success
    assert_output --partial "windows-chrome.desktop"
    assert_output --partial "x-www-browser"
    [ ! -e "$DESKTOP" ]
}

@test "--register --dry-run names this wrapper as the shared target" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register --dry-run
    assert_success
    assert_output --partial "$SCRIPT"
}

# --- misc ---

# Only the first argument selects a mode; everything else is forwarded
# verbatim, so Chrome's own flags keep working. `--` forces pass-through
# for the rare case where a literal argument collides with a mode name.
@test "-- forces pass-through of an argument that looks like a mode" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script -- --register
    assert_success
    assert_output "stub:--register"
}
