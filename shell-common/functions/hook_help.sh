#!/bin/sh
# shell-common/functions/hook_help.sh
# Git Hook Configuration Help and Diagnostic

hook_help() {
    ux_header "Git Hook Configuration & Diagnostics"

    ux_section "개요"
    ux_bullet "2-tier Hook 아키텍처: User-level (전역) + Project-level (로컬)"
    ux_bullet "자동 진단 도구로 설정 문제를 쉽게 해결"
    ux_bullet "상세 가이드: git/doc/HOOK_WORKFLOW.md"

    ux_section "주요 명령어"
    ux_table_row "hook-check" "Hook 설정 진단 ⭐" "6가지 자동 체크 + 자동 수정 옵션"
    ux_table_row "hook-check --help" "도움말 보기" "이 페이지 표시"

    ux_section "hook-check 동작 원리"
    ux_bullet "CHECK 1: core.hooksPath 설정 확인"
    ux_bullet "  → git config --global core.hooksPath"
    ux_bullet ""
    ux_bullet "CHECK 2: Hook 파일 존재 확인"
    ux_bullet "  → ~/.config/git/hooks/pre-commit 존재?"
    ux_bullet ""
    ux_bullet "CHECK 3: Hook 파일 권한 확인"
    ux_bullet "  → 실행 가능 파일(+x)인가?"
    ux_bullet ""
    ux_bullet "CHECK 4: 프로젝트 Hook 확인"
    ux_bullet "  → .git/hooks/pre-commit 존재 및 권한?"
    ux_bullet ""
    ux_bullet "CHECK 5: Hook 문법 검증"
    ux_bullet "  → bash -n로 syntax 체크"

    ux_section "실행 방법"
    ux_table_row "hook-check" "대화형 진단 (권장)" "문제 발견 시 자동 수정 제안"
    ux_table_row "bash shell-common/tools/custom/hook_check.sh" "직접 실행" "setup이 필요 없을 때"

    ux_section "진단 결과 해석"
    ux_bullet "✓ = 설정 정상"
    ux_bullet "✗ = 설정 오류 (수정 필요)"
    ux_bullet "⚠ = 경고 (선택적)"

    ux_section "자동 수정하기"
    ux_bullet "hook-check 실행 시 문제 감지되면:"
    ux_bullet "  1. '위 내용을 확인하세요' 메시지 표시"
    ux_bullet "  2. '자동 수정할까요? (y/n)' 질문"
    ux_bullet "  3. 'y' 입력하면 setup.sh 자동 실행"
    ux_bullet "  4. 모든 설정 자동 복구"

    ux_section "수동 수정하기"
    ux_bullet "개별 명령어들:"
    ux_bullet "  1. core.hooksPath 설정:"
    ux_bullet "     git config --global core.hooksPath ~/.config/git/hooks"
    ux_bullet ""
    ux_bullet "  2. Hook 파일 권한 설정:"
    ux_bullet "     chmod +x ~/.config/git/hooks/pre-commit"
    ux_bullet ""
    ux_bullet "  3. 전체 설정 재실행:"
    ux_bullet "     cd ~/dotfiles && ./git/setup.sh"

    ux_section "문제 해결"
    ux_table_row "Hook이 실행 안 됨" "hook-check 실행" "자동 진단 및 수정"
    ux_table_row "core.hooksPath 오류" "'수동 수정' 섹션 참고" "git config 명령 직접 실행"
    ux_table_row "권한 오류" "chmod +x 명령 실행" "Hook 파일을 실행 가능하게"
    ux_table_row "설정 전부 다시 하고 싶음" "setup.sh 재실행" "cd ~/dotfiles && ./git/setup.sh"

    ux_section "Hook 종류"
    ux_bullet "${bold}User-level Hook${reset} (~/.config/git/hooks/pre-commit)"
    ux_bullet "  • 모든 git 프로젝트에 적용 (전역)"
    ux_bullet "  • Secret/Key 감지, Conflict markers 확인 등"
    ux_bullet "  • 빠름: ~150ms"
    ux_bullet ""
    ux_bullet "${bold}Project-level Hook${reset} (dotfiles/.git/hooks/pre-commit)"
    ux_bullet "  • 이 dotfiles 프로젝트에만 적용 (로컬)"
    ux_bullet "  • Shebang, Function naming, UX library 검사 등"
    ux_bullet "  • 상대적으로 느림: ~1-3초"

    ux_section "더 알아보기"
    ux_bullet "자세한 가이드: git/doc/HOOK_WORKFLOW.md"
    ux_bullet "Hook 구현: git/global-hooks/pre-commit"
    ux_bullet "Hook 설정값: git/config/hook-config.sh"
    ux_bullet "Setup 스크립트: git/setup.sh"

    ux_section "팁"
    ux_bullet "hook-check를 주기적으로 실행해서 설정 상태 확인"
    ux_bullet "새 PC에서는 반드시 ./git/setup.sh 실행"
    ux_bullet "Hook 문제 발생 시 GIT_HOOKS_DEBUG=1 환경변수로 디버그 출력"

}
