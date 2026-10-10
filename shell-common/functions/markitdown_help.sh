#!/bin/sh
# shell-common/functions/markitdown_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_markitdown_help_summary() {
    ux_info "Usage: markitdown-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "install: global-packages (uv-tools.txt) | Python 3.12 + pip-system-certs"
    ux_bullet_sub "usage: wrapper 자동 저장 | --output-path | 이름 규칙"
    ux_bullet_sub "examples: 파일 | YouTube URL | 저장 위치 지정 | stdin"
    ux_bullet_sub "troubleshoot: CERTIFICATE_VERIFY_FAILED | --output-path 미인식 | URL 따옴표"
    ux_bullet_sub "details: markitdown-help <section>  (example: markitdown-help usage)"
}

_markitdown_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "install"
    ux_bullet_sub "usage"
    ux_bullet_sub "examples"
    ux_bullet_sub "troubleshoot"
}

_markitdown_help_rows_install() {
    ux_bullet "markitdown 은 ${UX_BOLD}global-packages${UX_RESET} 로 관리 — 문서/URL → Markdown 변환 CLI"
    ux_bullet "SSOT: ${UX_BOLD}global-packages/uv-tools.txt${UX_RESET} 의 줄 ${UX_BOLD}markitdown[all] --python 3.12 --with pip-system-certs${UX_RESET}"
    ux_bullet "설치: ${UX_BOLD}./global-packages/setup.sh${UX_RESET} (또는 ${UX_BOLD}./setup.sh${UX_RESET})"
    ux_bullet "수동: ${UX_BOLD}uv tool install --native-tls --python 3.12 --with pip-system-certs --force 'markitdown[all]'${UX_RESET}"
    ux_bullet "확인: ${UX_BOLD}markitdown --version${UX_RESET}"
    ux_bullet "이미 설치된 PC: uv receipt 의 --python/--with 가 uv-tools.txt 와 다르면 setup.sh 가 --force 재설치"
}

_markitdown_help_rows_usage() {
    ux_bullet "${UX_BOLD}markitdown <파일|URL>${UX_RESET} — stdout 이 터미널이면 현재 디렉토리에 ${UX_BOLD}<이름>.md${UX_RESET} 저장"
    ux_bullet "${UX_BOLD}--output-path DIR${UX_RESET} (또는 ${UX_BOLD}--output-path=DIR${UX_RESET}) — DIR 에 저장, 없으면 생성"
    ux_bullet "기존 파일은 덮어쓰지 않는다"
    ux_bullet "원본 stdout 동작: ${UX_BOLD}-o FILE${UX_RESET} 지정 / stdin 입력 / ${UX_BOLD}>${UX_RESET}·${UX_BOLD}|${UX_RESET} 리다이렉트"
    ux_bullet "인자 없이 TTY 에서 실행 → --help 출력 (stdin 대기로 멈추지 않음)"

    ux_section "저장 이름 규칙"
    ux_bullet "로컬 파일: 확장자 제거 (report.pdf → report.md)"
    ux_bullet "URL: query/fragment 를 떼고 마지막 경로 조각"
    ux_bullet "YouTube ${UX_BOLD}watch?v=ID${UX_RESET} → ID"

    ux_section "주의"
    ux_bullet "wrapper 는 interactive 셸 전용 — 스크립트에서는 원본 markitdown 동작"
    ux_bullet "wrapper 수정 후 기존 터미널은 ${UX_BOLD}exec zsh${UX_RESET} 로 다시 로드"
}

_markitdown_help_rows_examples() {
    ux_bullet "markitdown report.pdf                              # ./report.md"
    ux_bullet "markitdown 'https://youtube.com/shorts/ID?si=x'    # ./ID.md"
    ux_bullet "markitdown 'URL' --output-path ~/para/project/obsidian-para/99-Inbox/YouTube"
    ux_bullet "markitdown doc.docx -o out.md                      # 원본 -o 동작"
    ux_bullet "cat a.pdf | markitdown -x pdf > a.md               # stdin + 리다이렉트"
}

_markitdown_help_rows_troubleshoot() {
    ux_section "1. CERTIFICATE_VERIFY_FAILED"
    ux_bullet "증상: ${UX_BOLD}Missing Authority Key Identifier${UX_RESET} 또는 ${UX_BOLD}unable to get local issuer certificate${UX_RESET}"
    ux_bullet "원인: 사내 프록시 CA 에 AKI 가 없음 + Python 3.13+ 의 strict X509 검증"
    ux_bullet "해결: install 섹션 수동 명령으로 Python 3.12 + pip-system-certs 재설치"

    ux_section "2. unrecognized arguments: --output-path"
    ux_bullet "원인: 셸에 옛 wrapper 가 로드돼 있음"
    ux_bullet "해결: ${UX_BOLD}exec zsh${UX_RESET}"

    ux_section "3. URL 따옴표"
    ux_bullet "URL 은 작은따옴표로 감싼다"
    ux_bullet "큰따옴표 안의 ${UX_BOLD}\\?${UX_RESET} 는 backslash 가 URL 에 그대로 남는다"
}

_markitdown_help_render_section() {
    ux_section "$1"
    "$2"
}

_markitdown_help_section_rows() {
    case "$1" in
        install)                    _markitdown_help_rows_install ;;
        usage)                      _markitdown_help_rows_usage ;;
        example|examples)           _markitdown_help_rows_examples ;;
        troubleshoot|troubleshooting) _markitdown_help_rows_troubleshoot ;;
        *)
            ux_error "Unknown markitdown-help section: $1"
            ux_info "Try: markitdown-help --list"
            return 1
            ;;
    esac
}

_markitdown_help_full() {
    ux_header "markitdown - Document/URL to Markdown Converter"
    _markitdown_help_render_section "Install" _markitdown_help_rows_install
    _markitdown_help_render_section "Usage" _markitdown_help_rows_usage
    _markitdown_help_render_section "Examples" _markitdown_help_rows_examples
    _markitdown_help_render_section "Troubleshoot" _markitdown_help_rows_troubleshoot
}

markitdown_help() {
    case "${1:-}" in
        ""|-h|--help|help) _markitdown_help_summary ;;
        --list|list|section|sections) _markitdown_help_list_sections ;;
        --all|all)          _markitdown_help_full ;;
        *)                  _markitdown_help_section_rows "$1" ;;
    esac
}

alias markitdown-help='markitdown_help'
