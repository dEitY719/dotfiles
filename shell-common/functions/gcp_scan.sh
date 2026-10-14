#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/gcp_scan.sh — `gcp scan` wrapper (#2155). The scanner is
# the PATH executable tools/custom/gcp_scan.sh (also ~/.local/bin/gcp-scan); the
# gcp dispatcher and the deprecated gcp_scan/gcp-scan aliases (gcp.sh) call this.
_gcp_scan() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/gcp_scan.sh" "$@"
}
