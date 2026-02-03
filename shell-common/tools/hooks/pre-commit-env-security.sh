#!/bin/sh
# shell-common/tools/hooks/pre-commit-env-security.sh
# Pre-commit Hook: Environment File Security Validation
#
# Purpose:
#   - If git-crypt active: Verify .env is encrypted (SSOT principle)
#   - If git-crypt NOT active: Prevent committing .env (security)
#
# Supports two workflows:
#   1. Current workflow: git-crypt enabled (safe to commit .env)
#   2. Legacy/new-PC workflow: git-crypt disabled (must prevent .env)
#
# Installation:
#   ln -sf "../../shell-common/tools/hooks/pre-commit-env-security.sh" .git/hooks/pre-commit

set -e

# ═══════════════════════════════════════════════════════════════
# Scenario 1: git-crypt IS active
# ═══════════════════════════════════════════════════════════════
if git-crypt status >/dev/null 2>&1; then
    echo "ℹ️  git-crypt detected - validating encryption settings..."
    echo ""

    # Verify .env is in .gitattributes for encryption
    if ! grep -q "\.env" .gitattributes 2>/dev/null; then
        echo "❌ ERROR: .env is NOT in .gitattributes"
        echo "   .env will be committed in plaintext (not encrypted)!"
        echo ""
        echo "Fix: Add to .gitattributes:"
        echo "  .env filter=git-crypt diff=git-crypt"
        echo ""
        echo "Then run:"
        echo "  git-crypt encrypt"
        exit 1
    fi

    # Verify .local files are in .gitattributes for encryption
    if git diff --cached --name-only | grep -E "\.local(\.sh)?$"; then
        echo "⚠️  WARNING: .local files detected in commit"
        echo "   Verify they are in .gitattributes:"
        echo ""
        git diff --cached --name-only | grep -E "\.local(\.sh)?$" | sed 's/^/     /'
        echo ""
        echo "   If NOT encrypted, they will be exposed!"
        echo ""
    fi

    echo "✓ git-crypt encryption verified for sensitive files"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# Scenario 2: git-crypt is NOT active (legacy or new PC)
# ═══════════════════════════════════════════════════════════════
echo "ℹ️  git-crypt NOT active - enforcing environment file security..."
echo ""

# Check 1: Prevent .env commit (API keys, credentials exposed)
if git diff --cached --name-only | grep -q "^\.env$"; then
    echo "❌ ERROR: .env 파일이 평문으로 커밋되려고 합니다!"
    echo ""
    echo "원인:"
    echo "  git-crypt이 활성화되지 않았는데 .env를 커밋하려 함"
    echo "  → 민감한 정보(API 키) 노출 위험 ⚠️"
    echo ""
    echo "해결 방법:"
    echo "  1) git-crypt 설정:"
    echo "     git-crypt init"
    echo "     .gitattributes에 추가:"
    echo "       .env filter=git-crypt diff=git-crypt"
    echo "     git-crypt encrypt"
    echo ""
    echo "  2) 또는 .env를 .gitignore에 추가:"
    echo "     echo '.env' >> .gitignore"
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
exit 0
