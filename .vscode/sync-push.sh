#!/bin/bash
set -euo pipefail

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FILE="$SCRIPT_DIR/base.json"

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

# OS별 VS Code 설정 경로 결정
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    # Windows (Git Bash, MSYS2, Cygwin에서 실행됨)
    VSCODE_SETTINGS_PATH="$APPDATA/Code/User/settings.json"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    VSCODE_SETTINGS_PATH="$HOME/Library/Application Support/Code/User/settings.json"
else
    # Linux
    VSCODE_SETTINGS_PATH="$HOME/.config/Code/User/settings.json"
fi

log_info "Pushing .vscode/base.json → VS Code settings"
log_info "Target path: $VSCODE_SETTINGS_PATH"
echo ""

# 대상 디렉토리 확인
if [[ ! -d "$(dirname "$VSCODE_SETTINGS_PATH")" ]]; then
    log_error "VS Code 설정 디렉토리를 찾을 수 없습니다"
    log_info "VS Code를 한 번 실행한 후 다시 시도하세요"
    exit 1
fi

# 백업 생성
BACKUP_FILE="${VSCODE_SETTINGS_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$VSCODE_SETTINGS_PATH" ]]; then
    cp "$VSCODE_SETTINGS_PATH" "$BACKUP_FILE"
    log_info "기존 설정 백업: $BACKUP_FILE"
fi

# base.json을 VS Code 설정에 복사
cp "$BASE_FILE" "$VSCODE_SETTINGS_PATH"
log_success "설정 파일 복사 완료"

echo ""
log_info "VS Code를 재시작하여 변경 사항을 적용하세요"
