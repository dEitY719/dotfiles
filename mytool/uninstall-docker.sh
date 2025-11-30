#!/bin/bash

# mytool/uninstall-docker.sh
# WSL Docker 제거 스크립트 (대화형)

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
  WSL Docker 제거 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 WSL Ubuntu에서 Docker를 제거합니다.
제거 과정:
  1. Docker 패키지 제거
  2. Docker 저장소 및 GPG 키 제거 (선택)
  3. docker 그룹 제거 (선택)
  4. 제거 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}
${red}경고: Docker 데이터는 백업되지 않습니다. 필요하면 사전에 백업하세요.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "제거가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Remove Docker packages
    # ========================================
    info "Step 1/4: Docker 패키지 제거 중..."

    if confirm "Docker Engine, CLI, Compose를 제거하시겠습니까?"; then
        sudo apt-get remove -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-compose-plugin || {
            warning "Docker 패키지 제거 중 일부 오류 발생"
        }
        success "Docker 패키지 제거 완료"
    else
        warning "Step 1 스킵됨"
    fi

    # ========================================
    # Step 2: Remove Docker repository and GPG key
    # ========================================
    info "Step 2/4: Docker 저장소 및 GPG 키 제거 중..."

    if confirm "Docker 저장소 및 GPG 키를 제거하시겠습니까?"; then
        if [ -f /etc/apt/sources.list.d/docker.list ]; then
            sudo rm -f /etc/apt/sources.list.d/docker.list || {
                error "Docker 저장소 파일 삭제 실패"
                return 1
            }
            success "Docker 저장소 파일 제거 완료"
        fi

        if [ -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
            sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg || {
                error "Docker GPG 키 삭제 실패"
                return 1
            }
            success "Docker GPG 키 제거 완료"
        fi

        info "패키지 매니저 업데이트 중..."
        sudo apt-get update || warning "apt-get update 실패"
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Remove docker group
    # ========================================
    info "Step 3/4: docker 그룹 제거 중..."

    if confirm "docker 그룹을 제거하시겠습니까?"; then
        if getent group docker > /dev/null; then
            sudo groupdel docker || {
                warning "docker 그룹 삭제 실패 (사용자가 여전히 소속되어 있을 수 있음)"
            }
            success "docker 그룹 제거 완료"
        else
            success "docker 그룹이 없습니다."
        fi
    else
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Step 4: Verify uninstallation
    # ========================================
    info "Step 4/4: 제거 확인 중..."

    echo ""
    if command -v docker &> /dev/null; then
        warning "docker 명령어가 여전히 존재합니다."
    else
        success "Docker가 성공적으로 제거되었습니다."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Docker 제거 완료!
════════════════════════════════════════════════════${reset}

${bold}추가 정리 작업 (선택사항):${reset}
  1. Docker 캐시 데이터 제거:
     ${yellow}sudo rm -rf /var/lib/docker${reset}

  2. 모든 Docker 관련 설정 제거:
     ${yellow}sudo rm -rf /etc/docker${reset}

  3. Docker 설정 디렉토리 제거:
     ${yellow}rm -rf ~/.docker${reset}

${bold}참고:${reset}
  더 많은 Docker 명령어는:
  ${yellow}dockerhelp${reset}

EOF
}

main "$@"
