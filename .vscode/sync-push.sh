#!/bin/bash
set -euo pipefail

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FILE="$SCRIPT_DIR/base.json"
KEYBINDINGS_FILE="$SCRIPT_DIR/keybindings.json"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 헬퍼 함수
log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

log_error() {
    echo -e "${RED}✗${NC}  $1" >&2
}

# base.json 파일 확인
if [[ ! -f "$BASE_FILE" ]]; then
    log_error "base.json 파일을 찾을 수 없습니다: $BASE_FILE"
    exit 1
fi

# keybindings.json 파일 확인
if [[ ! -f "$KEYBINDINGS_FILE" ]]; then
    log_error "keybindings.json 파일을 찾을 수 없습니다: $KEYBINDINGS_FILE"
    exit 1
fi

# WSL 환경 감지 함수
is_wsl() {
    if [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        return 0
    fi
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        return 0
    fi
    return 1
}

# OS별 VS Code 설정 경로 결정
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    # Windows (Git Bash, MSYS2, Cygwin에서 실행됨)
    VSCODE_SETTINGS_PATH="$APPDATA/Code/User/settings.json"
elif is_wsl; then
    # WSL 환경: Windows의 VS Code 설정 경로 사용
    # Windows APPDATA 경로를 가져와서 WSL 경로로 변환
    WIN_APPDATA=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r')
    if [[ -n "$WIN_APPDATA" ]]; then
        WSL_APPDATA=$(wslpath "$WIN_APPDATA")
        VSCODE_SETTINGS_PATH="$WSL_APPDATA/Code/User/settings.json"
    else
        log_error "Windows APPDATA 경로를 가져올 수 없습니다"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    VSCODE_SETTINGS_PATH="$HOME/Library/Application Support/Code/User/settings.json"
else
    # Linux (native)
    VSCODE_SETTINGS_PATH="$HOME/.config/Code/User/settings.json"
fi

log_info "Pushing .vscode/ → VS Code settings"
log_info "Target path: $VSCODE_SETTINGS_PATH"
echo ""

# 대상 디렉토리 확인
if [[ ! -d "$(dirname "$VSCODE_SETTINGS_PATH")" ]]; then
    log_error "VS Code 설정 디렉토리를 찾을 수 없습니다"
    log_info "VS Code를 한 번 실행한 후 다시 시도하세요"
    exit 1
fi

# VS Code 설정 파일들의 경로 결정
VSCODE_KEYBINDINGS_PATH="${VSCODE_SETTINGS_PATH%/*}/keybindings.json"

# settings.json 백업 생성
BACKUP_FILE="${VSCODE_SETTINGS_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$VSCODE_SETTINGS_PATH" ]]; then
    cp "$VSCODE_SETTINGS_PATH" "$BACKUP_FILE"
    log_info "기존 settings.json 백업: $BACKUP_FILE"
fi

# base.json을 VS Code settings.json에 복사
cp "$BASE_FILE" "$VSCODE_SETTINGS_PATH"
log_success "settings.json 복사 완료"

# keybindings.json 백업 생성
KEYBINDINGS_BACKUP_FILE="${VSCODE_KEYBINDINGS_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$VSCODE_KEYBINDINGS_PATH" ]]; then
    cp "$VSCODE_KEYBINDINGS_PATH" "$KEYBINDINGS_BACKUP_FILE"
    log_info "기존 keybindings.json 백업: $KEYBINDINGS_BACKUP_FILE"
fi

# keybindings.json을 VS Code에 복사
cp "$KEYBINDINGS_FILE" "$VSCODE_KEYBINDINGS_PATH"
log_success "keybindings.json 복사 완료"

echo ""
log_info "VS Code를 재시작하여 변경 사항을 적용하세요"
