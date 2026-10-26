#!/usr/bin/env bats
# tests/bats/init/browser_env.bats
# $BROWSER wiring for WSL (issue #1408): shell-common/env/browser.sh must
# point $BROWSER at the wrapper that fronts the Windows-side Chrome, and stay
# a silent no-op everywhere else.

load '../test_helper'

setup() {
    unset BROWSER
    setup_isolated_home
    BROWSER_ENV="${SHELL_COMMON}/env/browser.sh"
    WRAPPER="${SHELL_COMMON}/tools/custom/open_in_windows_chrome.sh"
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
    mkdir -p "$(dirname "$CHROME")"
    printf '#!/bin/sh\nprintf "stub:%%s\\n" "$*"\n' > "$CHROME"
    chmod +x "$CHROME"
}

# A shell-common lookalike whose env/ is ours to plant files in while
# lib/ and tools/ still point at the real tree.
_fake_shell_common() {
    local root="${TEST_TEMP_HOME}/fake-shell-common"
    mkdir -p "$root/env"
    ln -sfn "${SHELL_COMMON}/lib" "$root/lib"
    ln -sfn "${SHELL_COMMON}/tools" "$root/tools"
    ln -sfn "${SHELL_COMMON}/util" "$root/util"
    printf '%s' "$root"
}

# Source env/browser.sh in a bare subprocess and print the resulting
# $BROWSER via the environment (proves it was *exported*, not just set).
# $1 = SHELL_COMMON override, rest = the shell command words — one env list for
# both shells, so the cross-shell tests are guaranteed to compare like with like.
_source_run() {
    local shell_common="${1:-$SHELL_COMMON}"
    shift
    run env \
        "SHELL_COMMON=${shell_common}" \
        DOTFILES_FORCE_INIT=1 \
        "_WINDOWS_CHROME_PROC_VERSION=${PROC}" \
        "WINDOWS_CHROME_EXE=${WINDOWS_CHROME_EXE:-}" \
        "WINDOWS_CHROME_DRIVE=${TEST_TEMP_HOME}/no-such-drive" \
        "DOTFILES_NO_BROWSER_HINT=${DOTFILES_NO_BROWSER_HINT-1}" \
        "XDG_DATA_HOME=${TEST_TEMP_HOME}/xdg" \
        "$@" -c ". '${BROWSER_ENV}'
printenv BROWSER || true"
}

_source_bash() { _source_run "${1-}" bash --noprofile --norc; }
_source_zsh() { _source_run "${1-}" zsh -f; }
# Interactive (-i) variants: the register hint is interactive-only (#2294).
# bash -i without a tty adds job-control noise on stderr, so hint tests use
# --partial / refute_output --partial rather than an exact match.
_source_bash_i() { _source_run "${1-}" bash --noprofile --norc -i; }
_source_zsh_i() { _source_run "${1-}" zsh -f -i; }

_need_zsh() { command -v zsh > /dev/null 2>&1 || skip "zsh not available"; }

# --- bash ---

@test "bash: WSL + Chrome installed exports the wrapper as BROWSER" {
    _wsl_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_bash
    assert_success
    assert_output "$WRAPPER"
}

# The actual defect this file guards. $BROWSER is a command spec, not a path:
# Python's webbrowser (shlex.split), sensible-browser and friends word-split
# it, so exporting the real chrome.exe — which lives under "Program Files" —
# made them try to run `/mnt/c/Program`. Plant the space-carrying install
# shape so a revert to exporting chrome.exe fails here.
@test "bash: BROWSER is the wrapper, never a chrome.exe path containing a space" {
    _wsl_proc
    CHROME="${TEST_TEMP_HOME}/Program Files/Google/Chrome/Application/chrome.exe"
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_bash
    assert_success
    assert_output "$WRAPPER"
    case "$output" in
    *" "*) fail "BROWSER must not contain a space: ${output}" ;;
    esac
}

# xdg-open registration is machine-local; a fresh WSL lacks it, so say how to fix it.
@test "bash: WSL + Chrome without the xdg desktop entry prints a register hint" {
    _wsl_proc
    _stub_chrome
    DOTFILES_NO_BROWSER_HINT= WINDOWS_CHROME_EXE="$CHROME" _source_bash_i
    assert_success
    assert_output --partial "--register"
}

# #2294: forced non-interactive init (bats `run`, pytest pty, scripts) must not
# leak the hint into captured output — the exact repro of a WSL dev PC.
@test "bash: non-interactive init never prints the register hint" {
    _wsl_proc
    _stub_chrome
    DOTFILES_NO_BROWSER_HINT= WINDOWS_CHROME_EXE="$CHROME" _source_bash
    assert_success
    assert_output "$WRAPPER"
}

@test "zsh: interactive init prints the register hint, non-interactive does not" {
    _need_zsh
    _wsl_proc
    _stub_chrome
    DOTFILES_NO_BROWSER_HINT= WINDOWS_CHROME_EXE="$CHROME" _source_zsh_i
    assert_success
    assert_output --partial "--register"
    DOTFILES_NO_BROWSER_HINT= WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output "$WRAPPER"
}

@test "bash: the register hint is silent once windows-chrome.desktop exists" {
    _wsl_proc
    _stub_chrome
    mkdir -p "${TEST_TEMP_HOME}/xdg/applications"
    : > "${TEST_TEMP_HOME}/xdg/applications/windows-chrome.desktop"
    DOTFILES_NO_BROWSER_HINT= WINDOWS_CHROME_EXE="$CHROME" _source_bash_i
    assert_success
    assert_output --partial "$WRAPPER"
    refute_output --partial "--register"
}

@test "bash: DOTFILES_NO_BROWSER_HINT silences the register hint" {
    _wsl_proc
    _stub_chrome
    DOTFILES_NO_BROWSER_HINT=1 WINDOWS_CHROME_EXE="$CHROME" _source_bash_i
    assert_success
    assert_output --partial "$WRAPPER"
    refute_output --partial "--register"
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

# chrome.exe stays the gate even though the wrapper is what gets exported:
# with Chrome absent the wrapper can only error out, so exporting it would
# just move the failure.
@test "bash: Chrome absent exports nothing even though the wrapper is executable" {
    _wsl_proc
    [ -x "$WRAPPER" ]
    _source_bash
    assert_success
    assert_output ""
}

# The mirror image: Chrome is there but the wrapper is not runnable (partial
# checkout, lost +x). Exporting it would hand every consumer a broken spec.
@test "bash: a non-executable wrapper exports nothing" {
    _wsl_proc
    _stub_chrome
    local root="${TEST_TEMP_HOME}/no-exec-shell-common"
    mkdir -p "$root/tools/custom"
    ln -sfn "${SHELL_COMMON}/lib" "$root/lib"
    cp "$WRAPPER" "$root/tools/custom/open_in_windows_chrome.sh"
    chmod -x "$root/tools/custom/open_in_windows_chrome.sh"
    WINDOWS_CHROME_EXE="$CHROME" _source_bash "$root"
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

# --- machine-local override ---

# The supported way to keep a different browser on one machine, matching the
# proxy.local.sh / security.local.sh house pattern. It must load *after* the
# default so it wins — no "only export if unset" guard, which would make a
# stale value sticky across `src` reloads.
@test "bash: env/browser.local.sh overrides the default BROWSER" {
    _wsl_proc
    _stub_chrome
    local root
    root="$(_fake_shell_common)"
    printf 'export BROWSER=/usr/bin/firefox\n' > "${root}/env/browser.local.sh"
    unset DOTFILES_SKIP_LOCAL_ENV # fixture tree: the local file is the subject
    WINDOWS_CHROME_EXE="$CHROME" _source_bash "$root"
    assert_success
    assert_output "/usr/bin/firefox"
}

@test "bash: no browser.local.sh leaves the default in place" {
    _wsl_proc
    _stub_chrome
    local root
    root="$(_fake_shell_common)"
    WINDOWS_CHROME_EXE="$CHROME" _source_bash "$root"
    assert_success
    assert_output "${root}/tools/custom/open_in_windows_chrome.sh"
}

# --- zsh ---

@test "zsh: WSL + Chrome installed exports the wrapper as BROWSER" {
    _need_zsh
    _wsl_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output "$WRAPPER"
}

@test "zsh: BROWSER contains no space" {
    _need_zsh
    _wsl_proc
    CHROME="${TEST_TEMP_HOME}/Program Files/Google/Chrome/Application/chrome.exe"
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output "$WRAPPER"
    case "$output" in
    *" "*) fail "BROWSER must not contain a space: ${output}" ;;
    esac
}

@test "zsh: non-WSL exports nothing" {
    _need_zsh
    _plain_proc
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _source_zsh
    assert_success
    assert_output ""
}

@test "zsh: WSL without Chrome skips silently" {
    _need_zsh
    _wsl_proc
    _source_zsh
    assert_success
    assert_output ""
}
