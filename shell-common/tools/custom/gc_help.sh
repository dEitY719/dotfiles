#!/bin/bash
# shell-common/tools/custom/gc_help.sh
# git-crypt help reference - run explicitly via gchelp/gc-help alias

# Source UX library for formatting functions
source "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/ux_lib/ux_lib.sh"

main() {
    ux_header "git-crypt Helper Commands"
    echo ""

    ux_section "📚 주요 명령어"
    echo ""
    ux_bullet "gc-check          : 🔍 git-crypt 상태 진단 (Health Check)"
    ux_bullet "gc-init           : git-crypt 초기화 (1회만)"
    ux_bullet "gc-setup          : git-crypt 초기 설정 (대화형)"
    ux_bullet "gc-new-pc         : 새 PC에서 한 번에 설정"
    ux_bullet "gc-push           : .env 파일 암호화 & 한 번에 push"
    ux_bullet "gc-backup         : GPG 개인키 백업 (GitHub에 안전하게 업로드)"
    ux_bullet "gc-restore        : GPG 개인키 복원"
    ux_bullet "gc-unlock         : git-crypt unlock (저장소 복호화)"
    ux_bullet "gc-lock           : git-crypt lock (저장소 암호화)"
    ux_bullet "gc-status         : git-crypt 상태 확인"
    ux_bullet "gc-ls             : 암호화된 파일 목록"
    ux_bullet "gc-add-me         : 내 GPG 키 자동 추가"
    ux_bullet "gc-setup-cache    : GPG agent 캐싱 설정 (편의성)"
    ux_bullet "gc-purge          : GPG agent 캐시 초기화"
    echo ""

    ux_section "⚠️  자주 발생하는 문제"
    echo ""
    ux_bullet "문제 1: git reset --hard 후 unstaged files 남음"
    echo "        → 원인: git-crypt unlock 상태에서 reset 실행"
    echo "        → 해결:"
    echo "           1. gc-lock (또는 git-crypt lock)"
    echo "           2. git reset --hard upstream/main"
    echo "           3. gc-unlock (필요시)"
    echo ""

    ux_bullet "문제 2: .secrets/ 파일이 추적됨"
    echo "        → 원인: .gitignore 설정 누락"
    echo "        → 확인: grep '.secrets' .gitignore"
    echo "        → 해결: echo '.secrets/*.asc' >> .gitignore"
    echo ""

    ux_bullet "문제 3: git-crypt unlock 실패"
    echo "        → 원인: GPG 개인키 없음 또는 잘못된 키"
    echo "        → 해결:"
    echo "           1. gpg --list-secret-keys (키 확인)"
    echo "           2. gc-restore (기존 키 복원)"
    echo "           3. git-crypt unlock (다시 시도)"
    echo ""

    echo "💡 더 많은 정보:"
    echo "   gc-check   : 🔍 종합 상태 진단 (항상 실행 권장!)"
    echo "   gc-setup   : 초기 설정 가이드"
    echo "   gc-new-pc  : 새 PC 온보딩"
    echo ""
}

# Direct-exec guard: runs main() only if executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
