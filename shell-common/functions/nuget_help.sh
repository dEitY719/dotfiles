#!/bin/sh
# shell-common/functions/nuget_help.sh
# NuGet check wrapper - shared between bash and zsh

# NuGet Check Wrapper - calls the diagnostic script
nuget_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_nuget.sh" "$@"
}

alias check-nuget='nuget_check'
