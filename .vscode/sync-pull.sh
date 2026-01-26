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

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

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
        echo -e "${RED}✗${NC}  Windows APPDATA 경로를 가져올 수 없습니다" >&2
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    VSCODE_SETTINGS_PATH="$HOME/Library/Application Support/Code/User/settings.json"
else
    # Linux (native)
    VSCODE_SETTINGS_PATH="$HOME/.config/Code/User/settings.json"
fi

log_info "Pulling VS Code settings → .vscode/"
log_info "Source path: $VSCODE_SETTINGS_PATH"
echo ""

# VS Code 설정 파일 확인
if [[ ! -f "$VSCODE_SETTINGS_PATH" ]]; then
    log_error "VS Code 설정 파일을 찾을 수 없습니다: $VSCODE_SETTINGS_PATH"
    log_info "VS Code를 한 번 실행한 후 다시 시도하세요"
    exit 1
fi

# VS Code 설정 파일들의 경로 결정
VSCODE_KEYBINDINGS_PATH="${VSCODE_SETTINGS_PATH%/*}/keybindings.json"

# base.json 백업 생성
BACKUP_FILE="${BASE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$BASE_FILE" ]]; then
    cp "$BASE_FILE" "$BACKUP_FILE"
    log_info "기존 base.json 백업: $BACKUP_FILE"
fi

# VS Code 설정을 base.json에 복사
cp "$VSCODE_SETTINGS_PATH" "$BASE_FILE"
log_success "settings.json 복사 완료"

echo ""
log_info "Settings 파일:"
cat "$BASE_FILE" | python3 -m json.tool --indent 2 2>/dev/null || cat "$BASE_FILE"

# keybindings.json 복사 (존재하는 경우)
if [[ -f "$VSCODE_KEYBINDINGS_PATH" ]]; then
    KEYBINDINGS_BACKUP_FILE="${KEYBINDINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    if [[ -f "$KEYBINDINGS_FILE" ]]; then
        cp "$KEYBINDINGS_FILE" "$KEYBINDINGS_BACKUP_FILE"
        log_info "기존 keybindings.json 백업: $KEYBINDINGS_BACKUP_FILE"
    fi

    # VS Code의 JSON 주석을 제거하고 정렬된 형식으로 저장
    python3 << EOF
import json
import re

vscode_file = "$VSCODE_KEYBINDINGS_PATH"
target_file = "$KEYBINDINGS_FILE"

try:
    with open(vscode_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # JSON 주석 제거 (// 로 시작하는 라인)
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)

    # JSON 파싱
    data = json.loads(content)

    # 정렬된 JSON으로 저장
    with open(target_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print("OK")
except Exception as e:
    print(f"ERROR: {e}")
    exit(1)
EOF

    if [[ $? -eq 0 ]]; then
        log_success "keybindings.json 복사 완료"

        echo ""
        log_info "Keybindings 파일:"
        cat "$KEYBINDINGS_FILE" | python3 -m json.tool --indent 2 2>/dev/null || cat "$KEYBINDINGS_FILE"
    else
        log_error "keybindings.json 처리 중 오류가 발생했습니다"
        exit 1
    fi
else
    log_warning "keybindings.json 파일을 찾을 수 없습니다: $VSCODE_KEYBINDINGS_PATH"
fi

echo ""
log_success "VS Code 설정이 동기화되었습니다"
log_warning "변경 사항이 필요하면 Git에 커밋하세요"
