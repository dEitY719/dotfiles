#!/bin/sh
# shell-common/functions/cargo_help.sh
# Cargo check wrapper - shared between bash and zsh

# Cargo Check Wrapper - calls the diagnostic script
cargo_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_cargo.sh" "$@"
}

alias check-cargo='cargo_check'
