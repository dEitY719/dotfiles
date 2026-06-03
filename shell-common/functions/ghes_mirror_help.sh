#!/bin/sh
# shell-common/functions/ghes_mirror_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ghes_mirror_help() {
    ux_header "ghes-mirror"

    ux_section "Usage"
    echo "  ${UX_SUCCESS}ghes-mirror${UX_RESET}         ${UX_MUTED}# launch interactive wizard${UX_RESET}"
    echo "  ${UX_SUCCESS}ghes-mirror --help${UX_RESET}  ${UX_MUTED}# show this help${UX_RESET}"
    echo ""

    ux_section "What it does"
    ux_bullet "Clones a public GitHub repo (becomes upstream)"
    ux_bullet "Creates a mirror repo in your internal GHES instance"
    ux_bullet "Renames origin -> upstream, adds GHES as origin"
    ux_bullet "Pushes the default branch to GHES origin"
    echo ""

    ux_section "Resulting remotes"
    echo "  ${UX_INFO}origin    https://<ghes-host>/<user>/<repo>${UX_RESET}"
    echo "  ${UX_INFO}upstream  https://github.com/<owner>/<repo>${UX_RESET}"
    echo ""

    ux_section "Requirements"
    ux_bullet "git"
    ux_bullet "gh CLI authenticated to github.com  (gh auth login)"
    ux_bullet "gh CLI authenticated to GHES host   (gh auth login --hostname <host>)"
    echo ""

    ux_section "Notes"
    ux_bullet "The wizard changes your working directory to the cloned repo."
    ux_bullet "GHES repo visibility: --public (upstream is public; --internal is GHEC-only)."
    echo ""
}

alias ghes-mirror-help='ghes_mirror_help'
