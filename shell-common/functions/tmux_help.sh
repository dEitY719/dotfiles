#!/bin/sh
# shell-common/functions/tmux_help.sh

_tmux_help_summary() {
    ux_info "Usage: tmux-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: 세션 유지 | 화면 분할 | prefix Ctrl+b"
    ux_bullet_sub "session: tmux new | attach | ls | kill-session"
    ux_bullet_sub "pane: % | \" | arrow | z | x | Alt+arrow"
    ux_bullet_sub "control: d | s | \$"
    ux_bullet_sub "window: c | n/p | 0-9 | ,"
    ux_bullet_sub "copy: [ | Space | Enter | q | ]"
    ux_bullet_sub "example | companion | custom | related"
    ux_bullet_sub "details: tmux-help <section>  (example: tmux-help session)"
}

_tmux_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "session"
    ux_bullet_sub "pane"
    ux_bullet_sub "control"
    ux_bullet_sub "window"
    ux_bullet_sub "copy"
    ux_bullet_sub "example"
    ux_bullet_sub "companion"
    ux_bullet_sub "custom"
    ux_bullet_sub "related"
}

_tmux_help_rows_concept() {
    ux_bullet "SSH/터미널 종료 후에도 세션 유지"
    ux_bullet "화면 분할로 여러 작업 동시 수행"
    ux_bullet "모든 단축키: Ctrl+b (prefix) 누른 뒤 해당 키"
}

_tmux_help_rows_session() {
    ux_table_row "tmux new -s <name>" "새 세션 생성"
    ux_table_row "tmux attach -t <name>" "세션 다시 연결"
    ux_table_row "tmux ls" "세션 목록 확인"
    ux_table_row "tmux kill-session -t <name>" "세션 삭제"
}

_tmux_help_rows_pane() {
    ux_table_row "%" "좌우 분할"
    ux_table_row "\"" "상하 분할"
    ux_table_row "arrow keys" "패인 이동"
    ux_table_row "z" "현재 패인 전체화면 토글"
    ux_table_row "x" "현재 패인 닫기"
    ux_table_row "Alt+arrow (no prefix)" "패인 크기 조절"
}

_tmux_help_rows_control() {
    ux_table_row "d" "세션에서 빠져나오기 (detach)"
    ux_table_row "s" "세션 목록 선택 이동"
    ux_table_row "\$" "현재 세션 이름 변경"
}

_tmux_help_rows_window() {
    ux_table_row "c" "새 윈도우 생성"
    ux_table_row "n / p" "다음 / 이전 윈도우"
    ux_table_row "0-9" "해당 번호 윈도우로 이동"
    ux_table_row "," "현재 윈도우 이름 변경"
}

_tmux_help_rows_copy() {
    ux_table_row "[" "카피 모드 (스크롤 가능)"
    ux_table_row "Space" "선택 시작 (카피 모드 내)"
    ux_table_row "Enter" "선택 영역 복사 (카피 모드 내)"
    ux_table_row "q" "카피 모드 종료"
    ux_table_row "]" "buffer_0 붙여넣기"
}

_tmux_help_rows_example() {
    ux_bullet "tmux new -s dev        # 세션 시작"
    ux_bullet "Ctrl+b %               # 좌우 분할"
    ux_bullet "오른쪽에서 claude 실행"
    ux_bullet "Ctrl+b z               # 전체화면 토글"
    ux_bullet "Ctrl+b d               # detach"
    ux_bullet "tmux attach -t dev     # 나중에 다시 연결"
}

_tmux_help_rows_companion() {
    ux_table_row "marmonitor" "tmux 상태바 모니터링 플러그인"
    ux_bullet "Install: ${UX_BOLD}npm install -g marmonitor${UX_RESET}"
    ux_bullet "Setup:   ${UX_BOLD}marmonitor setup tmux${UX_RESET}"
    ux_bullet "tmux 안에서 prefix+I 로 플러그인 활성화"
}

_tmux_help_rows_custom() {
    ux_table_row "tmux-spawn [agent]" "3-pane AI 세션 생성"
    ux_table_row "tmux-teardown [name|all]" "세션 정리 (기본: all)"
}

_tmux_help_rows_related() {
    ux_bullet "Cheat sheet: ${UX_BOLD}https://tmuxcheatsheet.com/${UX_RESET}"
    ux_bullet "Terminal: ${UX_BOLD}ghostty-help${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
}

_tmux_help_render_section() {
    ux_section "$1"
    "$2"
}

_tmux_help_section_rows() {
    case "$1" in
        concept)            _tmux_help_rows_concept ;;
        session|sessions)   _tmux_help_rows_session ;;
        pane|panes|split)   _tmux_help_rows_pane ;;
        control)            _tmux_help_rows_control ;;
        window|windows|tab) _tmux_help_rows_window ;;
        copy|scroll)        _tmux_help_rows_copy ;;
        example|examples)   _tmux_help_rows_example ;;
        companion|tools)    _tmux_help_rows_companion ;;
        custom|commands)    _tmux_help_rows_custom ;;
        related)            _tmux_help_rows_related ;;
        *)
            ux_error "Unknown tmux-help section: $1"
            ux_info "Try: tmux-help --list"
            return 1
            ;;
    esac
}

_tmux_help_full() {
    ux_header "tmux - Terminal Multiplexer"
    _tmux_help_render_section "Core Concept" _tmux_help_rows_concept
    _tmux_help_render_section "Session Commands" _tmux_help_rows_session
    _tmux_help_render_section "Pane (Split) - Ctrl+b +" _tmux_help_rows_pane
    _tmux_help_render_section "Session - Ctrl+b +" _tmux_help_rows_control
    _tmux_help_render_section "Window (Tab) - Ctrl+b +" _tmux_help_rows_window
    _tmux_help_render_section "Scroll & Copy - Ctrl+b +" _tmux_help_rows_copy
    _tmux_help_render_section "Practical Example" _tmux_help_rows_example
    _tmux_help_render_section "Companion Tools" _tmux_help_rows_companion
    _tmux_help_render_section "Custom Commands" _tmux_help_rows_custom
    _tmux_help_render_section "Related Help" _tmux_help_rows_related
}

tmux_help() {
    case "${1:-}" in
        ""|-h|--help|help) _tmux_help_summary ;;
        --list|list)        _tmux_help_list_sections ;;
        --all|all)          _tmux_help_full ;;
        *)                  _tmux_help_section_rows "$1" ;;
    esac
}

alias tmux-help='tmux_help'
