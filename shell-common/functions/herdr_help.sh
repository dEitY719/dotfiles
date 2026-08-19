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
    ux_bullet_sub "plugin: 설치된 플러그인 | 키바인딩 | herdr plugin CLI"
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
    ux_bullet_sub "plugin"
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

_herdr_help_rows_plugin() {
    ux_section "설치된 플러그인"
    ux_table_header "plugin_id" "설치 소스 (owner/repo)" "액션 — 용도"
    ux_table_row "herdr-file-viewer" "smarzban/herdr-file-viewer" "open-file-viewer[-tab] — git-aware 파일 뷰어"
    ux_table_row "persiyanov.reviewr" "persiyanov/herdr-reviewr" "toggle — agent diff 코드리뷰 페인"
    ux_table_row "ray.plugin-manager" "speardragon/herdr-plugin-manager" "open — 플러그인 매니저 팝업"
    ux_bullet "현재 설치 상태는 ${UX_BOLD}herdr plugin list${UX_RESET} 가 SSOT — 위 표는 기본 구성"

    ux_section "신규 PC 부트스트랩"
    ux_bullet "${UX_BOLD}./setup.sh${UX_RESET} 한 번이면 config 심링크 + 플러그인 + 외부 바이너리까지 끝 (멱등)"
    ux_bullet "플러그인 herdr/plugins.conf · 외부 바이너리 herdr/tools.conf (lazygit · glow · delta · bat)"
    ux_bullet "외부 바이너리는 ${UX_BOLD}gh auth login${UX_RESET} 이 끝나 있어야 한다 — 익명 GitHub API 는 IP 당 60회/시간이라 공용 사내 IP 에서 먼저 소진된다"
    ux_bullet "설치 실패는 경고만 남기고 넘어간다 — 플러그인이 없으면 키바인딩이 무동작, 렌더러가 없으면 뷰어가 plain text"
    ux_bullet "HERDR_SKIP_PLUGINS=1 / HERDR_SKIP_TOOLS=1 ./setup.sh   # 각 단계 건너뛰기"

    ux_section "키바인딩"
    ux_bullet "커스텀 명령은 ${UX_BOLD}prefix+ctrl+<letter>${UX_RESET} 로 통일 (내장 액션과 충돌 회피)"
    ux_table_header "Key" "Action"
    ux_table_row "prefix+ctrl+f" "파일 뷰어 (split)"
    ux_table_row "prefix+ctrl+t" "파일 뷰어 (별도 tab)"
    ux_table_row "prefix+ctrl+r" "reviewr 토글"
    ux_table_row "prefix+ctrl+p" "플러그인 매니저 열기"
    ux_table_row "prefix+ctrl+g" "lazygit 팝업 (플러그인 아님 — tools.conf 로 설치)"

    ux_section "herdr plugin CLI"
    ux_bullet "herdr plugin install <owner>/<repo>              # 부트스트랩 실패분 수동 재시도"
    ux_bullet "herdr plugin uninstall <plugin-id>               # 업데이트는 uninstall 후 재설치"
    ux_bullet "herdr plugin list                                # 설치 목록 + plugin_id + config 경로"
    ux_bullet "herdr plugin enable|disable <plugin-id>"
    ux_bullet "herdr plugin config-dir <plugin-id>              # 플러그인별 설정 디렉터리"
    ux_bullet "herdr plugin log list                            # 실행 로그 (--plugin ID, --limit N)"
    ux_bullet "herdr plugin action list                         # 호출 가능한 액션 전체 (JSON)"
    ux_bullet "herdr plugin action invoke <action> --plugin <plugin-id>   # 액션명은 위 표 참조"
    ux_bullet "herdr plugin link <path> / unlink <plugin-id>    # 복제 없이 작업 디렉터리 연결"

    ux_section "설정"
    ux_bullet "config.toml 은 dotfiles SSOT (herdr/config.toml) 심링크"
    ux_bullet "herdr config check                               # 문법 검증 (내장 액션과의 키 충돌은 검사하지 않음)"
    ux_bullet "herdr server reload-config                       # 재시작 없이 반영"
    ux_bullet "HERDR_CONFIG_PATH=/tmp/try.toml herdr config check  # 실제 설정을 건드리지 않고 후보 검증"
    ux_bullet "파일 뷰어 렌더러 glow · delta · bat — setup.sh 가 설치, PATH 에 있으면 자동 사용"
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
    ux_bullet "사외(표준, 전 OS): curl -fsSL https://herdr.dev/install.sh | sh  (또는 brew install herdr / mise use -g herdr)"
    ux_bullet "사내(프록시 차단 우회, Linux x86_64 전용): curl -fsSL -o ~/.local/bin/herdr https://github.com/ogulcancelik/herdr/releases/latest/download/herdr-linux-x86_64 && chmod +x ~/.local/bin/herdr"
    ux_bullet "macOS/Apple Silicon 사내망: 위 바이너리는 Linux 전용 — 사외(표준) brew/mise 경로 사용 또는 releases 페이지에서 darwin 자산명 확인"
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
        plugin|plugins)       _herdr_help_rows_plugin ;;
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
    _herdr_help_render_section "Plugin" _herdr_help_rows_plugin
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
