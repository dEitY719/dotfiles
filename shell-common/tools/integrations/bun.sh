#!/bin/sh
# shell-common/tools/integrations/bun.sh
# Bun JavaScript runtime - PATH setup, install helpers, and aliases
#
# Configuration:
#   ~/.bunfig.toml is managed as a symlink to bun/bunfig.toml.{environment}
#   Run ./shell-common/setup.sh to configure for your environment

# ========================================
# Load UX Library
# ========================================
if ! type ux_header >/dev/null 2>&1; then
    _bun_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_bun_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _bun_dir
fi

# NOTE: $HOME/.bun/bin PATH is managed by env/path.sh (SSOT)

# ========================================
# Bun Aliases
# ========================================
alias bun-v='bun --version'
alias bun-i='bun install'
alias bun-id='bun install --dev'
alias bun-ig='bun install --global'
alias bun-un='bun remove'
alias bun-run='bun run'
alias bun-update='bun update'
alias bun-outdated='bun outdated'

# ========================================
# Install / Uninstall
# ========================================

install_bun() {
    ux_header "Bun 설치"
    echo ""

    if command -v bun >/dev/null 2>&1; then
        ux_success "Bun이 이미 설치되어 있습니다: $(bun --version)"
        echo ""
        return 0
    fi

    ux_info "공식 설치 스크립트 실행 중..."
    curl -fsSL https://bun.sh/install | bash

    # Reload PATH for current session
    export PATH="$HOME/.bun/bin:$PATH"

    if command -v bun >/dev/null 2>&1; then
        echo ""
        ux_success "Bun 설치 완료: $(bun --version)"
        ux_info "새 셸을 열거나 'source ~/.bashrc' 실행 후 사용하세요"
    else
        ux_error "설치 후에도 bun을 찾을 수 없습니다"
        ux_info "PATH에 ~/.bun/bin이 포함되어 있는지 확인하세요"
        return 1
    fi
    echo ""
}

uninstall_bun() {
    ux_header "Bun 제거"
    echo ""

    printf "%sBun을 제거하시겠습니까? (y/N): %s" "$UX_PRIMARY" "$UX_RESET"
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        ux_info "제거 취소됨"
        return 0
    fi
    echo ""

    if [ -d "$HOME/.bun" ]; then
        ux_info "~/.bun 디렉토리 제거 중..."
        rm -rf "$HOME/.bun"
        ux_success "Bun 제거 완료"
    else
        ux_info "Bun 설치 디렉토리를 찾을 수 없습니다: ~/.bun"
    fi

    if [ -f "$HOME/.bunfig.toml" ] || [ -L "$HOME/.bunfig.toml" ]; then
        ux_info "~/.bunfig.toml 제거 중..."
        rm -f "$HOME/.bunfig.toml"
        ux_success "bunfig.toml 제거 완료"
    fi
    echo ""

    ux_header "Bun 제거 완료"
    ux_info "재설치: install-bun"
    echo ""
}

# ========================================
# Aliases
# ========================================
alias install-bun='install_bun'
alias uninstall-bun='uninstall_bun'
