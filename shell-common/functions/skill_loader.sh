#!/bin/sh
# shell-common/functions/skill_loader.sh
# Cross-CLI skill loader for Claude Code, Codex, Gemini, etc.
# Thin wrapper (#2195): the logic is the PATH executable
# shell-common/tools/custom/skill_loader.sh (~/.local/bin/skill-loader).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

skill_loader() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/skill_loader.sh
    "$_exe" "$@"
}

# Alias for skill-loader format (using dash instead of underscore)
alias skill-loader='skill_loader'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func skill_loader "Load skills into an agent harness"
