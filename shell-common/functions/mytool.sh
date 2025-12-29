#!/bin/sh
# shell-common/functions/mytool.sh
# MyTool - Personal Utility Functions (POSIX-compatible)
# Shared between bash and zsh

# 하드웨어 정보 표시 함수
get_hw_info() {
    local script="$HOME/dotfiles/mytool/get_hw_info.sh"
    if [ ! -f "$script" ]; then
        echo "Error: Hardware info script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# 소스 번들링 함수
srcpack() {
    local script="$HOME/dotfiles/mytool/srcpack.py"
    if [ ! -f "$script" ]; then
        echo "not found: $script" >&2
        return 2
    fi
    python "$script" "$@"
}

# AGENTS.md 생성 함수
agents_init() {
    local script="$HOME/dotfiles/mytool/run-AGENTS_md_Master_Prompt.sh"
    if [ ! -f "$script" ]; then
        echo "Error: AGENTS.md generation script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# Powerlevel10k 설치 함수
install-p10k() {
    local script="$HOME/dotfiles/mytool/install-p10k.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-p10k script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fzf (fuzzy finder) 설치 함수
install-fzf() {
    local script="$HOME/dotfiles/mytool/install-fzf.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fzf script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fasd (fast access to directories/files) 설치 함수
install-fasd() {
    local script="$HOME/dotfiles/mytool/install-fasd.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fasd script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# ripgrep (fast text search) 설치 함수
install-ripgrep() {
    local script="$HOME/dotfiles/mytool/install-ripgrep.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-ripgrep script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# fd (fast file finder) 설치 함수
install-fd() {
    local script="$HOME/dotfiles/mytool/install-fd.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-fd script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# bat (cat with syntax highlighting) 설치 함수
install-bat() {
    local script="$HOME/dotfiles/mytool/install-bat.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-bat script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# pet (command snippet manager) 설치 함수
install-pet() {
    local script="$HOME/dotfiles/mytool/install-pet.sh"
    if [ ! -f "$script" ]; then
        echo "Error: install-pet script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}
