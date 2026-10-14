#!/bin/sh
# shell-common/functions/ghes_mirror_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ghes_mirror_help() {
    ux_header "ghes-mirror"

    ux_usage "ghes-mirror" "[-h|--help]" "Launch the interactive wizard; -h|--help shows this help."
    ux_section "What it does"
    ux_bullet "Clones a public GitHub repo (becomes upstream)"
    ux_bullet "Creates a mirror repo in your internal GHES instance"
    ux_bullet "Renames origin -> upstream, adds GHES as origin"
    ux_bullet "Pushes the default branch to GHES origin"

    ux_section "Resulting remotes"
    ux_bullet "origin    https://<ghes-host>/<user>/<repo>"
    ux_bullet "upstream  https://github.com/<owner>/<repo>"

    ux_section "Requirements"
    ux_bullet "git"
    ux_bullet "gh CLI authenticated to github.com  (gh auth login)"
    ux_bullet "gh CLI authenticated to GHES host   (gh auth login --hostname <host>)"

    ux_section "Notes"
    ux_bullet "ghes_mirror (shell function) leaves you inside the cloned repo;"
    ux_bullet "  the ghes-mirror executable on PATH only prints its path."
    ux_bullet "GHES repo visibility: --public (upstream is public; --internal is GHEC-only)."
}

alias ghes-mirror-help='ghes_mirror_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help ghes_mirror_help "[Development] Mirror public GitHub repo to internal GHES instance" development
