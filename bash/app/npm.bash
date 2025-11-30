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
    # Color definitions
    local bold blue green yellow reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[NPM Quick Commands]${reset}

  ${bold}${blue}정보 & 버전:${reset}
    ${green}npm-v${reset}                 : npm 버전 확인
    ${green}npm-list${reset}              : 글로벌 설치 패키지 목록 (최상위만)
    ${green}npm-info <package>${reset}    : 패키지 상세 정보
                          예) npm-info react, npm-info lodash
    ${green}npm-search <keyword>${reset}  : npm 레지스트리에서 패키지 검색
                          예) npm-search testing, npm-search animation
    ${green}npm-outdated${reset}          : 구버전 글로벌 패키지 확인

  ${bold}${blue}패키지 설치:${reset}
    ${green}npm-i${reset}          : npm install (현재 프로젝트)
    ${green}npm-is${reset}         : npm install --save (프로젝트 의존성)
    ${green}npm-isd${reset}        : npm install --save-dev (개발 의존성)
    ${green}npm-ig${reset}         : npm install -g (글로벌 설치)

  ${bold}${blue}패키지 제거:${reset}
    ${green}npm-un${reset}         : npm uninstall (프로젝트에서 제거)
    ${green}npm-ung${reset}        : npm uninstall -g (글로벌에서 제거)

  ${bold}${blue}업데이트 & 유지보수:${reset}
    ${green}npm-update${reset}      : 글로벌 패키지 모두 업데이트
    ${green}npm-cache-clean${reset} : npm 캐시 강제 삭제

  ${bold}${blue}Installation & Setup:${reset}
    ${green}npminstall${reset}     : Node.js/npm 설치 (대화형 스크립트)
    ${green}npmuninstall${reset}   : Node.js/npm 제거 (대화형 스크립트)

  ${bold}${blue}자주 사용하는 npm 명령어:${reset}
    ${green}npm init${reset}                   : 새 프로젝트 초기화
    ${green}npm install${reset}                : package.json 기반 의존성 설치
    ${green}npm install <package>${reset}      : 특정 패키지 설치
    ${green}npm install <package>@<version>{{reset}  : 특정 버전 설치
    ${green}npm list${reset}                   : 프로젝트 패키지 목록
    ${green}npm list -g --depth=0${reset}      : 글로벌 패키지 목록
    ${green}npm update{{reset}                 : 패키지 업데이트
    ${green}npm uninstall <package>{{reset}    : 패키지 제거
    ${green}npm uninstall -g <package>{{reset} : 글로벌 패키지 제거
    ${green}npm search <keyword>{{reset}       : 패키지 검색
    ${green}npm run <script>{{reset}           : package.json 스크립트 실행
    ${green}npm audit{{reset}                  : 보안 취약점 검사
    ${green}npm audit fix{{reset}              : 보안 취약점 자동 수정
    ${green}npm cache clean --force{{reset}    : npm 캐시 삭제
    ${green}npm config list{{reset}            : npm 설정 확인
    ${green}npm config set {{reset}}           : npm 설정 변경

  ${bold}${blue}팁:{{reset}
    • 글로벌 경로: ~/.npm-global
    • 설정 파일: ~/.npmrc
    • 캐시 위치: ~/.npm
    • 더 많은 정보: ${yellow}npm help${reset}

EOF
}

# NPM 설치 (대화형 스크립트)
npminstall() {
    bash /home/bwyoon/dotfiles/mytool/install-npm.sh
}

# NPM 제거 (대화형 스크립트)
npmuninstall() {
    bash /home/bwyoon/dotfiles/mytool/uninstall-npm.sh
}
