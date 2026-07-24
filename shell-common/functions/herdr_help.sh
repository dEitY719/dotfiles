#!/bin/sh
# shell-common/functions/herdr_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_herdr_help_summary() {
    ux_info "Usage: herdr-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: agent multiplexer | 세션 유지 | prefix Ctrl+b"
    ux_bullet_sub "pane: split right/down | hjkl 이동 | zoom | rename | close"
    ux_bullet_sub "tab: new | next/prev"
    ux_bullet_sub "workspace: navigation | new"
    ux_bullet_sub "control: detach"
    ux_bullet_sub "example | related"
    ux_bullet_sub "install: 사외 curl|sh · 사내 GitHub 릴리스 바이너리"
    ux_bullet_sub "details: herdr-help <section>  (example: herdr-help pane)"
}

_herdr_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "pane"
    ux_bullet_sub "tab"
    ux_bullet_sub "workspace"
    ux_bullet_sub "control"
    ux_bullet_sub "example"
    ux_bullet_sub "related"
    ux_bullet_sub "install"
}

_herdr_help_rows_concept() {
    ux_bullet "여러 코딩 agent를 한 터미널에서 실행하는 multiplexer"
    ux_bullet "서버에 세션 유지 — 터미널/SSH 끊겨도 agent 계속 동작"
    ux_bullet "모든 단축키: prefix (기본 Ctrl+b) 누른 뒤 해당 키"
}

_herdr_help_rows_pane() {
    ux_table_row "prefix+v" "split right (좌우 분할)"
    ux_table_row "prefix+minus" "split down (상하 분할, horizontal)"
    ux_table_row "prefix+h" "왼쪽 pane으로 이동"
    ux_table_row "prefix+j" "아래 pane으로 이동"
    ux_table_row "prefix+k" "위 pane으로 이동"
    ux_table_row "prefix+l" "오른쪽 pane으로 이동"
    ux_table_row "prefix+z" "현재 pane 풀스크린 토글 (zoom)"
    ux_table_row "prefix+shift+p" "현재 pane 이름 변경"
    ux_table_row "prefix+x" "현재 pane 닫기"
}

_herdr_help_rows_tab() {
    ux_table_row "prefix+c" "새 탭 생성"
    ux_table_row "prefix+n / prefix+p" "다음 / 이전 탭"
}

_herdr_help_rows_workspace() {
    ux_table_row "prefix+w" "workspace 간 이동"
    ux_table_row "prefix+shift+n" "새 workspace 생성"
}

_herdr_help_rows_control() {
    ux_table_row "prefix+q" "세션에서 빠져나오기 (detach client) — agent는 계속 실행"
}

_herdr_help_rows_example() {
    ux_bullet "herdr                    # 세션 시작/재접속"
    ux_bullet "claude                   # pane 안에서 agent 실행"
    ux_bullet "prefix+v                 # 오른쪽 split"
    ux_bullet "prefix+minus             # 아래 split (오른쪽 pane 안에서)"
    ux_bullet "prefix+j / prefix+l 등   # pane 간 이동"
    ux_bullet "prefix+q                 # detach"
    ux_bullet "herdr                    # 나중에 다시 접속, agent 그대로"
}

_herdr_help_rows_related() {
    ux_bullet "Docs: ${UX_BOLD}https://herdr.dev/docs/${UX_RESET}"
    ux_bullet "tmux 사용자라면: ${UX_BOLD}tmux-help${UX_RESET}"
}

_herdr_help_rows_install() {
    ux_bullet "사외(표준): curl -fsSL https://herdr.dev/install.sh | sh  (또는 brew install herdr / mise use -g herdr)"
    ux_bullet "사내(프록시 차단 우회, 권장): curl -fsSL -o ~/.local/bin/herdr https://github.com/ogulcancelik/herdr/releases/latest/download/herdr-linux-x86_64 && chmod +x ~/.local/bin/herdr"
    ux_bullet "사내(버전 고정): 위 URL의 latest/download 대신 download/v0.7.5 로 태그 지정"
    ux_bullet "근본 해결: 프록시 예외 신청 — GSAMS ${UX_BOLD}https://gsams.samsungds.net${UX_RESET}"
}

_herdr_help_render_section() {
    ux_section "$1"
    "$2"
}

_herdr_help_section_rows() {
    case "$1" in
        concept)              _herdr_help_rows_concept ;;
        pane|panes|split)     _herdr_help_rows_pane ;;
        tab|tabs)             _herdr_help_rows_tab ;;
        workspace|workspaces) _herdr_help_rows_workspace ;;
        control)              _herdr_help_rows_control ;;
        example|examples)     _herdr_help_rows_example ;;
        related)              _herdr_help_rows_related ;;
        install)              _herdr_help_rows_install ;;
        *)
            ux_error "Unknown herdr-help section: $1"
            ux_info "Try: herdr-help --list"
            return 1
            ;;
    esac
}

_herdr_help_full() {
    ux_header "herdr - Agent Multiplexer"
    _herdr_help_render_section "Core Concept" _herdr_help_rows_concept
    _herdr_help_render_section "Pane - prefix +" _herdr_help_rows_pane
    _herdr_help_render_section "Tab - prefix +" _herdr_help_rows_tab
    _herdr_help_render_section "Workspace - prefix +" _herdr_help_rows_workspace
    _herdr_help_render_section "Session Control - prefix +" _herdr_help_rows_control
    _herdr_help_render_section "Practical Example" _herdr_help_rows_example
    _herdr_help_render_section "Related Help" _herdr_help_rows_related
    _herdr_help_render_section "Install" _herdr_help_rows_install
}

herdr_help() {
    case "${1:-}" in
        ""|-h|--help|help) _herdr_help_summary ;;
        --list|list|section|sections) _herdr_help_list_sections ;;
        --all|all)          _herdr_help_full ;;
        *)                  _herdr_help_section_rows "$1" ;;
    esac
}

alias herdr-help='herdr_help'
