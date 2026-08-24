#!/usr/bin/env bats
# tests/bats/tools/open_in_windows_chrome.bats
# Thin wrapper that $BROWSER, xdg-open's .desktop entry and update-alternatives
# x-www-browser all point at, so all three browser paths land on the same
# Windows-side Chrome (issue #1408).

load '../test_helper'

setup() {
    setup_isolated_home
    SCRIPT="${SHELL_COMMON}/tools/custom/open_in_windows_chrome.sh"
    CHROME="${TEST_TEMP_HOME}/chrome.exe"
    DESKTOP="${TEST_TEMP_HOME}/applications/windows-chrome.desktop"
    STUB_BIN="${TEST_TEMP_HOME}/stub-bin"
    STUB_LOG="${TEST_TEMP_HOME}/stub.log"
    mkdir -p "$STUB_BIN"
    # Both stubs are unconditional so no test depends on what the machine
    # running the suite happens to have: this box IS WSL and DOES ship
    # wslpath, and the suite must behave the same on a plain Linux CI box.
    _stub_wslpath
    _stub_git_no_repo
}

teardown() {
    teardown_isolated_home
}

_stub_chrome() {
    mkdir -p "$(dirname "$CHROME")"
    printf '#!/bin/sh\nprintf "stub:%%s\\n" "$*"\n' > "$CHROME"
    chmod +x "$CHROME"
}

# Deterministic stand-in for the real wslpath: `-w /a/b` -> `C:\a\b`.
_stub_wslpath() {
    cat > "${STUB_BIN}/wslpath" <<'STUB'
#!/bin/sh
printf 'C:%s\n' "$(printf '%s' "$2" | tr '/' '\\')"
STUB
    chmod +x "${STUB_BIN}/wslpath"
}

# What _stub_wslpath would return for $1.
_win_path() {
    printf 'C:%s' "$(printf '%s' "$1" | tr '/' '\\')"
}

# git says "not a repository" — an installed copy outside any checkout, which
# --register must accept. Default for every test so the suite does not depend
# on the fact that it is itself run from a worktree.
_stub_git_no_repo() {
    cat > "${STUB_BIN}/git" <<'STUB'
#!/bin/sh
exit 128
STUB
    chmod +x "${STUB_BIN}/git"
}

# git says "linked worktree": --absolute-git-dir points inside the main
# repo's .git/worktrees/, --git-common-dir at the main .git itself.
_stub_git_linked_worktree() {
    cat > "${STUB_BIN}/git" <<'STUB'
#!/bin/sh
for a in "$@"; do
    case "$a" in
    --absolute-git-dir) printf '%s\n' "/home/u/dotfiles/.git/worktrees/wt-1"; exit 0 ;;
    --git-common-dir) printf '%s\n' "/home/u/dotfiles/.git"; exit 0 ;;
    esac
done
exit 128
STUB
    chmod +x "${STUB_BIN}/git"
}

# git says "main checkout": both paths resolve to the same .git dir.
_stub_git_main_checkout() {
    cat > "${STUB_BIN}/git" <<'STUB'
#!/bin/sh
for a in "$@"; do
    case "$a" in
    --absolute-git-dir | --git-common-dir) printf '%s\n' "/home/u/dotfiles/.git"; exit 0 ;;
    esac
done
exit 128
STUB
    chmod +x "${STUB_BIN}/git"
}

# Everything a real --register shells out to, each logging its own argv and
# touching nothing. `sudo` never execs its argument, so no privileged command
# can escape the sandbox even if the box has passwordless sudo.
_stub_desktop_tools() {
    local name
    for name in xdg-settings xdg-mime update-desktop-database update-alternatives sudo; do
        cat > "${STUB_BIN}/${name}" <<STUB
#!/bin/sh
printf '%s %s\n' "${name}" "\$*" >> "${STUB_LOG}"
exit 0
STUB
        chmod +x "${STUB_BIN}/${name}"
    done
}

_run_script_at() {
    local script="$1"
    shift
    run env \
        DOTFILES_TEST_MODE=1 \
        HOME="$TEST_TEMP_HOME" \
        XDG_DATA_HOME="$TEST_TEMP_HOME" \
        PATH="${STUB_BIN}:${PATH}" \
        WINDOWS_CHROME_EXE="${WINDOWS_CHROME_EXE:-}" \
        WINDOWS_CHROME_DRIVE="${TEST_TEMP_HOME}/no-such-drive" \
        bash "$script" "$@"
}

_run_script() { _run_script_at "$SCRIPT" "$@"; }

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

# --- WSL -> Windows path translation ---
#
# --register claims text/html, so `xdg-open ./report.html` and a file:// URL
# do reach this wrapper — and chrome.exe cannot see /home/... at all.

@test "an existing local path is translated to a Windows path" {
    _stub_chrome
    local file="${TEST_TEMP_HOME}/report.html"
    : > "$file"
    WINDOWS_CHROME_EXE="$CHROME" _run_script "$file"
    assert_success
    assert_output "stub:$(_win_path "$file")"
}

@test "a file:// URL for an existing file is translated, %20 decoded" {
    _stub_chrome
    local file="${TEST_TEMP_HOME}/my report.html"
    : > "$file"
    WINDOWS_CHROME_EXE="$CHROME" _run_script "file://${TEST_TEMP_HOME}/my%20report.html"
    assert_success
    assert_output "stub:$(_win_path "$file")"
}

@test "an https URL is forwarded byte-identical" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script "https://example.com/a%20b?q=1#frag"
    assert_success
    assert_output "stub:https://example.com/a%20b?q=1#frag"
}

@test "a path that does not exist is forwarded unchanged" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script "${TEST_TEMP_HOME}/no-such-file.html"
    assert_success
    assert_output "stub:${TEST_TEMP_HOME}/no-such-file.html"
}

@test "a Chrome flag is forwarded unchanged" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script --new-window
    assert_success
    assert_output "stub:--new-window"
}

@test "a file:// URL naming a missing file is forwarded unchanged" {
    _stub_chrome
    WINDOWS_CHROME_EXE="$CHROME" _run_script "file://${TEST_TEMP_HOME}/gone.html"
    assert_success
    assert_output "stub:file://${TEST_TEMP_HOME}/gone.html"
}

# --- register: worktree refusal ---

@test "--register refuses to run from a linked git worktree" {
    _stub_chrome
    _stub_git_linked_worktree
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register
    assert_failure
    assert_output --partial "linked git worktree"
    assert_output --partial "/home/u/dotfiles"
    [ ! -e "$DESKTOP" ]
}

# The refusal sits ahead of the dry-run branch on purpose: --dry-run promises
# what a real run would do, and a real run from here would only break things.
@test "--register --dry-run reports the worktree refusal too" {
    _stub_chrome
    _stub_git_linked_worktree
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register --dry-run
    assert_failure
    assert_output --partial "linked git worktree"
}

@test "--register --dry-run proceeds from a main checkout" {
    _stub_chrome
    _stub_git_main_checkout
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register --dry-run
    assert_success
    assert_output --partial "Dry run"
    refute_output --partial "linked git worktree"
}

# --- register: dry run ---

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

# --- register: the real thing ---
#
# Fully sandboxed: XDG_DATA_HOME is the per-test temp home, and every external
# command --register calls is a logging stub first on PATH.

@test "--register writes the desktop entry and sets the xdg defaults" {
    _stub_chrome
    _stub_desktop_tools
    WINDOWS_CHROME_EXE="$CHROME" _run_script --register
    assert_success

    [ -f "$DESKTOP" ]
    run cat "$DESKTOP"
    assert_output --partial "Type=Application"
    assert_output --partial "Exec=\"${SCRIPT}\" %u"
    assert_output --partial "MimeType=text/html;"
    assert_output --partial "x-scheme-handler/https;"

    run cat "$STUB_LOG"
    assert_output --partial "xdg-settings set default-web-browser windows-chrome.desktop"
    assert_output --partial "xdg-mime default windows-chrome.desktop x-scheme-handler/http x-scheme-handler/https text/html"
    assert_output --partial "update-desktop-database ${TEST_TEMP_HOME}/applications"
}

# The Desktop Entry spec requires the Exec executable to be quoted; without
# it a dotfiles checkout under "Program Files"-style path is unlaunchable.
@test "--register quotes an Exec path that contains a space" {
    _stub_chrome
    _stub_desktop_tools
    local base="${TEST_TEMP_HOME}/dir with space"
    mkdir -p "${base}/tools/custom"
    ln -sfn "${SHELL_COMMON}/functions" "${base}/functions"
    ln -sfn "${SHELL_COMMON}/tools/ux_lib" "${base}/tools/ux_lib"
    cp "$SCRIPT" "${base}/tools/custom/open_in_windows_chrome.sh"

    local self
    self="$(realpath "${base}/tools/custom/open_in_windows_chrome.sh")"
    WINDOWS_CHROME_EXE="$CHROME" _run_script_at "$self" --register
    assert_success

    run cat "$DESKTOP"
    assert_output --partial "Exec=\"${self}\" %u"
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
