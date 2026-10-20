#!/bin/sh
# shell-common/functions/gh_project_pat.sh
# gh-project-pat — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/gh_project_pat.sh (also ~/.local/bin/gh-project-pat); this keeps the
# `gh_project_pat` / `gh-project-pat` names and tab completion in interactive shells.
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

gh_project_pat() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/gh_project_pat.sh "$@"
}

alias gh-project-pat='gh_project_pat'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func gh_project_pat "PROJECT_BOARD_PAT guide + multi-repo secret set/status"
