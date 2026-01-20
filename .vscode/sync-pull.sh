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

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

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

log_info "Pulling VS Code settings → .vscode/base.json"
log_info "Source path: $VSCODE_SETTINGS_PATH"
echo ""

# VS Code 설정 파일 확인
if [[ ! -f "$VSCODE_SETTINGS_PATH" ]]; then
    log_error "VS Code 설정 파일을 찾을 수 없습니다: $VSCODE_SETTINGS_PATH"
    log_info "VS Code를 한 번 실행한 후 다시 시도하세요"
    exit 1
fi

# 백업 생성
BACKUP_FILE="${BASE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$BASE_FILE" ]]; then
    cp "$BASE_FILE" "$BACKUP_FILE"
    log_info "기존 base.json 백업: $BACKUP_FILE"
fi

# VS Code 설정을 base.json에 복사
cp "$VSCODE_SETTINGS_PATH" "$BASE_FILE"
log_success "설정 파일 복사 완료"

echo ""
log_info "복사된 파일:"
cat "$BASE_FILE" | python3 -m json.tool --indent 2

echo ""
log_success "base.json이 VS Code 설정과 동기화되었습니다"
log_warning "변경 사항이 필요하면 Git에 커밋하세요"
