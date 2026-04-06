#!/bin/sh
# shell-common/functions/tmux_help.sh

tmux_help() {
    ux_header "tmux - Terminal Multiplexer"

    ux_section "Core Concept"
    ux_bullet "SSH/터미널 종료 후에도 세션 유지"
    ux_bullet "화면 분할로 여러 작업 동시 수행"
    ux_bullet "모든 단축키: Ctrl+b (prefix) 누른 뒤 해당 키"

    ux_section "Session Commands"
    ux_table_row "tmux new -s <name>" "새 세션 생성"
    ux_table_row "tmux attach -t <name>" "세션 다시 연결"
    ux_table_row "tmux ls" "세션 목록 확인"
    ux_table_row "tmux kill-session -t <name>" "세션 삭제"

    ux_section "Pane (Split) - Ctrl+b +"
    ux_table_row "%" "좌우 분할"
    ux_table_row "\"" "상하 분할"
    ux_table_row "arrow keys" "패인 이동"
    ux_table_row "z" "현재 패인 전체화면 토글"
    ux_table_row "x" "현재 패인 닫기"
    ux_table_row "Alt+arrow (no prefix)" "패인 크기 조절"

    ux_section "Session - Ctrl+b +"
    ux_table_row "d" "세션에서 빠져나오기 (detach)"
    ux_table_row "s" "세션 목록 선택 이동"
    ux_table_row "\$" "현재 세션 이름 변경"

    ux_section "Window (Tab) - Ctrl+b +"
    ux_table_row "c" "새 윈도우 생성"
    ux_table_row "n / p" "다음 / 이전 윈도우"
    ux_table_row "0-9" "해당 번호 윈도우로 이동"
    ux_table_row "," "현재 윈도우 이름 변경"

    ux_section "Scroll & Copy - Ctrl+b +"
    ux_table_row "[" "카피 모드 (스크롤 가능)"
    ux_table_row "Space" "선택 시작 (카피 모드 내)"
    ux_table_row "Enter" "선택 영역 복사 (카피 모드 내)"
    ux_table_row "q" "카피 모드 종료"
    ux_table_row "]" "buffer_0 붙여넣기"

    ux_section "Practical Example"
    ux_bullet "tmux new -s dev        # 세션 시작"
    ux_bullet "Ctrl+b %               # 좌우 분할"
    ux_bullet "오른쪽에서 claude 실행"
    ux_bullet "Ctrl+b z               # 전체화면 토글"
    ux_bullet "Ctrl+b d               # detach"
    ux_bullet "tmux attach -t dev     # 나중에 다시 연결"

    ux_section "Companion Tools"
    ux_table_row "marmonitor" "tmux 상태바 모니터링 플러그인"
    ux_bullet "Install: ${UX_BOLD}npm install -g marmonitor${UX_RESET}"
    ux_bullet "Setup:   ${UX_BOLD}marmonitor setup tmux${UX_RESET}"
    ux_bullet "tmux 안에서 prefix+I 로 플러그인 활성화"

    ux_section "Custom Commands"
    ux_table_row "tmux-spawn [agent]" "3-pane AI 세션 생성"
    ux_table_row "tmux-teardown [name|all]" "세션 정리 (기본: all)"

    ux_section "Related Help"
    ux_bullet "Cheat sheet: ${UX_BOLD}https://tmuxcheatsheet.com/${UX_RESET}"
    ux_bullet "Terminal: ${UX_BOLD}ghostty-help${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
}

alias tmux-help='tmux_help'
