#!/bin/bash

# scripts/verify-config-files.sh: setup.sh 사후 무결성 검증
#
# PURPOSE: setup.sh 가 배치한 활성 심볼릭 링크의 타겟 파일들이
#   (a) 정상 JSON 으로 파싱되고,
#   (b) NBSP (U+00A0) / BOM / NUL 같은 비가시 손상 바이트가 없는지
# 매번 확인한다. 사내 PC 에서 #594 의 NBSP / InvalidSymbol 증상이
# 재현되면 즉시 fail-loud 로 잡기 위한 안전망.
#
# WHEN TO RUN: setup.sh 가 자동 호출 (종료 직전).
#
# EXIT:
#   0  — 모든 파일 정상
#   1  — JSON parse 실패 또는 손상 바이트 검출 (fatal)

set -u

_SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT="$(cd "$_SCRIPT_PATH/.." && pwd)"
UX_LIB="$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
if [ ! -f "$UX_LIB" ]; then
    echo "CRITICAL ERROR: UX library not found at $UX_LIB. Exiting." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$UX_LIB"

ux_header "Verify config files (#594)"

# Targets: (kind, path)
#   kind=json     — full JSON parse + byte scan
#   kind=bytes    — byte scan only (TOML/XML 등)
#   kind=tokenchk — JSON parse + placeholder token warning (settings.local.json)
_FILES="
json    $HOME/.config/opencode/opencode.json
json    $HOME/.claude/settings.json
tokenchk $HOME/.claude/settings.local.json
bytes   $HOME/.cargo/config.toml
bytes   $HOME/.config/uv/uv.toml
bytes   $HOME/.bunfig.toml
bytes   $HOME/.nuget/NuGet/NuGet.Config
"

# Detect helpers
_HAS_PYTHON3=0
command -v python3 >/dev/null 2>&1 && _HAS_PYTHON3=1
_HAS_JQ=0
command -v jq >/dev/null 2>&1 && _HAS_JQ=1

_fail=0

_scan_bytes() {
    # $1: path
    # Returns 1 if NBSP / BOM / NUL detected. Prints location hint.
    _path=$1
    # BOM (EF BB BF) at file start
    if [ "$(head -c 3 "$_path" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
        ux_error "BOM detected at start of: $_path"
        return 1
    fi
    # NBSP (UTF-8: C2 A0) anywhere
    if LC_ALL=C grep -lP '\xc2\xa0' "$_path" >/dev/null 2>&1; then
        _line=$(LC_ALL=C grep -nP '\xc2\xa0' "$_path" | head -1 | cut -d: -f1)
        ux_error "NBSP (U+00A0) detected at line $_line in: $_path"
        return 1
    fi
    # NUL byte anywhere (encrypted-blob leftover)
    if LC_ALL=C grep -lP '\x00' "$_path" >/dev/null 2>&1; then
        ux_error "NUL byte detected (encrypted-blob leftover?): $_path"
        return 1
    fi
    return 0
}

_parse_json() {
    _path=$1
    if [ "$_HAS_PYTHON3" -eq 1 ]; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$_path" 2>/dev/null
        return $?
    elif [ "$_HAS_JQ" -eq 1 ]; then
        jq -e . "$_path" >/dev/null 2>&1
        return $?
    fi
    # No JSON validator available — skip parse, byte scan still runs
    return 0
}

# Iterate. Here-doc (not pipe) so `_fail` assignments persist in this shell
# — `while ... | read` would fork a subshell and lose state (#595 review).
while read -r _kind _path; do
    [ -z "$_kind" ] && continue

    if [ ! -f "$_path" ]; then
        if [ -L "$_path" ]; then
            ux_warning "Dangling symlink: $_path → $(readlink "$_path")"
            ux_info    "→ Re-run ./setup.sh or restore the symlink target."
            _fail=1
        fi
        continue
    fi

    case "$_kind" in
        json|tokenchk)
            if ! _parse_json "$_path"; then
                ux_error "Invalid JSON: $_path"
                _fail=1
                continue
            fi
            ;;
    esac

    if ! _scan_bytes "$_path"; then
        _fail=1
        continue
    fi

    if [ "$_kind" = "tokenchk" ] && [ "$_HAS_JQ" -eq 1 ]; then
        _token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$_path" 2>/dev/null)
        if [ -z "$_token" ] || [ "$_token" = "your-dt-api-key" ]; then
            ux_warning "$_path: ANTHROPIC_AUTH_TOKEN is empty or placeholder"
            ux_info    "→ Edit the file and replace with the real token."
        fi
    fi

    ux_success "OK: $_path"
done <<EOF
$_FILES
EOF

if [ "$_fail" -ne 0 ]; then
    ux_error "Config file verification FAILED — see messages above."
    ux_info  "Likely cause: leftover git-crypt smudge filter (#594)."
    ux_info  "Recovery:    rerun ./setup.sh after a fresh checkout, or"
    ux_info  "             ./scripts/disable-git-crypt-local.sh && reset target file."
    exit 1
fi

ux_success "All config files OK."
exit 0
