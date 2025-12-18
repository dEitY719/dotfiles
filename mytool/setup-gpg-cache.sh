#!/bin/bash

# mytool/setup-gpg-cache.sh
# GPG agent 캐싱 설정 스크립트 (편의성 향상)

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
  GPG Agent 캐싱 설정 스크립트
════════════════════════════════════════════════════${reset}

이 스크립트는 GPG passphrase를 자동으로 캐싱하도록 설정합니다.

${bold}캐싱의 장점:${reset}
  ✓ Passphrase를 하루에 한 번만 입력
  ✓ git-crypt unlock 시 자동 실행
  ✓ 보안과 편의성의 균형

설정 과정:
  1. GPG 설치 확인
  2. ~/.gnupg 디렉토리 생성
  3. gpg-agent.conf 파일 설정
  4. GPG agent 재시작

${yellow}주의: 기존 gpg-agent.conf가 있으면 추가됩니다.${reset}

EOF

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설정이 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 1: Check GPG
    # ========================================
    info "Step 1/4: GPG 설치 확인 중..."

    if ! command -v gpg &>/dev/null; then
        error "gpg가 설치되어 있지 않습니다."
        warning "apt-get install gnupg 로 설치 후 다시 시도하세요."
        exit 1
    fi
    success "gpg 설치됨: $(gpg --version | head -n 1)"
    echo ""

    # ========================================
    # Step 2: Create .gnupg directory
    # ========================================
    info "Step 2/4: ~/.gnupg 디렉토리 확인 중..."

    if [[ -d ~/.gnupg ]]; then
        success "~/.gnupg 디렉토리가 이미 존재합니다."
    else
        mkdir -p ~/.gnupg
        chmod 700 ~/.gnupg
        success "~/.gnupg 디렉토리 생성 완료"
    fi
    echo ""

    # ========================================
    # Step 3: Configure gpg-agent.conf
    # ========================================
    info "Step 3/4: gpg-agent.conf 설정 중..."

    local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"
    local cache_ttl=86400  # 24 hours in seconds

    # Check if settings already exist
    if grep -q "default-cache-ttl" "$gpg_agent_conf" 2>/dev/null; then
        warning "gpg-agent.conf에 이미 cache-ttl 설정이 있습니다."
        echo "${bold}현재 설정:${reset}"
        grep -E "cache-ttl|cache-ttl-ssh" "$gpg_agent_conf" 2>/dev/null || echo "  (없음)"
        echo ""

        if confirm "기존 설정을 덮어쓰시겠습니까?"; then
            # Remove old cache-ttl settings
            sed -i '/default-cache-ttl/d' "$gpg_agent_conf"
            sed -i '/max-cache-ttl/d' "$gpg_agent_conf"
            info "기존 cache-ttl 설정 제거됨"
        else
            warning "설정 변경을 건너뜁니다."
            exit 0
        fi
    fi

    # Add new settings
    echo "default-cache-ttl $cache_ttl" >> "$gpg_agent_conf"
    echo "max-cache-ttl $cache_ttl" >> "$gpg_agent_conf"
    success "gpg-agent.conf 설정 완료 (24시간 캐싱)"

    echo ""
    echo "${bold}추가된 설정:${reset}"
    echo "  default-cache-ttl $cache_ttl"
    echo "  max-cache-ttl $cache_ttl"
    echo ""

    # ========================================
    # Step 4: Reload GPG agent
    # ========================================
    info "Step 4/4: GPG agent 재시작 중..."

    if gpg-connect-agent reloadagent /bye &>/dev/null; then
        success "GPG agent 재시작 완료"
    else
        warning "GPG agent 재시작 실패 (수동으로 재시작해야 할 수 있습니다)"
        info "수동 재시작: gpgconf --kill gpg-agent"
    fi
    echo ""

    # ========================================
    # Verify configuration
    # ========================================
    info "설정 확인 중..."
    echo ""
    echo "${bold}gpg-agent.conf 내용:${reset}"
    cat "$gpg_agent_conf"
    echo ""

    # ========================================
    # Completion
    # ========================================
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ GPG Agent 캐싱 설정 완료!
════════════════════════════════════════════════════${reset}

${bold}다음 단계:${reset}
  1. git-crypt unlock 또는 GPG 사용 시 passphrase 입력
  2. 24시간 동안 자동으로 캐싱됨
  3. 하루에 한 번만 입력하면 됩니다

${bold}캐싱 동작:${reset}
  • 첫 GPG 사용: Passphrase 입력 필요
  • 24시간 이내: 자동으로 사용 (재입력 불필요)
  • 24시간 이후: Passphrase 재입력

${bold}캐싱 초기화 (즉시 만료):${reset}
  ${yellow}gpgconf --kill gpg-agent${reset}

${bold}설정 확인:${reset}
  ${yellow}cat ~/.gnupg/gpg-agent.conf${reset}

EOF
}

main "$@"
