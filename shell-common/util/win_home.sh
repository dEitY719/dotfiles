#!/bin/sh
# shell-common/util/win_home.sh
# SSOT for the Windows profile dir (%USERPROFILE%) as a WSL path.
#
# No interactive guard on purpose — same rationale as setup_mode_read.sh:
# aliases/directory.sh, functions/obsidian_claude.sh and tools/custom scripts
# source it for the function. Pure function, no ux_* dependency.
#
# Windows and WSL user names differ per PC (docs/.ssot/pc-environment.md), and
# the profile dir name can differ from %USERNAME% (Microsoft accounts), so
# /mnt/c/Users/$USER and /mnt/c/Users/%USERNAME% are both wrong in general.

# _win_home — print the WSL path of the Windows profile dir; rc 1 when it
# cannot be found (non-WSL, cmd.exe/wslpath missing). $WIN_HOME overrides.
# cmd.exe costs ~100ms: call lazily, never at shell start (see _cd_win).
_win_home() {
    if [ -n "${WIN_HOME-}" ]; then
        printf '%s\n' "$WIN_HOME"
        return 0
    fi
    command -v cmd.exe >/dev/null 2>&1 || return 1
    command -v wslpath >/dev/null 2>&1 || return 1
    # cd /mnt/c: cmd.exe warns about UNC paths when started from a Linux dir.
    _wh_win=$(cd /mnt/c 2>/dev/null || :; cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')
    case "$_wh_win" in
        "" | *%USERPROFILE%*)
            unset _wh_win
            return 1
            ;;
    esac
    _wh_path=$(wslpath -u "$_wh_win" 2>/dev/null)
    unset _wh_win
    if [ -z "$_wh_path" ]; then
        unset _wh_path
        return 1
    fi
    printf '%s\n' "$_wh_path"
    unset _wh_path
}
