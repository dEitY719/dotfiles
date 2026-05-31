#!/bin/sh
# shell-common/functions/wsl_check_help.sh
# Help for wsl-check (see wsl_check.sh). Registered under the `devops`
# category in functions/my_help.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_wsl_check_help_summary() {
    ux_section "wsl-check — WSL & Docker environment health"
    ux_table_header "Command" "Description"
    ux_table_row "wsl-check" "One-line summary (c-drive / disk / cpu / mem / docker)"
    ux_table_row "wsl-check --all" "Detailed sectioned report"
    ux_table_row "wsl-check --prune" "Report + prune build cache & dangling images"
    ux_table_row "wsl-check --prune-all" "Report + full docker system prune"
    ux_table_row "wsl-check -h" "This help"

    ux_section "Thresholds (env overrides)"
    ux_table_row "WSL_CHECK_DISK_WARN" "disk / mem / cpu warn % (default 90)"
    ux_table_row "WSL_CHECK_CDRIVE_MIN_GB" "host C: avail floor GB (default 10)"
    ux_table_row "WSL_CHECK_DOCKER_RECLAIM_GB" "auto-prune trigger GB (default 5)"
    ux_table_row "WSL_CHECK_AUTO_PRUNE" "1 = auto-prune on --all when over threshold"

    ux_section "vhdx Compaction (host-only)"
    ux_bullet "The WSL ext4.vhdx grows but never auto-shrinks: pruning inside"
    ux_bullet_sub "WSL frees the fs but not the host C: drive. '--all' shows the"
    ux_bullet_sub "reclaimable estimate; compact the vhdx to return it to Windows."
    ux_bullet "Run from the Windows host (PowerShell as admin) — NOT inside WSL,"
    ux_bullet_sub "since 'wsl --shutdown' terminates this very session:"
    ux_bullet_sub "wsl --shutdown"
    ux_bullet_sub "diskpart -> select vdisk file=\"...\\LocalState\\ext4.vhdx\""
    ux_bullet_sub "  attach vdisk readonly; compact vdisk; detach vdisk"
    ux_bullet "Or (newer builds): wsl --manage <distro> --set-sparse true"
    ux_bullet_sub "for auto-shrinking sparse mode."

    ux_section "Notes"
    ux_bullet "C: drive is shown first: a full WSL crash (SIGBUS) was caused by"
    ux_bullet_sub "the Windows host C: drive filling up, not the WSL disk (#897)."
    ux_bullet "The one-line summary also prints after a manual 'src' reload."
    ux_bullet "Prune is destructive and never runs in a non-interactive shell."
}

wsl_check_help() {
    case "${1:-}" in
    -h | --help | help | "") _wsl_check_help_summary ;;
    *) _wsl_check_help_summary ;;
    esac
}

alias wsl-check-help='wsl_check_help'
