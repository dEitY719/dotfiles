#!/bin/bash

# mytool/enable-docker.sh
# Docker 서비스 자동 시작 설정 (systemd) - 대화형

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
  Docker 서비스 자동 시작 설정 (systemd)
════════════════════════════════════════════════════${reset}

이 스크립트는 Docker 서비스를 WSL 부팅 시
자동으로 시작되도록 설정합니다.

설정 과정:
  1. Docker 서비스 시작
  2. Docker 자동 시작 활성화 (systemd enable)
  3. 설정 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설정이 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Check if Docker is installed
    # ========================================
    info "Docker 설치 상태 확인 중..."
    if ! command -v docker &> /dev/null; then
        error "Docker가 설치되어 있지 않습니다."
        echo "${yellow}먼저 'dinstall'을 실행하여 Docker를 설치하세요.${reset}"
        exit 1
    fi
    success "Docker가 설치되어 있습니다."

    # ========================================
    # Step 1: Start Docker service
    # ========================================
    info "Step 1/3: Docker 서비스 시작 중..."
    if confirm "Docker 서비스를 시작하시겠습니까?"; then
        if sudo systemctl start docker; then
            success "Docker 서비스 시작 완료"
        else
            error "Docker 서비스 시작 실패"
            return 1
        fi
    else
        warning "Step 1 스킵됨"
    fi

    # ========================================
    # Step 2: Enable Docker to start on boot
    # ========================================
    info "Step 2/3: Docker 자동 시작 활성화 중..."
    if confirm "Docker를 WSL 부팅 시 자동 시작하도록 설정하시겠습니까?"; then
        if sudo systemctl enable docker; then
            success "Docker 자동 시작 활성화 완료"
        else
            error "Docker 자동 시작 활성화 실패"
            return 1
        fi
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Verify Docker is running
    # ========================================
    info "Step 3/3: Docker 서비스 상태 확인 중..."
    if confirm "Docker 서비스 상태를 확인하시겠습니까?";  then
        echo ""
        echo "${bold}Docker 서비스 상태:${reset}"
        if sudo systemctl status docker --no-pager; then
            echo ""
            success "Docker 서비스가 정상 실행 중입니다."
        else
            warning "Docker 서비스 상태 확인 실패"
        fi
    else
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Docker 자동 시작 설정 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. WSL 재시작: ${yellow}wsl --shutdown${reset}
  2. WSL 다시 시작 후 Docker 자동 실행 확인:
     ${yellow}docker ps${reset}

${bold}Docker 상태 확인:${reset}
  - 서비스 상태: ${yellow}sudo systemctl status docker${reset}
  - 자동 시작 설정: ${yellow}sudo systemctl is-enabled docker${reset}

${bold}더 많은 Docker 명령어는:${reset}
  ${yellow}dockerhelp${reset}

EOF
}

main "$@"
