#!/bin/sh
# lint_docs_filenames.sh — docs/ 파일명 kebab-case 규칙 검사 (issue #1027)
#
# 정책:
#   - 파일명은 kebab-case (^[a-z0-9]+(-[a-z0-9]+)*\.md$) 를 따른다.
#   - 관례적 대문자 파일(README/AGENTS/GEMINI/CLAUDE)은 면제한다.
#   - 강제(ENFORCED) 범위: 새 정책으로 신설/정비된 tier (docs/adr, docs/requirement).
#     이 범위의 위반은 종료 코드 1 로 CI 를 막는다.
#   - 그 외 docs/ 하위는 warn-only — 레거시 위반은 별도 정리 이슈로 분리한다 (#1027 리스크 1).
#
# 사용:
#   sh scripts/lint_docs_filenames.sh           # repo root 기준
#   DOCS_ROOT=path/to/docs sh scripts/lint_docs_filenames.sh

set -eu

DOCS_ROOT="${DOCS_ROOT:-docs}"

# 강제 검사 범위 (공백 구분 prefix 목록)
ENFORCED_DIRS="${DOCS_ROOT}/adr ${DOCS_ROOT}/requirement"

if [ ! -d "$DOCS_ROOT" ]; then
    echo "lint-docs: '$DOCS_ROOT' 디렉토리를 찾을 수 없습니다." >&2
    exit 2
fi

errors=0
warnings=0

is_exempt() {
    # 관례적 대문자 인덱스/컨텍스트 파일은 면제
    case "$1" in
    README.md | AGENTS.md | GEMINI.md | CLAUDE.md) return 0 ;;
    *) return 1 ;;
    esac
}

is_enforced() {
    # $1 == 파일 경로. ENFORCED_DIRS 중 하나로 시작하면 강제 범위.
    _path="$1"
    for _dir in $ENFORCED_DIRS; do
        case "$_path" in
        "$_dir"/*) return 0 ;;
        esac
    done
    return 1
}

# kebab-case 검사: 소문자/숫자 + 단일 하이픈 구분
is_kebab() {
    printf '%s' "$1" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'
}

while IFS= read -r file; do
    base="$(basename "$file")"
    is_exempt "$base" && continue

    stem="${base%.md}"
    is_kebab "$stem" && continue

    if is_enforced "$file"; then
        echo "FAIL  $file — 파일명이 kebab-case 가 아닙니다 (강제 범위)." >&2
        errors=$((errors + 1))
    else
        echo "warn  $file — 파일명이 kebab-case 가 아닙니다 (legacy, warn-only)."
        warnings=$((warnings + 1))
    fi
done <<EOF
$(find "$DOCS_ROOT" -type f -name '*.md' | sort)
EOF

echo "lint-docs: errors=${errors} warnings=${warnings} (enforced: ${ENFORCED_DIRS})"

[ "$errors" -eq 0 ] || exit 1
