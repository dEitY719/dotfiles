#!/bin/bash

# mytool/install-git-secret.sh
# git-secret 설치 스크립트 (GPG 기반 비밀 관리)

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

main() {
    clear
    cat <<EOF
${bold}${blue}════════════════════════════════════════════════════
  git-secret 설치 스크립트
════════════════════════════════════════════════════${reset}

이 스크립트는 apt 패키지 관리자를 사용하여 git-secret을 설치합니다.
설치 과정:
  1. git 및 gpg 의존성 확인
  2. apt 저장소 업데이트 (옵션)
  3. git-secret 패키지 설치
  4. 설치 확인

${yellow}주의: sudo 권한이 필요할 수 있습니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설치가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Check dependencies
    # ========================================
    info "Step 1/4: git 및 gpg 의존성 확인 중..."

    if ! command -v git &>/dev/null; then
        error "git이 설치되어 있지 않습니다."
        warning "apt-get install git 또는 mytool/install-git.sh (미제공) 등을 통해 설치해주세요."
        exit 1
    fi
    success "git 설치됨: $(git --version)"

    if ! command -v gpg &>/dev/null; then
        error "gpg가 설치되어 있지 않습니다."
        warning "apt-get install gnupg 로 설치 후 다시 시도하세요."
        exit 1
    fi
    success "gpg 설치됨: $(gpg --version | head -n 1)"

    # ========================================
    # Step 2: Update apt (optional)
    # ========================================
    info "Step 2/4: apt 저장소 업데이트 여부 확인..."
    if confirm "apt-get update 를 먼저 실행할까요?"; then
        if sudo -n true 2>/dev/null; then
            sudo apt-get update
        else
            warning "sudo 인증 필요. 비밀번호를 입력해야 할 수 있습니다."
            sudo apt-get update
        fi
        success "apt-get update 완료"
    else
        warning "apt-get update 스킵됨"
    fi

    # ========================================
    # Step 3: Install git-secret
    # ========================================
    info "Step 3/4: git-secret 설치 중..."

    if command -v git-secret &>/dev/null; then
        warning "git-secret이 이미 설치되어 있습니다."
        if ! confirm "재설치/업데이트 하시겠습니까?"; then
            info "설치를 건너뜁니다."
        else
            sudo apt-get install -y git-secret
            success "git-secret 재설치/업데이트 완료"
        fi
    else
        sudo apt-get install -y git-secret
        success "git-secret 설치 완료"
    fi

    # ========================================
    # Step 4: Verify installation
    # ========================================
    info "Step 4/4: 설치 확인 중..."

    echo ""
    echo "${bold}git-secret 버전:${reset}"
    if command -v git-secret &>/dev/null; then
        git-secret --version || warning "버전 확인 실패"
    else
        error "git-secret 명령어를 찾을 수 없습니다. PATH 또는 설치 상태를 확인하세요."
        exit 1
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ git-secret 설치 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. GPG 공개키/개인키 준비: ${yellow}gpg --full-generate-key${reset}
  2. dotfiles 도움말: ${yellow}gshelp${reset}
  3. 기존 Git 리포지토리에서 git-secret 초기화: ${yellow}git secret init${reset}

EOF
}

main "$@"
