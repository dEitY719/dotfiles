#!/usr/bin/env bats
# tests/bats/functions/windows_chrome.bats
# Windows-side Chrome resolution helper — SSOT shared by
# shell-common/env/browser.sh and tools/custom/open_in_windows_chrome.sh
# (issue #1408).

load '../test_helper'

setup() {
    setup_isolated_home
    HELPER="${SHELL_COMMON}/functions/windows_chrome.sh"
    FAKE_DRIVE="${TEST_TEMP_HOME}/mnt/c"
    PROC="${TEST_TEMP_HOME}/proc-version"
}

teardown() {
    teardown_isolated_home
}

# Source the helper in a bare subprocess and run BODY against it.
# $1 = body, rest = the shell command words — one env list for both shells, so
# the cross-shell tests are guaranteed to compare like with like.
_helper_run() {
    local body="$1"
    shift
    run env \
        "_WINDOWS_CHROME_PROC_VERSION=${PROC}" \
        "WINDOWS_CHROME_DRIVE=${FAKE_DRIVE}" \
        "WINDOWS_CHROME_EXE=${WINDOWS_CHROME_EXE:-}" \
        "$@" -c ". '${HELPER}'
${body}"
}

_helper_bash() { _helper_run "$1" bash --noprofile --norc; }
_helper_zsh() { _helper_run "$1" zsh -f; }

# The cross-shell tests below are the only ones that need zsh; a machine
# without it must skip them, not fail (same guard as setup_mode.bats /
# gh_pr_review.bats).
_need_zsh() { command -v zsh >/dev/null 2>&1 || skip "zsh not available"; }

# Create an executable stub at $1 (parent dirs included).
_stub_exe() {
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\nprintf "stub:%%s\\n" "$*"\n' > "$1"
    chmod +x "$1"
}

# --- WSL detection -------------------------------------------------

@test "_windows_chrome_is_wsl: true when /proc/version names microsoft" {
    printf 'Linux version 6.6.87.2-microsoft-standard-WSL2\n' > "$PROC"
    _helper_bash '_windows_chrome_is_wsl && echo yes'
    assert_success
    assert_output "yes"
}

@test "_windows_chrome_is_wsl: case-insensitive match" {
    printf 'Linux version 5.15.0 (Microsoft@WSL)\n' > "$PROC"
    _helper_bash '_windows_chrome_is_wsl && echo yes'
    assert_success
    assert_output "yes"
}

@test "_windows_chrome_is_wsl: false on a plain Linux kernel" {
    printf 'Linux version 6.8.0-generic (Ubuntu)\n' > "$PROC"
    _helper_bash '_windows_chrome_is_wsl || echo no'
    assert_success
    assert_output "no"
}

@test "_windows_chrome_is_wsl: false when the proc file is missing" {
    rm -f "$PROC"
    _helper_bash '_windows_chrome_is_wsl || echo no'
    assert_success
    assert_output "no"
}

# --- executable resolution -----------------------------------------

@test "_windows_chrome_exe: honors an executable WINDOWS_CHROME_EXE override" {
    local exe="${TEST_TEMP_HOME}/custom-chrome.exe"
    _stub_exe "$exe"
    WINDOWS_CHROME_EXE="$exe" _helper_bash '_windows_chrome_exe'
    assert_success
    assert_output "$exe"
}

@test "_windows_chrome_exe: fails when WINDOWS_CHROME_EXE is set but not executable" {
    local exe="${TEST_TEMP_HOME}/missing-chrome.exe"
    # A default-install candidate exists — an explicit broken override must
    # still fail rather than silently opening a different Chrome.
    _stub_exe "${FAKE_DRIVE}/Program Files/Google/Chrome/Application/chrome.exe"
    WINDOWS_CHROME_EXE="$exe" _helper_bash '_windows_chrome_exe'
    assert_failure
    assert_output ""
}

@test "_windows_chrome_exe: finds the Program Files install" {
    local exe="${FAKE_DRIVE}/Program Files/Google/Chrome/Application/chrome.exe"
    _stub_exe "$exe"
    _helper_bash '_windows_chrome_exe'
    assert_success
    assert_output "$exe"
}

@test "_windows_chrome_exe: finds the 32-bit Program Files (x86) install" {
    local exe="${FAKE_DRIVE}/Program Files (x86)/Google/Chrome/Application/chrome.exe"
    _stub_exe "$exe"
    _helper_bash '_windows_chrome_exe'
    assert_success
    assert_output "$exe"
}

@test "_windows_chrome_exe: finds a per-user AppData install" {
    local exe="${FAKE_DRIVE}/Users/someone/AppData/Local/Google/Chrome/Application/chrome.exe"
    _stub_exe "$exe"
    _helper_bash '_windows_chrome_exe'
    assert_success
    assert_output "$exe"
}

@test "_windows_chrome_exe: prefers Program Files over a per-user install" {
    local sys="${FAKE_DRIVE}/Program Files/Google/Chrome/Application/chrome.exe"
    _stub_exe "$sys"
    _stub_exe "${FAKE_DRIVE}/Users/someone/AppData/Local/Google/Chrome/Application/chrome.exe"
    _helper_bash '_windows_chrome_exe'
    assert_success
    assert_output "$sys"
}

@test "_windows_chrome_exe: fails silently when Chrome is not installed" {
    _helper_bash '_windows_chrome_exe'
    assert_failure
    assert_output ""
}

@test "_windows_chrome_exe: ignores a non-executable chrome.exe" {
    local exe="${FAKE_DRIVE}/Program Files/Google/Chrome/Application/chrome.exe"
    mkdir -p "$(dirname "$exe")"
    : > "$exe"
    _helper_bash '_windows_chrome_exe'
    # A missing helper exits 127, which assert_failure alone accepts (#1419).
    assert_failure
    assert_output ""
}

# --- cross-shell ---------------------------------------------------

@test "zsh: helper sources and resolves identically" {
    _need_zsh
    local exe="${FAKE_DRIVE}/Program Files/Google/Chrome/Application/chrome.exe"
    _stub_exe "$exe"
    _helper_zsh '_windows_chrome_exe'
    assert_success
    assert_output "$exe"
}

@test "zsh: WSL detection works" {
    _need_zsh
    printf 'Linux version 6.6.87.2-microsoft-standard-WSL2\n' > "$PROC"
    _helper_zsh '_windows_chrome_is_wsl && echo yes'
    assert_success
    assert_output "yes"
}
