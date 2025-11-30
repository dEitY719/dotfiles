#!/bin/bash

# mytool/uninstall-npm.sh
# Node.js & npm 제거 스크립트 (대화형)

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
  Node.js & npm 제거 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 WSL Ubuntu에서 Node.js와 npm을 제거합니다.
제거 과정:
  1. Node.js & npm 패키지 제거
  2. npm 글로벌 패키지 정리 (선택)
  3. npm 설정 디렉토리 정리 (선택)
  4. 제거 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}
${red}경고: npm 글로벌 패키지 및 설정이 삭제될 수 있습니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "제거가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Remove Node.js & npm packages
    # ========================================
    info "Step 1/4: Node.js & npm 패키지 제거 중..."

    if confirm "Node.js & npm을 제거하시겠습니까?"; then
        sudo apt-get remove -y nodejs npm || {
            warning "Node.js & npm 제거 중 일부 오류 발생"
        }
        success "Node.js & npm 패키지 제거 완료"
    else
        warning "Step 1 스킵됨"
    fi

    # ========================================
    # Step 2: Remove npm global packages
    # ========================================
    info "Step 2/4: npm 글로벌 패키지 정리 중..."

    if confirm "npm 글로벌 패키지를 모두 제거하시겠습니까?"; then
        if command -v npm &> /dev/null; then
            npm list -g --depth=0 || warning "npm 글로벌 패키지 목록 조회 실패"

            if confirm "위 패키지들을 모두 제거하시겠습니까?"; then
                local packages
                packages=$(npm list -g --depth=0 --parseable 2>/dev/null | grep -v npm$ | tail -n +2 || true)

                if [ -n "$packages" ]; then
                    npm uninstall -g $packages || {
                        warning "npm 글로벌 패키지 제거 중 오류 발생"
                    }
                    success "npm 글로벌 패키지 제거 완료"
                else
                    success "제거할 글로벌 패키지가 없습니다."
                fi
            fi
        else
            warning "npm이 설치되어 있지 않아 스킵되었습니다."
        fi
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Clean npm configuration
    # ========================================
    info "Step 3/4: npm 설정 디렉토리 정리 중..."

    if confirm "npm 설정 및 캐시 디렉토리를 제거하시겠습니까?"; then
        # npm 캐시 삭제
        if [ -d "$HOME/.npm" ]; then
            rm -rf "$HOME/.npm" || {
                warning "npm 캐시 디렉토리 삭제 실패"
            }
            success "npm 캐시 삭제 완료"
        fi

        # npm 설정 디렉토리 삭제
        if [ -d "$HOME/.npmrc" ]; then
            rm -f "$HOME/.npmrc" || {
                warning ".npmrc 파일 삭제 실패"
            }
            success ".npmrc 파일 삭제 완료"
        fi

        # npm 글로벌 경로 삭제
        if [ -d "$HOME/.npm-global" ]; then
            if confirm "npm 글로벌 경로 (${HOME}/.npm-global)를 삭제하시겠습니까? (데이터 손실 가능)"; then
                rm -rf "$HOME/.npm-global" || {
                    warning "npm 글로벌 경로 삭제 실패"
                }
                success "npm 글로벌 경로 삭제 완료"
            fi
        fi
    else
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Step 4: Verify uninstallation
    # ========================================
    info "Step 4/4: 제거 확인 중..."

    echo ""
    if command -v node &> /dev/null; then
        warning "node 명령어가 여전히 존재합니다."
    else
        success "Node.js가 성공적으로 제거되었습니다."
    fi

    if command -v npm &> /dev/null; then
        warning "npm 명령어가 여전히 존재합니다."
    else
        success "npm이 성공적으로 제거되었습니다."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Node.js & npm 제거 완료!
════════════════════════════════════════════════════${reset}

${bold}추가 정리 작업 (선택사항):${reset}
  1. npm 관련 패키지 자동 제거:
     ${yellow}sudo apt-get autoremove -y${reset}

  2. npm 의존성 전부 정리:
     ${yellow}sudo apt-get remove --auto-remove -y npm${reset}

${bold}참고:${reset}
  더 많은 npm 명령어는:
  ${yellow}npmhelp${reset}

EOF
}

main "$@"
