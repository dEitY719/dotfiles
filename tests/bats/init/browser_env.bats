#!/usr/bin/env bats
# tests/bats/init/browser_env.bats
# $BROWSER wiring for WSL (issue #1408): shell-common/env/browser.sh must
# point $BROWSER at the Windows-side Chrome on WSL and stay a silent no-op
# everywhere else.

load '../test_helper'

setup() {
    setup_isolated_home
    BROWSER_ENV="${SHELL_COMMON}/env/browser.sh"
    PROC="${TEST_TEMP_HOME}/proc-version"
    CHROME="${TEST_TEMP_HOME}/chrome.exe"
}

teardown() {
    teardown_isolated_home
}

_wsl_proc() {
    printf 'Linux version 6.6.87.2-microsoft-standard-WSL2\n' > "$PROC"
}

_plain_proc() {
    printf 'Linux version 6.8.0-generic (Ubuntu)\n' > "$PROC"
}

_stub_chrome() {
    printf '#!/bin/sh\nprintf "stub:%%s\\n" "$*"\n' > "$CHROME"
    chmod +x "$CHROME"
}

# Source env/browser.sh in a bare subprocess and print the resulting
# $BROWSER via the environment (proves it was *exported*, not just set).
_source_bash() {
    run bash --noprofile --norc -c "
        export SHELL_COMMON='${1:-$SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export _WINDOWS_CHROME_PROC_VERSION='${PROC}'
        export WINDOWS_CHROME_EXE='${WINDOWS_CHROME_EXE:-}'
        export WINDOWS_CHROME_DRIVE='${TEST_TEMP_HOME}/no-such-drive'
        . '${BROWSER_ENV}'
        printenv BROWSER || true
    "
}

_source_zsh() {
    run zsh -f -c "
        export SHELL_COMMON='${1:-$SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export _WINDOWS_CHROME_PROC_VERSION='${PROC}'
        export WINDOWS_CHROME_EXE='${WINDOWS_CHROME_EXE:-}'
        export WINDOWS_CHROME_DRIVE='${TEST_TEMP_HOME}/no-such-drive'
        . '${BROWSER_ENV}'
        printenv BROWSER || true
    "
}

# --- bash ---

@test "bash: WSL + Chrome installed exports BROWSER" {
    _wsl_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_bash
    assert_success
    assert_output "$CHROME"
}

@test "bash: non-WSL exports nothing even when Chrome is reachable" {
    _plain_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_bash
    assert_success
    assert_output ""
}

@test "bash: WSL without Chrome skips silently" {
    _wsl_proc
    _source_bash
    assert_success
    assert_output ""
}

@test "bash: unreadable helper does not break shell init" {
    _wsl_proc
    _stub_chrome
    mkdir -p "${TEST_TEMP_HOME}/empty-shell-common"
    WINDOWS_CHROME_EXE="$CHROME" _source_bash "${TEST_TEMP_HOME}/empty-shell-common"
    assert_success
    assert_output ""
}

# --- zsh ---

@test "zsh: WSL + Chrome installed exports BROWSER" {
    _wsl_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output "$CHROME"
}

@test "zsh: non-WSL exports nothing" {
    _plain_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output ""
}

@test "zsh: WSL without Chrome skips silently" {
    _wsl_proc
    _source_zsh
    assert_success
    assert_output ""
}
