#!/bin/sh
# shell-common/functions/mytool.sh
# MyTool - Personal Utility Functions (POSIX-compatible)
# Shared between bash and zsh

# 하드웨어 정보 표시 함수

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

get_hw_info() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/get_hw_info.sh"
    if [ ! -f "$script" ]; then
        ux_error "Hardware info script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# 소스 번들링 함수
srcpack() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/srcpack.py"
    if [ ! -f "$script" ]; then
        ux_error "srcpack script not found: $script"
        return 2
    fi
    python "$script" "$@"
}

# AGENTS.md 생성 함수
agents_init() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/run_agents_md_master_prompt.sh"
    if [ ! -f "$script" ]; then
        ux_error "AGENTS.md generation script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# Powerlevel10k 설치 함수
install_p10k() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_p10k.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-p10k script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# fzf (fuzzy finder) 설치 함수
install_fzf() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fzf.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-fzf script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# fasd (fast access to directories/files) 설치 함수
install_fasd() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fasd.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-fasd script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# ripgrep (fast text search) 설치 함수
install_ripgrep() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_ripgrep.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-ripgrep script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# fd (fast file finder) 설치 함수
install_fd() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fd.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-fd script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# bat (cat with syntax highlighting) 설치 함수
install_bat() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_bat.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-bat script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# pet (command snippet manager) 설치 함수
install_pet() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_pet.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-pet script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# zsh-autosuggestions (command history suggestions) 설치 함수
install_zsh_autosuggestions() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_zsh_autosuggestions.sh"
    if [ ! -f "$script" ]; then
        ux_error "install-zsh-autosuggestions script not found: $script"
        return 2
    fi
    bash "$script" "$@"
}

# Dash-form aliases (command-design-pattern.md R1: user-facing = dash-form).
# `srcpack` has no underscore, so it is already the dash-form entry point.
alias get-hw-info='get_hw_info'
alias agents-init='agents_init'
alias install-p10k='install_p10k'
alias install-fzf='install_fzf'
alias install-fasd='install_fasd'
alias install-ripgrep='install_ripgrep'
alias install-fd='install_fd'
alias install-bat='install_bat'
alias install-pet='install_pet'
alias install-zsh-autosuggestions='install_zsh_autosuggestions'
