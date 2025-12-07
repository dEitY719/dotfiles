#!/bin/bash

# 1. 전역 경로 변수 정의
NPM_GLOBAL_PATH="$HOME/.npm-global"

# 2. NPM prefix 설정이 되어 있는지 확인
# npm config get prefix 명령을 사용하며, 결과를 표준 오류로 리디렉션하여 깔끔하게 처리
CURRENT_PREFIX=$(npm config get prefix 2>/dev/null)

if [ "$CURRENT_PREFIX" != "$NPM_GLOBAL_PATH" ]; then
    # 설정이 원하는 경로와 다르거나 (기본값인 /usr/local 등), 설정이 아예 없을 경우
    echo ""
    echo "ℹ️ NPM prefix 경로를 '$NPM_GLOBAL_PATH'로 설정합니다. (현재: $CURRENT_PREFIX)"

    # 디렉토리 생성은 PATH 설정 전에 미리 해둡니다. (멱등성 유지)
    if [ ! -d "$NPM_GLOBAL_PATH" ]; then
        mkdir -p "$NPM_GLOBAL_PATH"
    fi

    # npm config set 명령 실행
    # 이 명령어는 한 번만 실행되어 ~/.npmrc에 기록됩니다.
    npm config set prefix "$NPM_GLOBAL_PATH"

    echo "✅ 설정 완료. ~/.npmrc 파일 확인: $(grep prefix ~/.npmrc)"
    # else
    # 설정이 이미 원하는 경로로 되어 있는 경우
    # echo "✅ NPM prefix 설정은 이미 '$NPM_GLOBAL_PATH'로 되어 있습니다."
fi

# 3. PATH 환경 변수 설정 (필수)
# 쉘이 시작될 때마다 PATH에 추가하여, CLI 실행 파일(gemini 등)을 찾을 수 있게 합니다.
# 조건부 설정과 관계없이 항상 실행되어야 하는 부분입니다.
if [[ ":$PATH:" != *":$NPM_GLOBAL_PATH/bin:"* ]]; then
    export PATH="$NPM_GLOBAL_PATH/bin:$PATH"
fi

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
npmhelp() {
    ux_header "NPM Quick Commands"

    ux_section "Info & Version"
    ux_table_row "npm-v" "npm --version" "Check version"
    ux_table_row "npm-list" "list -g --depth=0" "Global packages"
    ux_table_row "npm-info" "info <pkg>" "Package details"
    ux_table_row "npm-search" "search <keyword>" "Search packages"
    ux_table_row "npm-outdated" "outdated -g" "Check updates"
    echo ""

    ux_section "Install"
    ux_table_row "npm-i" "npm install" "Install deps"
    ux_table_row "npm-is" "install --save" "Save prod dep"
    ux_table_row "npm-isd" "install --save-dev" "Save dev dep"
    ux_table_row "npm-ig" "install -g" "Global install"
    echo ""

    ux_section "Uninstall"
    ux_table_row "npm-un" "npm uninstall" "Remove dep"
    ux_table_row "npm-ung" "uninstall -g" "Remove global"
    echo ""

    ux_section "Maintenance"
    ux_table_row "npm-update" "update -g" "Update global"
    ux_table_row "npm-cache-clean" "cache clean --force" "Clear cache"
    echo ""

    ux_section "Setup Tools"
    ux_table_row "npminstall" "Install Script" "Install Node/NPM"
    ux_table_row "npmuninstall" "Uninstall Script" "Remove Node/NPM"
    echo ""

    ux_section "Common Commands"
    ux_bullet "npm init"
    ux_bullet "npm run <script>"
    ux_bullet "npm audit fix"
    ux_bullet "npm config list"
    echo ""

    ux_info "Global Path: ~/.npm-global"
}

# NPM 설치 (대화형 스크립트)
npminstall() {
    bash "$HOME/dotfiles/mytool/install-npm.sh"
}

# NPM 제거 (대화형 스크립트)
npmuninstall() {
    bash "$HOME/dotfiles/mytool/uninstall-npm.sh"
}
