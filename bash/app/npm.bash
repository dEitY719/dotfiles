#!/bin/bash

# 1. 전역 경로 변수 정의
NPM_GLOBAL_PATH="$HOME/.npm-global"

# 2. nvm 설치 여부 확인 (디렉토리 존재로 판단 - NVM_DIR 변수보다 확실)
NVM_INSTALLED=false
if [ -d "$HOME/.nvm" ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
    NVM_INSTALLED=true
fi

# 3. NPM prefix 설정
# nvm이 설치되어 있지 않은 경우에만 전역 prefix를 설정합니다.
# nvm은 자체적으로 npm을 관리하므로 prefix 설정과 충돌합니다.
if [ "$NVM_INSTALLED" = false ]; then
    # NPM prefix 설정이 되어 있는지 확인
    CURRENT_PREFIX=$(npm config get prefix 2>/dev/null)

    if [ "$CURRENT_PREFIX" != "$NPM_GLOBAL_PATH" ]; then
        echo ""
        echo "ℹ️ NPM prefix 경로를 '$NPM_GLOBAL_PATH'로 설정합니다. (현재: $CURRENT_PREFIX)"

        # 디렉토리 생성
        if [ ! -d "$NPM_GLOBAL_PATH" ]; then
            mkdir -p "$NPM_GLOBAL_PATH"
        fi

        npm config set prefix "$NPM_GLOBAL_PATH"
        echo "✅ 설정 완료. ~/.npmrc 파일 확인: $(grep prefix ~/.npmrc 2>/dev/null)"
    fi
else
    # nvm이 설치된 경우: .npmrc에서 prefix 설정을 제거하여 충돌 방지
    # 이 설정이 있으면 nvm이 매번 경고를 출력합니다.
    if [ -f "$HOME/.npmrc" ] && grep -q "^prefix=" "$HOME/.npmrc" 2>/dev/null; then
        # prefix 라인 제거
        sed -i '/^prefix=/d' "$HOME/.npmrc"
        # 빈 파일이 되면 삭제
        if [ ! -s "$HOME/.npmrc" ]; then
            rm -f "$HOME/.npmrc"
        fi
    fi
fi

# 4. PATH 환경 변수 설정
# nvm 사용 여부와 관계없이 ~/.npm-global/bin을 PATH에 추가하여
# 사용자가 직접 설치한 다른 CLI 도구들을 사용할 수 있도록 합니다.
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
