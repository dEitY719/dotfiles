#!/bin/bash
# shell-common/tools/external/npm.sh
# NPM/NVM 기본 설정 및 유틸리티
#
# 환경별 설정 방법:
#   1. NVM을 사용하는 경우 (집 또는 회사):
#      shell-common/tools/external/npm.local.example을 npm.local.sh로 복사
#   2. npm.local.sh에서 환경에 맞게 NPM/NVM 설정 수정
#   3. npm.local.sh는 자동으로 로드됨 (.gitignore에 의해 제외됨)
#
# 참고:
#   - 이 파일은 기본 NPM aliases와 helper functions만 제공합니다
#   - NVM 관련 설정은 npm.local.sh에서 처리해야 합니다
#   - npm.local.sh가 없으면 시스템에 설치된 기본 npm을 사용합니다

# ========================================
# NPM Aliases
# ========================================
alias npm-v='npm --version'
alias npm-list='npm list -g --depth=0'
alias npm-outdated='npm outdated -g'
alias npm-update='npm update -g'
alias npm-cache-clean='npm cache clean --force'

# NPM Install Aliases
alias npm-i='npm install'
alias npm-is='npm install --save'
alias npm-isd='npm install --save-dev'
alias npm-ig='npm install -g'

# NPM Uninstall Aliases
alias npm-un='npm uninstall'
alias npm-ung='npm uninstall -g'

# NPM Info Function (with usage)
npm_info() {
    if [ -z "$1" ]; then
        echo "사용법: npm-info <package-name>"
        echo ""
        echo "예시:"
        echo "  npm-info react"
        echo "  npm-info lodash"
        echo "  npm-info express"
        return 1
    fi
    npm info "$@"
}
alias npm-info='npm_info'

# NPM Search Function (with usage)
npm_search() {
    if [ -z "$1" ]; then
        echo "사용법: npm-search <keyword>"
        echo ""
        echo "예시:"
        echo "  npm-search react"
        echo "  npm-search testing"
        echo "  npm-search animation"
        return 1
    fi
    npm search "$@"
}
alias npm-search='npm_search'

# ========================================
# NPM Helper Function
# ========================================

# NPM 설치 (대화형 스크립트)
npminstall() {
    bash "$HOME/dotfiles/shell-common/tools/custom/install-npm.sh"
}

# NPM 제거 (대화형 스크립트)
npmuninstall() {
    bash "$HOME/dotfiles/shell-common/tools/custom/uninstall-npm.sh"
}

# CA 인증서 설치 (대화형 스크립트)
crtsetup() {
    bash "$HOME/dotfiles/shell-common/tools/custom/setup-crt.sh"
}

# ========================================
# 환경별 로컬 NPM 설정 로드 (있는 경우)
# ========================================
if [ -f "${BASH_SOURCE[0]%/*}/npm.local.sh" ]; then
    . "${BASH_SOURCE[0]%/*}/npm.local.sh"
elif [ -f "${0:a:h}/npm.local.sh" ]; then
    # zsh support
    . "${0:a:h}/npm.local.sh"
fi
