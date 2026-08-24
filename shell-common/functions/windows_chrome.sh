#!/bin/sh
# shell-common/functions/windows_chrome.sh
# SSOT for locating the Windows-side Google Chrome from inside WSL (issue #1408).
#
# Two consumers share this file so the candidate-path list exists exactly once:
#
#   - shell-common/env/browser.sh                   -> exports $BROWSER at init
#   - shell-common/tools/custom/open_in_windows_chrome.sh -> the executable that
#     xdg-open's .desktop entry and `update-alternatives x-www-browser` both
#     point at
#
# No interactive guard here, for the same reason gh_host.sh has none: this file
# only defines functions and produces no output, and the wrapper above is
# executed non-interactively (xdg-open, a .desktop launch, a cron job). A guard
# would return before the definitions and leave those callers with nothing.

# _windows_chrome_is_wsl — return 0 when the running kernel is WSL.
#
# `_WINDOWS_CHROME_PROC_VERSION` overrides the kernel-banner path. It exists so
# both the WSL and the non-WSL branch stay testable on any machine — reading the
# real /proc/version would make the outcome depend on where the suite runs.
_windows_chrome_is_wsl() {
    grep -qi microsoft "${_WINDOWS_CHROME_PROC_VERSION:-/proc/version}" 2>/dev/null
}

# _windows_chrome_exe — print the chrome.exe path on stdout; return 1 if none.
#
# `WINDOWS_CHROME_EXE` pins an explicit executable and deliberately does NOT
# fall back to the search: a broken override is a configuration error, and
# quietly opening some other Chrome would hide it.
# `WINDOWS_CHROME_DRIVE` relocates the Windows C: mount for non-default WSL
# setups (and for the tests).
_windows_chrome_exe() {
    if [ -n "${WINDOWS_CHROME_EXE:-}" ]; then
        [ -x "$WINDOWS_CHROME_EXE" ] || return 1
        printf '%s\n' "$WINDOWS_CHROME_EXE"
        return 0
    fi

    _wce_drive="${WINDOWS_CHROME_DRIVE:-/mnt/c}"

    # sh/bash leave an unmatched glob as its literal pattern, which the -x test
    # below then rejects. zsh does not: `nomatch` is on by default and makes the
    # whole `for` fail loudly — an error line on every shell start of a WSL box
    # without Chrome. `local_options` scopes the opt-out to this function.
    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt local_options null_glob
    fi

    # System-wide installs first, then the per-user one: a machine with both
    # should follow the install every Windows account shares. The last entry is
    # a glob, so the Windows user name never has to be guessed from $USER.
    for _wce_cand in \
        "${_wce_drive}/Program Files/Google/Chrome/Application/chrome.exe" \
        "${_wce_drive}/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
        "${_wce_drive}"/Users/*/AppData/Local/Google/Chrome/Application/chrome.exe; do
        if [ -x "$_wce_cand" ]; then
            printf '%s\n' "$_wce_cand"
            unset _wce_cand _wce_drive
            return 0
        fi
    done

    unset _wce_cand _wce_drive
    return 1
}
