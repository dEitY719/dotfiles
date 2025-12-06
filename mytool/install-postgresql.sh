#!/bin/bash

# mytool/install-postgresql.sh
# PostgreSQL 서버 설치 스크립트 (대화형)

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
  PostgreSQL 서버 설치 스크립트 (대화형)
════════════════════════════════════════════════════${reset}

이 스크립트는 Ubuntu/Debian에 PostgreSQL 서버를 설치합니다.
설치 과정:
  1. 패키지 매니저 업데이트
  2. PostgreSQL 저장소 추가 (최신 버전)
  3. PostgreSQL 서버 설치
  4. PostgreSQL 서비스 활성화 및 시작
  5. 설치 확인
  6. 초기 설정 (선택사항)

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
    # Step 2: Add PostgreSQL Repository
    # ========================================
    info "Step 2/5: PostgreSQL 저장소 추가 중..."
    if confirm "PostgreSQL 공식 저장소를 추가하시겠습니까? (최신 버전)"; then
        # Import GPG key
        info "  -> PostgreSQL GPG 키 추가..."
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
            sudo gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg || {
            error "PostgreSQL GPG 키 추가 실패"
            return 1
        }

        # Add repository (Ubuntu/Debian 자동 감지)
        info "  -> PostgreSQL 저장소 추가..."
        if command -v lsb_release >/dev/null 2>&1; then
            local distro_name
            distro_name=$(lsb_release -cs)
        else
            # Fallback for minimal systems
            distro_name="focal"  # Default to Ubuntu 20.04
            warning "lsb_release를 찾을 수 없어 기본값(focal)을 사용합니다."
        fi

        echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt ${distro_name}-pgdg main" | \
            sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null || {
            error "PostgreSQL 저장소 추가 실패"
            return 1
        }

        success "PostgreSQL 저장소 추가 완료"
        info "  저장소 설정: ${distro_name}-pgdg"
    else
        warning "Step 2 스킵됨 (기본 저장소의 PostgreSQL 사용)"
    fi

    # ========================================
    # Step 3: Update & Install PostgreSQL
    # ========================================
    info "Step 3/5: apt-get 업데이트 후 PostgreSQL 설치 중..."
    if confirm "apt-get update를 실행하시겠습니까?"; then
        sudo apt-get update || {
            error "apt-get update 실패"
            return 1
        }
        success "패키지 매니저 업데이트 완료"
    else
        warning "apt-get update 스킵됨"
    fi

    if confirm "PostgreSQL Server를 설치하시겠습니까?"; then
        sudo apt-get install -y postgresql postgresql-contrib || {
            error "PostgreSQL 설치 실패"
            return 1
        }
        success "PostgreSQL 설치 완료"
    else
        warning "PostgreSQL 설치 스킵됨"
    fi

    # ========================================
    # Step 4: Start & Enable Service
    # ========================================
    info "Step 4/5: PostgreSQL 서비스 시작 중..."
    if confirm "PostgreSQL 서비스를 시작하시겠습니까?"; then
        sudo systemctl start postgresql || {
            error "PostgreSQL 서비스 시작 실패"
            return 1
        }
        success "PostgreSQL 서비스 시작됨"

        if confirm "부팅 시 자동 시작을 활성화하시겠습니까? (권장)"; then
            sudo systemctl enable postgresql || {
                error "부팅 자동 시작 활성화 실패"
                return 1
            }
            success "부팅 자동 시작 활성화됨"
        fi
    else
        warning "Step 4 스킵됨"
    fi

    # ========================================
    # Step 5: Verify Installation
    # ========================================
    info "Step 5/5: 설치 확인 중..."

    echo ""
    echo "${bold}PostgreSQL 버전:${reset}"
    sudo -u postgres psql --version || warning "PostgreSQL 버전 확인 실패"

    echo ""
    echo "${bold}PostgreSQL 서비스 상태:${reset}"
    sudo systemctl status postgresql --no-pager || warning "서비스 상태 확인 실패"

    # ========================================
    # Post-installation (optional)
    # ========================================
    echo ""
    if confirm "현재 사용자($USER)를 postgres 그룹에 추가하시겠습니까? (선택사항)"; then
        info "사용자를 postgres 그룹에 추가 중..."
        sudo usermod -aG postgres "$USER" || {
            error "사용자 추가 실패"
            return 1
        }
        success "그룹 설정 완료"
        warning "변경사항을 적용하려면 로그아웃 후 재로그인하거나 다음을 실행하세요:"
        echo "  newgrp postgres"
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ PostgreSQL 설치 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. PostgreSQL 확인: ${yellow}psql_server status${reset}
  2. DB/User 추가: ${yellow}psql_add${reset}
  3. 도움말: ${yellow}psqlhelp${reset}

${bold}기본 연결 테스트:${reset}
  ${yellow}sudo -u postgres psql${reset}
  또는
  ${yellow}psql -U postgres${reset} (비밀번호 입력)

${bold}더 많은 PostgreSQL 명령어는:${reset}
  ${yellow}psqlhelp${reset}

EOF
}

main "$@"
