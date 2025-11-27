#!/bin/bash

# mytool/install-docker.sh
# WSL Docker 설치 스크립트 (대화형)

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
  WSL Docker 설치 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 WSL Ubuntu에 Docker를 설치합니다.
설치 과정:
  1. 패키지 매니저 업데이트
  2. Docker 의존성 설치
  3. Docker 공식 GPG 키 추가
  4. Docker 저장소 추가
  5. Docker Engine & Compose 설치
  6. 설치 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설치가 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Update package manager
    # ========================================
    info "Step 1/6: 패키지 매니저 업데이트 중..."
    if confirm "apt-get update를 실행하시겠습니까?"; then
        sudo apt-get update || {
            error "apt-get update 실패"
            return 1
        }
        success "패키지 매니저 업데이트 완료"
    else
        warning "Step 1 스킵됨"
    fi

    if confirm "apt-get upgrade를 실행하시겠습니까?"; then
        sudo apt-get upgrade -y || {
            error "apt-get upgrade 실패"
            return 1
        }
        success "패키지 업그레이드 완료"
    else
        warning "apt-get upgrade 스킵됨"
    fi

    # ========================================
    # Step 2: Install Docker dependencies
    # ========================================
    info "Step 2/6: Docker 의존성 설치 중..."
    if confirm "Docker 의존성을 설치하시겠습니까?"; then
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release || {
            error "Docker 의존성 설치 실패"
            return 1
        }
        success "Docker 의존성 설치 완료"
    else
        warning "Step 2 스킵됨"
    fi

    # ========================================
    # Step 3: Add Docker's official GPG key
    # ========================================
    info "Step 3/6: Docker GPG 키 추가 중..."
    if confirm "Docker 공식 GPG 키를 추가하시겠습니까?"; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
            error "GPG 키 추가 실패"
            return 1
        }
        success "Docker GPG 키 추가 완료"
    else
        warning "Step 3 스킵됨"
    fi

    # ========================================
    # Step 4: Add Docker repository
    # ========================================
    info "Step 4/6: Docker 저장소 추가 중..."
    if confirm "Docker 저장소를 추가하시겠습니까?"; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || {
            error "Docker 저장소 추가 실패"
            return 1
        }
        success "Docker 저장소 추가 완료"

        info "저장소 설정 확인:"
        cat /etc/apt/sources.list.d/docker.list
    else
        warning "Step 4 스킵됨"
    fi

    # ========================================
    # Step 5: Update & Install Docker
    # ========================================
    info "Step 5/6: apt-get 업데이트 후 Docker 설치 중..."
    if confirm "apt-get update (Docker 저장소 반영)를 실행하시겠습니까?"; then
        sudo apt-get update || {
            error "apt-get update 실패"
            return 1
        }
        success "패키지 매니저 업데이트 완료"
    else
        warning "apt-get update 스킵됨"
    fi

    if confirm "Docker Engine, CLI, Compose를 설치하시겠습니까?"; then
        sudo apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-compose-plugin || {
            error "Docker 설치 실패"
            return 1
        }
        success "Docker 설치 완료"
    else
        warning "Docker 설치 스킵됨"
    fi

    # ========================================
    # Step 6: Verify installation
    # ========================================
    info "Step 6/6: 설치 확인 중..."

    echo ""
    echo "${bold}Docker 버전:${reset}"
    docker --version || warning "Docker 버전 확인 실패"

    echo ""
    echo "${bold}Docker Compose 버전:${reset}"
    docker compose version || warning "Docker Compose 버전 확인 실패"

    # ========================================
    # Post-installation (optional)
    # ========================================
    echo ""
    if confirm "Docker를 sudo 없이 사용하도록 설정하시겠습니까? (권장)"; then
        info "docker 그룹 생성 및 현재 사용자 추가 중..."
        sudo groupadd -f docker || true
        sudo usermod -aG docker "$USER" || {
            error "사용자를 docker 그룹에 추가 실패"
            return 1
        }
        success "docker 그룹 설정 완료"
        warning "설정을 적용하려면 WSL을 재시작하거나 다음을 실행하세요:"
        echo "  newgrp docker"
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Docker 설치 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. 필요시 WSL 재시작: ${yellow}wsl --shutdown${reset}
  2. Docker 테스트: ${yellow}docker run hello-world${reset}
  3. Docker Compose 테스트: ${yellow}docker compose version${reset}

${bold}더 많은 Docker 명령어는:${reset}
  ${yellow}dockerhelp${reset}

EOF
}

main "$@"
