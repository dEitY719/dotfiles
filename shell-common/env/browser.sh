#!/bin/sh
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
# Non-WSL machines (macOS, plain Linux) are a no-op: the WSL probe fails and
# nothing is exported.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_browser_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/windows_chrome.sh"

if [ -r "$_browser_helper" ]; then
    . "$_browser_helper"

    if _windows_chrome_is_wsl; then
        # Chrome absent on the Windows side -> leave $BROWSER untouched so the
        # existing fallback chain keeps working. Never an error: this file runs
        # on every shell start.
        _browser_exe=$(_windows_chrome_exe) && export BROWSER="$_browser_exe"
        unset _browser_exe
    fi
fi

unset _browser_helper
