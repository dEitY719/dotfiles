#!/bin/sh
# shell-common/functions/apt_help.sh
# APT check wrapper - shared between bash and zsh

# APT Check Wrapper - calls the diagnostic script
apt_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_apt.sh" "$@"
}

alias check-apt='apt_check'
