#!/bin/sh
# shell-common/functions/mirror_pages_activate_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

mirror_pages_activate_help() {
    ux_header "mirror-pages-activate"

    ux_section "Usage"
    echo "  ${UX_SUCCESS}mirror-pages-activate${UX_RESET}           ${UX_MUTED}# activate Pages + replace URLs${UX_RESET}"
    echo "  ${UX_SUCCESS}mirror-pages-activate --dry-run${UX_RESET} ${UX_MUTED}# preview without making changes${UX_RESET}"
    echo "  ${UX_SUCCESS}mirror-pages-activate --help${UX_RESET}    ${UX_MUTED}# show this help${UX_RESET}"
    echo ""

    ux_section "What it does"
    ux_bullet "Activates GitHub Pages on the GHE origin repo (branch=main, path=/docs)"
    ux_bullet "Replaces upstream github.io Pages URLs in README.md with the GHE Pages URL"
    echo ""

    ux_section "Requirements"
    ux_bullet "Run from inside a mirrored repo (set up by ghes-mirror)"
    ux_bullet "origin   = GHE mirror  (https://<ghe-host>/owner/repo)"
    ux_bullet "upstream = github.com source"
    ux_bullet "gh CLI authenticated to the GHE host  (gh auth login --hostname <host>)"
    echo ""

    ux_section "See also"
    ux_bullet "ghes-mirror — clone + mirror a public GitHub repo to GHES"
    echo ""
}

alias mirror-pages-activate-help='mirror_pages_activate_help'
