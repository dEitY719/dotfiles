#!/bin/sh
# shell-common/functions/mirror_pages_activate_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

mirror_pages_activate_help() {
    ux_header "mirror-pages-activate"

    ux_section "Usage"
    ux_table_row "mirror-pages-activate" "activate Pages + replace URLs"
    ux_table_row "mirror-pages-activate --dry-run" "preview without making changes"
    ux_table_row "mirror-pages-activate --help" "show this help"
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

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help mirror_pages_activate_help "[Development] Activate GHE Pages + replace upstream URLs in README" development
