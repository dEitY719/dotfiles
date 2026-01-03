#!/bin/bash
# proxy.sh
# Proxy configuration and diagnostics (environment-agnostic)
#
# This file provides:
#   1. Default proxy settings (works in all environments)
#   2. proxy_help() function (available in all environments)
#   3. check-proxy alias (diagnostic tool)
#   4. Loading of environment-specific proxy.local.sh (if exists)
#
# Environment-specific proxy settings are in:
#   - proxy.local.example (template)
#   - proxy.local.sh (auto-generated, environment-specific)

# ============================================================
# DEFAULT SETTINGS (for public/home environment)
# ============================================================

# No Proxy 설정 (기본값 - 일반 가정 환경)
export no_proxy="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.local"
export NO_PROXY="$no_proxy"

# HTTP/HTTPS 프록시 설정 (필요한 경우 override됨)
# export http_proxy="http://proxy.example.com:8080"
# export https_proxy="http://proxy.example.com:8080"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"

# ============================================================
# HELP & DIAGNOSTICS (environment-agnostic)
# ============================================================

proxy_help() {
    cat <<-'EOF'

[Proxy(Corporate) Commands & Diagnostics]

🔍 DIAGNOSTIC COMMANDS

  # 전체 프록시 진단 실행 (권장)
  check-proxy          # Run full diagnostic
  check-proxy env      # Environment variables only
  check-proxy file     # proxy.local.sh file check
  check-proxy shell    # Shell loading test
  check-proxy conn     # Connectivity test
  check-proxy git      # Git configuration

📌 QUICK COMMANDS

  # 현재 프록시 설정 확인
  echo $http_proxy
  echo $https_proxy
  echo $no_proxy

  # 프록시 설정 (기본값)
  export http_proxy="http://12.26.204.100:8080/"
  export https_proxy="http://12.26.204.100:8080/"
  export no_proxy="10.229.95.200,10.229.95.220,12.36.155.91,12.36.154.116,12.36.154.130,localhost,127.0.0.1,.samsung.net,.samsungds.net,ssai.samsungds.net,dsvdi.net,pfs.nprotect.com"

  # 프록시 해제 (비활성화)
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY

  # 현재 프록시 상태 출력
  env | grep -i proxy

🛠️  GIT CONFIGURATION

  # Git 프록시 타임아웃 증가 (기본 30초 → 60초)
  git config --global http.connectTimeout 60
  git config --global http.lowSpeedLimit 0
  git config --global http.lowSpeedTime 999999

  # GitHub 프록시 우회 (GitHub만 직접 연결)
  git config --global url."https://github.com/".insteadOf https://

  # Git 프록시 설정 확인
  git config --global -l | grep proxy

📖 RECIPES

  # 프록시 임시 적용 (현재 세션만)
  export http_proxy="http://12.26.204.100:8080/"

  # 프록시 완전 초기화
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY

  # 특정 도메인만 예외 처리
  export no_proxy="$no_proxy,.internal.domain.com"

⚠️  NOTES

  - NO_PROXY 값에 공백이 있으면 인식되지 않음 → 반드시 콤마(,)로 구분
  - 대소문자 구분이 없지만, 일부 툴은 대문자 환경 변수만 인식
  - 시스템 전체에 적용하려면 ~/.bashrc 또는 ~/.zshrc에 추가

  Ref: https://confluence.samsungds.net/pages/viewpage.action?pageId=1367083095

EOF
}

# Wrapper function for check-proxy.sh
proxy_check() {
    if [ -f "${HOME}/dotfiles/shell-common/tools/custom/check-proxy.sh" ]; then
        bash "${HOME}/dotfiles/shell-common/tools/custom/check-proxy.sh" "$@"
    else
        echo "❌ check-proxy.sh not found at ~/dotfiles/shell-common/tools/custom/check-proxy.sh"
        return 1
    fi
}

# Aliases (both work in interactive shells)
alias proxy-help='proxy_help'
alias check-proxy='proxy_check'

# ============================================================
# ENVIRONMENT-SPECIFIC SETTINGS (loaded if exists)
# ============================================================

# Load environment-specific proxy configuration (if exists)
# This allows overriding default settings for specific environments
if [ -f "${BASH_SOURCE[0]%/*}/proxy.local.sh" ]; then
    . "${BASH_SOURCE[0]%/*}/proxy.local.sh"
elif [ -f "${0:a:h}/proxy.local.sh" ]; then
    # zsh support
    . "${0:a:h}/proxy.local.sh"
fi
