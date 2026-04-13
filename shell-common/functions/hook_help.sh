#!/bin/sh
# shell-common/functions/hook_help.sh

_hook_help_summary() {
    ux_info "Usage: hook-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: 2-tier (user + project) | 자동 진단 | HOOK_WORKFLOW.md"
    ux_bullet_sub "commands: hook-check | hook-check --help"
    ux_bullet_sub "results: ✓ 정상 | ✗ 오류 | ⚠ 경고"
    ux_bullet_sub "trouble: hook 안 됨 | hooksPath | 권한 | 재실행"
    ux_bullet_sub "types: User-level | Project-level"
    ux_bullet_sub "more: HOOK_WORKFLOW.md | global-hooks | hook-config | setup.sh"
    ux_bullet_sub "tips: 주기적 점검 | 새 PC 셋업 | GIT_HOOKS_DEBUG"
    ux_bullet_sub "details: hook-help <section>  (example: hook-help commands)"
}

_hook_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "commands"
    ux_bullet_sub "results"
    ux_bullet_sub "trouble"
    ux_bullet_sub "types"
    ux_bullet_sub "more"
    ux_bullet_sub "tips"
}

_hook_help_rows_overview() {
    ux_bullet "2-tier Hook 아키텍처: User-level (전역) + Project-level (로컬)"
    ux_bullet "자동 진단 도구로 설정 문제를 쉽게 해결"
    ux_bullet "상세 가이드: git/doc/HOOK_WORKFLOW.md"
}

_hook_help_rows_commands() {
    ux_table_row "hook-check" "Hook 설정 진단 ⭐" "6가지 자동 체크 + 자동 수정 옵션"
    ux_table_row "hook-check --help" "도움말 보기" "이 페이지 표시"
}

_hook_help_rows_results() {
    ux_bullet "✓ = 설정 정상"
    ux_bullet "✗ = 설정 오류 (수정 필요)"
    ux_bullet "⚠ = 경고 (선택적)"
}

_hook_help_rows_trouble() {
    ux_table_row "Hook이 실행 안 됨" "hook-check 실행" "자동 진단 및 수정"
    ux_table_row "core.hooksPath 오류" "git config 명령 직접 실행"
    ux_table_row "권한 오류" "chmod +x 명령 실행" "Hook 파일을 실행 가능하게"
    ux_table_row "설정 전부 다시" "setup.sh 재실행" "cd ~/dotfiles && ./git/setup.sh"
}

_hook_help_rows_types() {
    ux_table_row "User-level" "~/.config/git/hooks/pre-commit" "모든 git 프로젝트에 적용 (전역)"
    ux_table_row "Project-level" "dotfiles/.git/hooks/pre-commit" "이 dotfiles 프로젝트에만 적용"
}

_hook_help_rows_more() {
    ux_bullet "자세한 가이드: git/doc/HOOK_WORKFLOW.md"
    ux_bullet "Hook 구현: git/global-hooks/pre-commit"
    ux_bullet "Hook 설정값: git/config/hook-config.sh"
    ux_bullet "Setup 스크립트: git/setup.sh"
}

_hook_help_rows_tips() {
    ux_bullet "hook-check를 주기적으로 실행해서 설정 상태 확인"
    ux_bullet "새 PC에서는 반드시 ./git/setup.sh 실행"
    ux_bullet "Hook 문제 발생 시 GIT_HOOKS_DEBUG=1 환경변수로 디버그 출력"
}

_hook_help_render_section() {
    ux_section "$1"
    "$2"
}

_hook_help_section_rows() {
    case "$1" in
        overview)           _hook_help_rows_overview ;;
        commands|cmds)      _hook_help_rows_commands ;;
        results|legend)     _hook_help_rows_results ;;
        trouble|troubleshooting) _hook_help_rows_trouble ;;
        types|kinds)        _hook_help_rows_types ;;
        more|docs|references) _hook_help_rows_more ;;
        tips)               _hook_help_rows_tips ;;
        *)
            ux_error "Unknown hook-help section: $1"
            ux_info "Try: hook-help --list"
            return 1
            ;;
    esac
}

_hook_help_full() {
    ux_header "Git Hook Configuration & Diagnostics"
    _hook_help_render_section "개요" _hook_help_rows_overview
    _hook_help_render_section "주요 명령어" _hook_help_rows_commands
    _hook_help_render_section "진단 결과 해석" _hook_help_rows_results
    _hook_help_render_section "문제 해결" _hook_help_rows_trouble
    _hook_help_render_section "Hook 종류" _hook_help_rows_types
    _hook_help_render_section "더 알아보기" _hook_help_rows_more
    _hook_help_render_section "팁" _hook_help_rows_tips
}

hook_help() {
    case "${1:-}" in
        ""|-h|--help|help) _hook_help_summary ;;
        --list|list)        _hook_help_list_sections ;;
        --all|all)          _hook_help_full ;;
        *)                  _hook_help_section_rows "$1" ;;
    esac
}

alias hook-help='hook_help'
