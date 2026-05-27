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

# 동일하면 skip, 다르면 backup→copy. target 없으면 backup 없이 copy.
copy_if_changed() {
    local src="$1" dst="$2" name
    name=$(basename "$dst")

    if [[ ! -f "$dst" ]]; then
        cp "$src" "$dst"
        log_success "${name} 복사 완료 (신규)"
        return 0
    fi

    if cmp -s "$src" "$dst" 2>/dev/null || diff -q "$src" "$dst" >/dev/null 2>&1; then
        log_info "${name} 변경 없음 — skip"
        return 0
    fi

    local backup
    backup="${dst}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$dst" "$backup"
    log_info "기존 ${name} 백업: $backup"
    cp "$src" "$dst"
    log_success "${name} 복사 완료"
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

# settings.json: diff 가드 후 backup → copy
copy_if_changed "$VSCODE_SETTINGS_PATH" "$BASE_FILE"

echo ""
log_info "Settings 파일:"
cat "$BASE_FILE" | python3 -m json.tool --indent 2 2>/dev/null || cat "$BASE_FILE"

# keybindings.json 복사 (존재하는 경우)
if [[ -f "$VSCODE_KEYBINDINGS_PATH" ]]; then
    # VS Code의 JSON 주석을 제거하고 정렬된 형식으로 임시 파일에 작성
    KEYBINDINGS_TMP=$(mktemp)
    trap 'rm -f "$KEYBINDINGS_TMP"' EXIT

    if ! python3 - "$VSCODE_KEYBINDINGS_PATH" "$KEYBINDINGS_TMP" <<'EOF'; then
import json
import re
import sys

vscode_file = sys.argv[1]
target_file = sys.argv[2]

try:
    with open(vscode_file, 'r', encoding='utf-8') as f:
        content = f.read()

    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    data = json.loads(content)

    with open(target_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print("OK")
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF
        log_error "keybindings.json 처리 중 오류가 발생했습니다"
        exit 1
    fi

    # 정규화된 임시 파일과 현재 KEYBINDINGS_FILE 을 비교 후 backup → copy
    copy_if_changed "$KEYBINDINGS_TMP" "$KEYBINDINGS_FILE"

    echo ""
    log_info "Keybindings 파일:"
    python3 -m json.tool --indent 2 "$KEYBINDINGS_FILE" 2>/dev/null || cat "$KEYBINDINGS_FILE"
else
    log_warning "keybindings.json 파일을 찾을 수 없습니다: $VSCODE_KEYBINDINGS_PATH"
fi

echo ""
log_success "VS Code 설정이 동기화되었습니다"
log_warning "변경 사항이 필요하면 Git에 커밋하세요"
