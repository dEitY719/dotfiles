#!/bin/sh
# shell-common/tools/hooks/pre-commit-env-security.sh
# Pre-commit Hook: Environment File Security Validation
#
# Purpose:
#   - Block any commit that adds .env or *.local files. Secrets must live
#     outside the repo (1Password / ~/.config/dotfiles-secrets/ / USB).
#   - git-crypt support removed in #594.
#
# Installation:
#   ln -sf "../../shell-common/tools/hooks/pre-commit-env-security.sh" .git/hooks/pre-commit

set -e

# Check 1: Prevent .env commit (API keys, credentials exposed)
if git diff --cached --name-only | grep -q "^\.env$"; then
    echo "❌ ERROR: .env 파일이 평문으로 커밋되려고 합니다!"
    echo ""
    echo "원인:"
    echo "  .env 는 시크릿이므로 repo 추적 금지 (#594)"
    echo ""
    echo "해결 방법:"
    echo "  echo '.env' >> .gitignore"
    echo "  git reset HEAD .env"
    echo ""
    echo "원본은 1Password / ~/.config/dotfiles-secrets/ / USB 등 외부에 보관."
    echo ""
    exit 1
fi

# Check 2: Prevent .local files commit (.local.sh, *.local etc)
if git diff --cached --name-only | grep -E "\.local(\.sh)?$"; then
    echo "❌ ERROR: .local 파일이 커밋되려고 합니다!"
    echo ""
    echo "민감한 파일:"
    git diff --cached --name-only | grep -E "\.local(\.sh)?$" | sed 's/^/  - /'
    echo ""
    echo ".local 파일은 환경별 설정이므로 커밋하면 안 됩니다."
    echo "해결: .gitignore에 추가"
    echo "  *.local"
    echo "  *.local.sh"
    exit 1
fi

echo "✓ 환경 파일 보안 검사 통과"
echo "  (민감한 파일 커밋 방지됨)"

# ═══════════════════════════════════════════════════════════════
# Check 3: Detect duplicate UX function definitions
# Prevents issues like multiple files defining fallback ux_header
# ═══════════════════════════════════════════════════════════════
echo ""
echo "🔍 검사: 중복된 UX 함수 정의..."

FUNCTIONS_TO_CHECK="ux_header ux_section ux_bullet ux_info ux_success ux_error"
DUPLICATE_FOUND=0

for func in $FUNCTIONS_TO_CHECK; do
    # Count definitions (excluding ux_lib.sh which is the source of truth)
    COUNT=$(grep -r "^${func}()" shell-common --include="*.sh" 2>/dev/null | grep -v "ux_lib.sh" | wc -l)

    if [ "$COUNT" -gt 1 ]; then
        echo "❌ ERROR: '${func}' 함수가 여러 파일에서 정의되었습니다:"
        grep -r "^${func}()" shell-common --include="*.sh" 2>/dev/null | grep -v "ux_lib.sh" | cut -d: -f1 | sed 's/^/     /'
        DUPLICATE_FOUND=1
    fi
done

if [ "$DUPLICATE_FOUND" -eq 1 ]; then
    echo ""
    echo "해결 방법:"
    echo "  1) shell-common/tools/ux_lib/ux_lib.sh에서 함수가 정의됨"
    echo "  2) 다른 파일의 fallback 정의 제거"
    echo "  3) 대신 절대 경로로 ux_lib.sh 로드:"
    echo "     source /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh"
    exit 1
fi

echo "✓ UX 함수 중복 정의 검사 통과"
exit 0
