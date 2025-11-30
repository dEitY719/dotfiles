#!/bin/bash

# mytool/uninstall-gemini.sh
# Gemini CLI 제거 스크립트 (대화형)

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
  Gemini CLI 제거 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 npm을 이용하여 Gemini CLI를 제거합니다.
제거 과정:
  1. npm 설치 확인
  2. Gemini CLI 제거
  3. 제거 확인

${yellow}주의: npm 전역 패키지가 제거됩니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "제거가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Check npm
    # ========================================
    info "Step 1/3: npm 설치 확인 중..."

    if ! command -v npm &> /dev/null; then
        error "npm이 설치되어 있지 않습니다."
        return 1
    fi
    success "npm 설치됨: $(npm --version)"

    # ========================================
    # Step 2: Uninstall Gemini CLI
    # ========================================
    info "Step 2/3: Gemini CLI 제거 중..."

    if confirm "Gemini CLI (@google/gemini-cli)를 제거하시겠습니까?"; then
        npm uninstall -g @google/gemini-cli || {
            error "Gemini CLI 제거 실패"
            return 1
        }
        success "Gemini CLI 제거 완료"
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Verify uninstallation
    # ========================================
    info "Step 3/3: 제거 확인 중..."

    echo ""
    if command -v gemini &> /dev/null; then
        warning "gemini 명령어가 여전히 존재합니다."
        warning "PATH 설정을 확인하고 터미널을 다시 시작하세요."
    else
        success "Gemini CLI가 성공적으로 제거되었습니다."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Gemini CLI 제거 완료!
════════════════════════════════════════════════════${reset}

${bold}설치된 npm 전역 패키지 확인:${reset}
  ${yellow}npm list -g --depth=0${reset}

EOF
}

main "$@"
