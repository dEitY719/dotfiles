#!/bin/sh
# shell-common/functions/mytool.sh
# MyTool - Personal Utility Functions (POSIX-compatible)
# Shared between bash and zsh

# 하드웨어 정보 표시 함수
get_hw_info() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/get_hw_info.sh"
    if [ ! -f "$script" ]; then
        echo "Error: Hardware info script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# 소스 번들링 함수
srcpack() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/srcpack.py"
    if [ ! -f "$script" ]; then
        echo "not found: $script" >&2
        return 2
    fi
    python "$script" "$@"
}

# AGENTS.md 생성 함수
agents_init() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/run_agents_md_master_prompt.sh"
    if [ ! -f "$script" ]; then
        echo "Error: AGENTS.md generation script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# Powerlevel10k 설치 함수
install_p10k() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_p10k.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-p10k script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fzf (fuzzy finder) 설치 함수
install_fzf() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fzf.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fzf script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fasd (fast access to directories/files) 설치 함수
install_fasd() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fasd.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fasd script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# ripgrep (fast text search) 설치 함수
install_ripgrep() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_ripgrep.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-ripgrep script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fd (fast file finder) 설치 함수
install_fd() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_fd.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fd script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# bat (cat with syntax highlighting) 설치 함수
install_bat() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_bat.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-bat script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# pet (command snippet manager) 설치 함수
install_pet() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_pet.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-pet script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# zsh-autosuggestions (command history suggestions) 설치 함수
install_zsh_autosuggestions() {
    local script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_zsh_autosuggestions.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-zsh-autosuggestions script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

alias install-zsh-autosuggestions='install_zsh_autosuggestions'
