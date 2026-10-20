#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/gh_audit_builtin_workflows.sh
# gh-audit-builtin-workflows — thin wrappers (#2155). The audit is the PATH
# executable tools/custom/gh_audit_builtin_workflows.sh (also
# ~/.local/bin/gh-audit-builtin-workflows); these keep the function/alias names.

gh_audit_builtin_workflows() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/gh_audit_builtin_workflows.sh "$@"
}

gh_audit_builtin_workflows_help() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/gh_audit_builtin_workflows.sh --help
}

alias gh-audit-builtin-workflows='gh_audit_builtin_workflows'
alias gh-audit-builtin-workflows-help='gh_audit_builtin_workflows_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help gh_audit_builtin_workflows_help "[Development] gh audit-builtin-workflows scan"
_register_func gh_audit_builtin_workflows "Audit built-in GitHub workflows"
