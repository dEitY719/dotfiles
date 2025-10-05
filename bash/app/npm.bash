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
