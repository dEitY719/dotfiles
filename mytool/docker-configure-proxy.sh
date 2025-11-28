#!/bin/bash

# mytool/docker-configure-proxy.sh
# Docker Proxy 설정 스크립트 (대화형)
# 회사 프록시(Corporate Proxy)가 필요한 환경에서 systemd를 통해 Docker에 proxy 설정

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
  Docker 회사 프록시(Corporate Proxy) 설정
════════════════════════════════════════════════════${reset}

이 스크립트는 Docker가 회사 프록시를 통해
인터넷에 접근할 수 있도록 설정합니다.

설정 과정:
  1. Proxy 설정 정보 입력
  2. systemd service drop-in 디렉토리 생성
  3. http-proxy.conf 파일 생성
  4. systemd daemon 재로드 및 Docker 재시작
  5. 설정 확인

${yellow}주의: 이 스크립트는 sudo 권한이 필요합니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설정이 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Check Docker installation
    # ========================================
    info "Step 1/5: Docker 설치 확인 중..."

    if ! command -v docker &> /dev/null; then
        error "Docker가 설치되어 있지 않습니다."
        error "먼저 Docker를 설치하세요: dinstall"
        return 1
    fi
    success "Docker 설치됨: $(docker --version)"

    # ========================================
    # Step 2: Get proxy information from user
    # ========================================
    info "Step 2/5: Proxy 설정 정보 입력"
    echo ""

    local http_proxy https_proxy no_proxy

    echo "${bold}HTTP/HTTPS Proxy URL:${reset}"
    read -p "  예) http://12.26.204.100:8080/ : " http_proxy

    if [ -z "$http_proxy" ]; then
        error "Proxy URL이 필요합니다."
        return 1
    fi

    https_proxy="$http_proxy"

    echo ""
    echo "${bold}NO_PROXY (쉼표로 구분, 선택사항):${reset}"
    echo "  예) localhost,127.0.0.1,.company.com,10.0.0.0/8"
    read -p "  입력 (비워둘 수 있음): " no_proxy

    # ========================================
    # Step 3: Create systemd drop-in directory
    # ========================================
    info "Step 3/5: systemd service drop-in 디렉토리 생성 중..."

    local drop_in_dir="/etc/systemd/system/docker.service.d"

    if ! sudo mkdir -p "$drop_in_dir"; then
        error "디렉토리 생성 실패: $drop_in_dir"
        return 1
    fi
    success "디렉토리 생성 완료: $drop_in_dir"

    # ========================================
    # Step 4: Create http-proxy.conf file
    # ========================================
    info "Step 4/5: http-proxy.conf 파일 생성 중..."

    cat <<PROXY_CONF | sudo tee "$drop_in_dir/http-proxy.conf" > /dev/null
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
PROXY_CONF

    if [ -n "$no_proxy" ]; then
        echo "Environment=\"NO_PROXY=${no_proxy}\"" | sudo tee -a "$drop_in_dir/http-proxy.conf" > /dev/null
    fi

    success "설정 파일 생성 완료: $drop_in_dir/http-proxy.conf"

    echo ""
    echo "${bold}생성된 설정:${reset}"
    sudo cat "$drop_in_dir/http-proxy.conf"

    # ========================================
    # Step 5: Reload systemd and restart Docker
    # ========================================
    info "Step 5/5: systemd 재로드 및 Docker 재시작 중..."

    if ! sudo systemctl daemon-reload; then
        error "systemd daemon-reload 실패"
        return 1
    fi
    success "systemd daemon-reload 완료"

    if ! sudo systemctl restart docker; then
        error "Docker 재시작 실패"
        return 1
    fi
    success "Docker 재시작 완료"

    # ========================================
    # Verify configuration
    # ========================================
    echo ""
    echo "${bold}설정 확인:${reset}"
    systemctl show --property=Environment docker

    # ========================================
    # Test proxy with docker pull
    # ========================================
    echo ""
    if confirm "Proxy 설정을 테스트하시겠습니까? (docker pull 시도)"; then
        info "작은 이미지로 테스트 중..."
        if docker pull alpine:latest > /dev/null 2>&1; then
            success "Proxy 설정이 정상입니다!"
            docker rmi alpine:latest > /dev/null 2>&1 || true
        else
            warning "docker pull 실패. Proxy 설정을 확인하세요."
            warning "수동 설정: $drop_in_dir/http-proxy.conf"
            return 1
        fi
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Docker 회사 프록시 설정 완료!
════════════════════════════════════════════════════${reset}

${bold}설정 파일:${reset}
  ${yellow}$drop_in_dir/http-proxy.conf${reset}

${bold}설정 확인:${reset}
  ${yellow}systemctl show --property=Environment docker${reset}

${bold}설정 수정:${reset}
  ${yellow}sudo nano $drop_in_dir/http-proxy.conf${reset}
  ${yellow}sudo systemctl daemon-reload${reset}
  ${yellow}sudo systemctl restart docker${reset}

${bold}설정 제거:${reset}
  ${yellow}sudo rm -f $drop_in_dir/http-proxy.conf${reset}
  ${yellow}sudo systemctl daemon-reload${reset}
  ${yellow}sudo systemctl restart docker${reset}

EOF
}

main "$@"
