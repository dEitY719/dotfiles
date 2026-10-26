#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/env/browser.sh
# WSL: point $BROWSER at the Windows-side Google Chrome (issue #1408).
#
# WSL has three independent "default browser" mechanisms and changing one does
# not move the others: $BROWSER (this file), xdg-open via mimeapps.list, and
# `update-alternatives x-www-browser`. The latter two are machine-local state,
# not repo state, so they are registered on demand by
# `shell-common/tools/custom/open_in_windows_chrome.sh --register` — which
# resolves chrome.exe through the same helper sourced below, so all three paths
# end up on one executable.
#
# $BROWSER holds the WRAPPER path, never chrome.exe itself. $BROWSER is a
# *command spec*, not a plain path: Python's `webbrowser` runs it through
# `shlex.split`, `sensible-browser` and many other CLIs word-split it the same
# way. The default install lives at
# `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe`, so exporting it
# directly makes every such consumer try to execute `/mnt/c/Program`. The
# wrapper's own path carries no space and forwards its arguments to chrome.exe.
#
# Non-WSL machines (macOS, plain Linux) are a no-op: the WSL probe fails and
# nothing is exported.

_browser_root="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
_browser_helper="${_browser_root}/lib/windows_chrome.sh"
_browser_wrapper="${_browser_root}/tools/custom/open_in_windows_chrome.sh"

if [ -r "$_browser_helper" ]; then
    # shellcheck source=/dev/null
    . "$_browser_helper"

    if _windows_chrome_is_wsl; then
        # chrome.exe stays the gate even though the wrapper is what gets
        # exported: with Chrome absent the wrapper would only ever error out,
        # so leave $BROWSER untouched and let the existing fallback chain keep
        # working. Never an error — this file runs on every shell start.
        # A non-executable wrapper (a partial checkout, a lost +x bit) is the
        # same story: exporting it would hand every consumer a broken spec.
        if _windows_chrome_exe >/dev/null 2>&1 && [ -x "$_browser_wrapper" ]; then
            export BROWSER="$_browser_wrapper"
            # xdg-open (what terminal link clicks use) is machine-local state that a
            # fresh WSL install lacks, so links land in the Linux Chrome and die on a
            # proxy-resigned cert. Hint only — registering rewrites desktop defaults,
            # so it stays an explicit step. Silence: DOTFILES_NO_BROWSER_HINT=1.
            if [ -z "${DOTFILES_NO_BROWSER_HINT-}" ] &&
                [ ! -e "${XDG_DATA_HOME:-$HOME/.local/share}/applications/windows-chrome.desktop" ]; then
                printf '[hint] xdg-open is not on Windows Chrome yet - run: %s --register\n' \
                    "$_browser_wrapper" >&2
            fi
        fi
    fi
fi

unset _browser_helper _browser_wrapper

# ============================================================
# ENVIRONMENT-SPECIFIC SETTINGS (loaded if exists)
# ============================================================
#
# Machine-local override (browser.local.sh), same house pattern as proxy /
# security. It loads *after* the default above, so assigning
# BROWSER there wins — that is the supported way to keep a different browser
# on one machine without an "only export if unset" guard here (such a guard
# would make a stale value sticky across `src` reloads).
[ -r "$_browser_root/util/local_env.sh" ] && . "$_browser_root/util/local_env.sh" &&
    _dotfiles_source_local browser "$_browser_root"

unset _browser_root
