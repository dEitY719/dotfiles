#!/bin/sh
# shell-common/functions/rpm_help.sh
# RPM check wrapper - shared between bash and zsh

# RPM Check Wrapper - calls the diagnostic script
rpm_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_rpm.sh" "$@"
}

alias check-rpm='rpm_check'
