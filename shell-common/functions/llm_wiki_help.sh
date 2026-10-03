#!/bin/sh
# shell-common/functions/llm_wiki_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_llm_wiki_help_summary() {
    ux_info "Usage: llm-wiki-help [section|--list|--all]"
    ux_bullet "vault 커맨드 (.claude/commands/)"
    ux_bullet_sub "/ingest [파일]: 99-Inbox 소스 1건 PARA 분류·이동 + 00-wiki 융합 (인자 없으면 큐 나열)"
    ux_bullet_sub "/query {질문}: 위키 근거 답변 (근거 없으면 없다고 선언)"
    ux_bullet_sub "/lint: 기계+판단 검사 보고서 (자동 수정 안 함)"
    ux_bullet_sub "/theme {주제}: 새 추적 테마 개설 + 기존 페이지 근거 수집"
    ux_bullet_sub "/archive {경로}: 40-Archive 로 이동 + 위키 링크 재작성 (이동은 이것만)"
    ux_bullet "클립 스킬 (vault 밖)"
    ux_bullet_sub "/pkm:obsidian-web-clip <url>: 99-Inbox/Web/"
    ux_bullet_sub "/pkm:obsidian-session-clip: 99-Inbox/ai-session/"
    ux_bullet "flow: 클립 -> 99-Inbox -> /ingest -> 00-wiki · index.md · log.md"
    ux_bullet_sub "details: llm-wiki-help <section>  (sections: commands clip flow related)"
}

_llm_wiki_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "clip"
    ux_bullet_sub "flow"
    ux_bullet_sub "related"
}

_llm_wiki_help_rows_commands() {
    ux_table_row "/ingest [파일]" "99-Inbox 소스 1건을 PARA 로 분류·이동하고 00-wiki 에 융합. 인자 없으면 큐 나열"
    ux_table_row "/query {질문}" "위키에 근거한 답변. 근거가 없으면 없다고 선언"
    ux_table_row "/lint" "기계 검사 + 판단 검사 보고서. 자동 수정하지 않음"
    ux_table_row "/theme {주제}" "새 추적 테마 개설 + 기존 페이지에서 근거 수집"
    ux_table_row "/archive {경로}" "PARA 문서를 40-Archive 로 이동 + 위키 링크 재작성. 이동은 이 커맨드로만"
}

_llm_wiki_help_rows_clip() {
    ux_table_row "/pkm:obsidian-web-clip <url>" "URL 을 99-Inbox/Web/ 에 클립"
    ux_table_row "/pkm:obsidian-session-clip" "AI 세션을 99-Inbox/ai-session/ 에 클립"
    ux_bullet "두 클리퍼는 Inbox 까지만 넣는다. 이후는 /ingest 담당"
}

_llm_wiki_help_rows_flow() {
    ux_bullet "클립 (web-clip / session-clip) -> 99-Inbox -> /ingest -> 00-wiki · index.md · log.md"
}

_llm_wiki_help_rows_related() {
    ux_bullet "원본 SSOT: obsidian-para AGENTS.md §4, .claude/commands/*.md, docs/guide/commands.md"
    ux_bullet "커맨드 목록이 바뀌면 이 토픽도 수동 갱신 (자동 동기화 없음)"
    ux_bullet "그래프: ${UX_BOLD}graphify-help${UX_RESET}"
}

_llm_wiki_help_render_section() {
    ux_section "$1"
    "$2"
}

_llm_wiki_help_section_rows() {
    case "$1" in
        commands|command|cmd) _llm_wiki_help_rows_commands ;;
        clip|clips)           _llm_wiki_help_rows_clip ;;
        flow)                 _llm_wiki_help_rows_flow ;;
        related)              _llm_wiki_help_rows_related ;;
        *)
            ux_error "Unknown llm-wiki-help section: $1"
            ux_info "Try: llm-wiki-help --list"
            return 1
            ;;
    esac
}

_llm_wiki_help_full() {
    ux_header "LLM Wiki - vault 커맨드 + 클립 스킬"
    _llm_wiki_help_render_section "Vault Commands" _llm_wiki_help_rows_commands
    _llm_wiki_help_render_section "Inbox Clippers" _llm_wiki_help_rows_clip
    _llm_wiki_help_render_section "Flow" _llm_wiki_help_rows_flow
    _llm_wiki_help_render_section "Related" _llm_wiki_help_rows_related
}

llm_wiki_help() {
    case "${1:-}" in
        ""|-h|--help|help) _llm_wiki_help_summary ;;
        --list|list|section|sections) _llm_wiki_help_list_sections ;;
        --all|all)          _llm_wiki_help_full ;;
        *)                  _llm_wiki_help_section_rows "$1" ;;
    esac
}

alias llm-wiki-help='llm_wiki_help'
