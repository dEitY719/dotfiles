#!/bin/sh
# shell-common/functions/hook_help.sh

hook_help() {
    ux_header "Git Hook Configuration & Diagnostics"

    ux_section "개요"
    ux_bullet "2-tier Hook 아키텍처: User-level (전역) + Project-level (로컬)"
    ux_bullet "자동 진단 도구로 설정 문제를 쉽게 해결"
    ux_bullet "상세 가이드: git/doc/HOOK_WORKFLOW.md"

    ux_section "주요 명령어"
    ux_table_row "hook-check" "Hook 설정 진단 ⭐" "6가지 자동 체크 + 자동 수정 옵션"
    ux_table_row "hook-check --help" "도움말 보기" "이 페이지 표시"

    ux_section "진단 결과 해석"
    ux_bullet "✓ = 설정 정상"
    ux_bullet "✗ = 설정 오류 (수정 필요)"
    ux_bullet "⚠ = 경고 (선택적)"

    ux_section "문제 해결"
    ux_table_row "Hook이 실행 안 됨" "hook-check 실행" "자동 진단 및 수정"
    ux_table_row "core.hooksPath 오류" "git config 명령 직접 실행"
    ux_table_row "권한 오류" "chmod +x 명령 실행" "Hook 파일을 실행 가능하게"
    ux_table_row "설정 전부 다시" "setup.sh 재실행" "cd ~/dotfiles && ./git/setup.sh"

    ux_section "Hook 종류"
    ux_table_row "User-level" "~/.config/git/hooks/pre-commit" "모든 git 프로젝트에 적용 (전역)"
    ux_table_row "Project-level" "dotfiles/.git/hooks/pre-commit" "이 dotfiles 프로젝트에만 적용"

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
