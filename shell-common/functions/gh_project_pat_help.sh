#!/bin/sh
# shell-common/functions/gh_project_pat_help.sh
# gh-project-pat 도움말 (issue #2064). 이 row 함수들이 PAT 생성 안내의 SSOT 다:
# `gh-project-pat guide` 와 docs/guide/commands/gh-project-pat.md 가 같은
# _gh_project_pat_help_rows_guide 를 쓴다.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gh_project_pat_help_summary() {
    ux_info "Usage: gh-project-pat <guide|set|status> [--host HOST] [options]"
    ux_bullet "순서: guide (PAT 발급) -> set (dry-run 확인) -> set --apply (등록) -> status (존재 확인)"
    ux_bullet "sections"
    ux_bullet_sub "guide: classic PAT 생성 경로 + project/repo scope"
    ux_bullet_sub "set: 여러 저장소에 PROJECT_BOARD_PAT 등록 (기본 dry-run, --apply 로 쓰기)"
    ux_bullet_sub "status: 각 저장소의 PROJECT_BOARD_PAT 존재 여부"
    ux_bullet_sub "options: --host / --owner / --repo / --repo-pattern / 종료 코드"
    ux_bullet_sub "details: gh-project-pat-help <section>  (example: gh-project-pat-help set)"
}

_gh_project_pat_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "guide"
    ux_bullet_sub "set"
    ux_bullet_sub "status"
    ux_bullet_sub "options"
}

# $1: host (생략 시 <host> placeholder — 생성 문서용). gh_project_pat.sh 가 전달.
# shellcheck disable=SC2120
_gh_project_pat_help_rows_guide() {
    ux_bullet "URL: https://${1:-<host>}/settings/tokens/new"
    ux_bullet "메뉴: Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token"
    ux_bullet "fine-grained PAT 생성 화면으로 들어갔다면 왼쪽 메뉴의 Tokens (classic) 으로 이동"
    ux_numbered 1 "Note 입력 (예: skills-plugins-board)"
    ux_numbered 2 "Expiration 선택 (만료 시 새 PAT 로 set --apply 재실행)"
    ux_numbered 3 "scope 선택: project (보드 쓰기) + repo (비공개 이슈/PR 접근)"
    ux_numbered 4 "Generate token 클릭"
    ux_numbered 5 "표시된 토큰을 복사 (화면을 떠나면 다시 볼 수 없음)"
    ux_bullet "다음: gh-project-pat set --host ${1:-<host>} --owner <owner>  (dry-run)"
}

_gh_project_pat_help_rows_set() {
    ux_table_row "set" "대상/개수만 표시 (dry-run)" "PAT 입력/쓰기 없음"
    ux_table_row "set --apply" "PAT 를 TTY 에서 한 번 숨김 입력 -> 각 repo 에 등록" "gh secret set 의 stdin 으로만 전달"
    ux_bullet "예: gh-project-pat set --host github.com --owner <owner> --apply"
    ux_bullet "예: gh-project-pat set --repo <owner>/repo-a --repo <owner>/repo-b --apply"
    ux_bullet "한 repo 실패가 나머지를 막지 않음 -> 마지막에 성공/실패 합계, 실패가 있으면 종료 코드 1"
    ux_bullet "재실행은 같은 secret 을 갱신하므로 수렴. 중단돼도 이미 쓴 secret 은 rollback 하지 않음"
    ux_bullet "TTY 없음 / 빈 입력 / Ctrl-C 는 secret 을 쓰기 전에 종료"
    ux_bullet "PAT 는 인자/환경변수/출력/파일에 남기지 않음. gh auth token 등 다른 토큰을 대신 쓰지 않음"
}

_gh_project_pat_help_rows_status() {
    ux_table_row "status" "각 repo 의 PROJECT_BOARD_PAT 존재 여부" "gh secret list 메타데이터만 조회"
    ux_bullet "예: gh-project-pat status --host github.com --owner <owner>"
    ux_bullet "존재는 PAT 의 scope/만료나 board-sync 성공을 보증하지 않음 -> workflow 실행으로 별도 확인"
    ux_bullet "누락 또는 조회 오류가 하나라도 있으면 종료 코드 1"
}

_gh_project_pat_help_rows_options() {
    ux_table_row "--host HOST" "대상 GitHub host" "생략 시 _gh_resolve_host (setup mode 기반)"
    ux_table_row "--owner OWNER" "저장소 owner" "생략 시 host 의 인증 사용자"
    ux_table_row "--repo OWNER/REPO" "대상 직접 지정 (반복 가능)" "owner 불일치는 입력 오류"
    ux_table_row "--repo-pattern P" "저장소 이름 glob (기본 *-skills)" "--repo 와 동시 사용 불가"
    ux_table_row "--dry-run | --apply" "set 의 쓰기 여부 (기본 dry-run)" "동시 지정은 입력 오류"
    ux_bullet "비공개 저장소 포함, 목록은 마지막 페이지까지 조회"
    ux_bullet "종료 코드: 0 정상 | 1 일부 실패/누락/대상 0개/TTY 없음 | 2 잘못된 옵션/host/owner"
    ux_bullet "요구: gh (대상 host 에 gh auth login --hostname HOST), python3"
}

_gh_project_pat_help_section_rows() {
    case "$1" in
        guide) _gh_project_pat_help_rows_guide ;;
        set | apply) _gh_project_pat_help_rows_set ;;
        status) _gh_project_pat_help_rows_status ;;
        options | opts) _gh_project_pat_help_rows_options ;;
        *)
            ux_error "Unknown gh-project-pat-help section: $1"
            ux_info "Try: gh-project-pat-help --list"
            return 1
            ;;
    esac
}

_gh_project_pat_help_full() {
    ux_header "gh-project-pat: PROJECT_BOARD_PAT 관리"
    ux_section "guide: PAT 생성"
    _gh_project_pat_help_rows_guide
    ux_section "set: secret 등록"
    _gh_project_pat_help_rows_set
    ux_section "status: 존재 확인"
    _gh_project_pat_help_rows_status
    ux_section "options"
    _gh_project_pat_help_rows_options
}

gh_project_pat_help() {
    case "${1:-}" in
        "" | -h | --help | help) _gh_project_pat_help_summary ;;
        --list | list | section | sections) _gh_project_pat_help_list_sections ;;
        --all | all) _gh_project_pat_help_full ;;
        *) _gh_project_pat_help_section_rows "$1" ;;
    esac
}

alias gh-project-pat-help='gh_project_pat_help'
