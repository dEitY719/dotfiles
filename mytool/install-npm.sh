#!/bin/bash

# mytool/install-npm.sh
# Node.js & npm 설치 스크립트 (대화형)

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
  Node.js & npm 설치 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 WSL Ubuntu에 Node.js와 npm을 설치합니다.
설치 과정:
  1. 패키지 매니저 업데이트
  2. Node.js & npm 설치
  3. npm 전역 경로 설정
  4. PATH 설정
  5. 설치 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설치가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Update package manager
    # ========================================
    info "Step 1/5: 패키지 매니저 업데이트 중..."
    if confirm "apt-get update를 실행하시겠습니까?"; then
        sudo apt-get update || {
            error "apt-get update 실패"
            return 1
        }
        success "패키지 매니저 업데이트 완료"
    else
        warning "Step 1 스킵됨"
    fi

    # ========================================
    # Step 2: Install Node.js & npm
    # ========================================
    info "Step 2/5: Node.js & npm 설치 중..."
    if confirm "Node.js & npm을 설치하시겠습니까?"; then
        sudo apt-get install -y nodejs npm || {
            error "Node.js & npm 설치 실패"
            return 1
        }
        success "Node.js & npm 설치 완료"
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Configure npm global path
    # ========================================
    info "Step 3/5: npm 전역 경로 설정 중..."

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
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Step 4: Update npm itself
    # ========================================
    info "Step 4/5: npm 자체 업그레이드 중..."
    if confirm "npm 자체를 최신 버전으로 업그레이드하시겠습니까?"; then
        npm install -g npm || {
            warning "npm 업그레이드 실패 (선택사항)"
        }
        success "npm 업그레이드 완료"
    else
        warning "Step 4 스킵됨"
    fi

    # ========================================
    # Step 5: Verify installation
    # ========================================
    info "Step 5/5: 설치 확인 중..."

    echo ""
    echo "${bold}Node.js 버전:${reset}"
    node --version || warning "Node.js 버전 확인 실패"

    echo ""
    echo "${bold}npm 버전:${reset}"
    npm --version || warning "npm 버전 확인 실패"

    echo ""
    echo "${bold}npm 설정 (prefix):${reset}"
    npm config get prefix || warning "npm prefix 확인 실패"

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Node.js & npm 설치 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. 글로벌 패키지 경로 확인: ${yellow}npm list -g --depth=0${reset}
  2. 유용한 전역 패키지 설치:
     ${yellow}npm install -g typescript${reset}
     ${yellow}npm install -g @angular/cli${reset}
     ${yellow}npm install -g create-react-app${reset}

${bold}더 많은 npm 명령어는:${reset}
  ${yellow}npmhelp${reset}

EOF
}

main "$@"
