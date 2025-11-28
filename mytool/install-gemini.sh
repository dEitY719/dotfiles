#!/bin/bash

# mytool/install-gemini.sh
# Gemini CLI 설치 스크립트 (대화형)
# npm 전역 패키지: @google/gemini-cli

set -e

# Color definitions
bold=$(tput bold 2>/dev/null || echo "")
blue=$(tput setaf 4 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")
reset=$(tput sgr0 2>/dev/null || echo "")

# Helper functions
info() {
    echo "${bold}${blue}[INFO]${reset} $*"
}

success() {
    echo "${bold}${green}[✓]${reset} $*"
}

warning() {
    echo "${bold}${yellow}[⚠]${reset} $*"
}

error() {
    echo "${bold}${red}[✗]${reset} $*"
}

confirm() {
    local prompt="$1"
    local response
    echo -n "${bold}${blue}${prompt}${reset} (y/n) "
    read -r response
    [[ "$response" == "y" || "$response" == "Y" ]]
}

# Main script
main() {
    clear
    cat <<EOF
${bold}${blue}════════════════════════════════════════════════════
  Gemini CLI 설치 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 npm을 이용하여 Gemini CLI를 설치합니다.
설치 과정:
  1. Node.js/npm 설치 확인
  2. npm 전역 경로 설정 (최초 1회)
  3. Gemini CLI npm 패키지 설치
  4. 설치 확인

${yellow}주의: npm이 설치되어 있어야 합니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설치가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Check Node.js & npm
    # ========================================
    info "Step 1/4: Node.js & npm 설치 확인 중..."

    if ! command -v node &> /dev/null; then
        error "Node.js가 설치되어 있지 않습니다."
        return 1
    fi
    success "Node.js 설치됨: $(node --version)"

    if ! command -v npm &> /dev/null; then
        error "npm이 설치되어 있지 않습니다."
        return 1
    fi
    success "npm 설치됨: $(npm --version)"

    # ========================================
    # Step 2: Configure npm global path
    # ========================================
    info "Step 2/4: npm 전역 경로 설정 중..."

    local npm_prefix="$HOME/.npm-global"

    if confirm "npm 전역 경로를 ${npm_prefix}로 설정하시겠습니까?"; then
        mkdir -p "$npm_prefix"
        npm config set prefix "$npm_prefix" || {
            error "npm 전역 경로 설정 실패"
            return 1
        }
        success "npm 전역 경로 설정 완료: $npm_prefix"

        # PATH 설정 확인
        if ! echo "$PATH" | grep -q "$npm_prefix/bin"; then
            warning "PATH에 ${npm_prefix}/bin이 없습니다."
            warning "~/.bashrc 또는 ~/.bash_profile에 다음을 추가하세요:"
            echo "  ${yellow}export PATH=\"\$HOME/.npm-global/bin:\$PATH\"${reset}"
        fi
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Install Gemini CLI
    # ========================================
    info "Step 3/4: Gemini CLI 설치 중..."

    if confirm "Gemini CLI (@google/gemini-cli)를 설치하시겠습니까?"; then
        npm install -g @google/gemini-cli || {
            error "Gemini CLI 설치 실패"
            return 1
        }
        success "Gemini CLI 설치 완료"
    else
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Step 4: Verify installation
    # ========================================
    info "Step 4/4: 설치 확인 중..."

    echo ""
    echo "${bold}Gemini 버전:${reset}"
    if command -v gemini &> /dev/null; then
        gemini --version || warning "Gemini 버전 확인 실패"
    else
        warning "gemini 명령어를 찾을 수 없습니다."
        warning "PATH 설정을 확인하고 터미널을 다시 시작하세요."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Gemini CLI 설치 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. PATH 설정 확인 (필요시): ${yellow}echo \$PATH${reset}
  2. Gemini 도움말: ${yellow}gemini --help${reset}
  3. Gemini 설정 확인: ${yellow}gemini --version${reset}

${bold}더 많은 Gemini 명령어는:${reset}
  ${yellow}geminihelp${reset}

EOF
}

main "$@"
