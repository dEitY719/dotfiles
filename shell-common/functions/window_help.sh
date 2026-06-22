#!/bin/sh
# shell-common/functions/window_help.sh
# Help for Windows-host PowerShell one-liners (WSL vhdx compaction, etc.).
# Registered under the `devops` category in functions/my_help.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# raw URL — Compact-WSL.ps1 remote one-liner (SSOT: windows/Compact-WSL.ps1)
WINDOW_COMPACT_WSL_URL="https://raw.githubusercontent.com/dEitY719/dotfiles/main/windows/Compact-WSL.ps1"

_window_help_summary() {
    ux_section "window — Windows host PowerShell helpers (run on Windows, not WSL)"
    ux_bullet "Compact-WSL.ps1: shrink the WSL2 ext4.vhdx + optional Windows cleanup."
    ux_bullet_sub "Run in PowerShell on the Windows host — NOT inside WSL"
    ux_bullet_sub "('wsl --shutdown' terminates this very session)."

    ux_section "Compact-WSL — remote one-liner (admin PowerShell)"
    ux_bullet "iex (irm '${WINDOW_COMPACT_WSL_URL}')"

    ux_section "From a non-admin shell (auto-elevates)"
    ux_bullet "powershell -ExecutionPolicy Bypass -Command \"iex (irm '${WINDOW_COMPACT_WSL_URL}')\""

    ux_section "Pass parameters (iex can't take args — use a scriptblock)"
    ux_bullet "& ([scriptblock]::Create((irm '${WINDOW_COMPACT_WSL_URL}'))) -DistroName \"Ubuntu\""

    ux_section "Notes"
    ux_bullet "A single registered WSL2 distro is auto-selected — no -DistroName needed."
    ux_bullet "WSL-side disk/health checks: my-help wsl_check"
}

window_help() {
    case "${1:-}" in
    -h | --help | help | "") _window_help_summary ;;
    *) _window_help_summary ;;
    esac
}

alias window-help='window_help'
