#!/bin/sh
# shell-common/functions/graphify_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_graphify_help_summary() {
    ux_info "Usage: graphify-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: 2-pass 추출 | Leiden clustering | confidence 태그"
    ux_bullet_sub "install: pip install graphifyy | graphify install | claude install"
    ux_bullet_sub "uninstall: graphify claude uninstall | graphify uninstall [--purge]"
    ux_bullet_sub "usage: /graphify . | update | query | path | explain | add | graphify-vault"
    ux_bullet_sub "output: graphify-out/ (graph.html, GRAPH_REPORT.md, graph.json)"
    ux_bullet_sub "accounts: 멀티 계정에서 스킬이 안 보일 때"
    ux_bullet_sub "related"
    ux_bullet_sub "details: graphify-help <section>  (example: graphify-help install)"
}

_graphify_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "install"
    ux_bullet_sub "uninstall"
    ux_bullet_sub "usage"
    ux_bullet_sub "output"
    ux_bullet_sub "accounts"
    ux_bullet_sub "related"
}

_graphify_help_rows_concept() {
    ux_bullet "코드/문서/이미지를 지속형 knowledge graph 로 바꿔 AI 가 저장소를 grep 대신 질의하게 한다 — 토큰 절감"
    ux_bullet "pass 1: Tree-sitter AST 로 코드 구조를 로컬 추출 (LLM 없음, 비용 0)"
    ux_bullet "pass 2: 문서/이미지 등은 LLM 으로 semantic 추출"
    ux_bullet "NetworkX 그래프 + Leiden community detection 으로 모듈/god node 도출"
    ux_bullet "edge confidence 태그: EXTRACTED (확정) / INFERRED (추론) / AMBIGUOUS (불확실)"
}

_graphify_help_rows_install() {
    ux_bullet "요구사항: Python 3.10+"
    ux_bullet "pip install graphifyy          # 패키지명 graphifyy, CLI 이름은 graphify"
    ux_bullet "graphify install [--platform claude|codex|opencode|claw|gemini|...]   # SKILL.md 복사"
    ux_bullet "graphify claude install        # CLAUDE.md 섹션 + PreToolUse hook (always-on, 스킬은 설치 안 함)"
    ux_bullet "graphify hook install          # git commit/checkout 시 그래프 자동 재빌드"
    ux_bullet "dotfiles: ${UX_BOLD}./graphify/setup.sh${UX_RESET}  (스킬 설치 + 계정별 링크, 멱등, pip 는 수동)"
}

_graphify_help_rows_uninstall() {
    ux_bullet "graphify claude uninstall      # CLAUDE.md 섹션 + hook 제거"
    ux_bullet "graphify uninstall             # 감지된 모든 플랫폼에서 스킬 제거"
    ux_bullet "graphify uninstall --purge     # graphify-out/ 디렉터리까지 삭제"
    ux_bullet "dotfiles: ${UX_BOLD}./graphify/uninstall.sh${UX_RESET}  (계정 링크만 제거, 원본 제거는 위 명령 안내)"
}

_graphify_help_rows_usage() {
    ux_section "Claude Code 스킬"
    ux_bullet "/graphify .                    # 현재 디렉터리 그래프 생성"
    ux_bullet "/graphify <path> --update      # 변경분만 증분 갱신"
    ux_bullet "/graphify <path> --watch       # 파일 변경 감시 후 자동 갱신"
    ux_bullet "/graphify <path> --wiki        # 커뮤니티별 wiki 생성"
    ux_bullet "/graphify <path> --cluster-only  # 클러스터링만 재실행"
    ux_bullet "/graphify <path> --no-viz      # graph.html 생략 (대형 그래프)"
    ux_section "CLI"
    ux_bullet "graphify update .              # AST 만 재추출 — LLM 비용 없음 (코드 수정 후)"
    ux_bullet "graphify query \"<q>\"           # 질문으로 BFS 부분 그래프 (--dfs, --budget N)"
    ux_bullet "graphify path \"A\" \"B\"          # 두 노드 간 최단 경로"
    ux_bullet "graphify explain \"X\"           # 노드와 이웃 설명"
    ux_bullet "graphify add <url>             # URL 을 ./raw 에 저장 후 그래프 갱신"
    ux_section "Obsidian 노드 단위 탐색"
    ux_bullet "${UX_BOLD}graphify-vault${UX_RESET}                   # repo 루트에서 실행 -> ~/vaults/<repo>-graph 생성 (덮어쓰기)"
    ux_bullet "GRAPHIFY_VAULT_ROOT=<dir>      # vault 상위 경로 변경 (기본 ~/vaults)"
    ux_bullet "수동: graphify export obsidian --dir ~/vaults/<repo>-graph"
}

_graphify_help_rows_output() {
    ux_table_row "graphify-out/graph.html" "브라우저용 인터랙티브 시각화"
    ux_table_row "graphify-out/GRAPH_REPORT.md" "god node / community / 구조 요약"
    ux_table_row "graphify-out/graph.json" "query/path/explain 이 읽는 그래프"
    ux_table_row "graphify-out/cache/" "추출 캐시 (증분 갱신용)"
}

_graphify_help_rows_accounts() {
    ux_bullet "증상: /graphify 스킬이 ~/.claude-<account> 계정에서 검색되지 않음"
    ux_bullet "원인 1: graphify claude install 은 CLAUDE.md + hook 만 등록 — 스킬은 graphify install 이 설치"
    ux_bullet "원인 2: graphify install 은 CLAUDE_CONFIG_DIR 를 따른다 — 터미널엔 미설정이라 ~/.claude/skills/graphify 에 설치됨"
    ux_bullet "해결: 원본 ~/.claude/skills/graphify 하나를 각 계정 <cdir>/skills/graphify 로 심볼릭 링크"
    ux_bullet "자동화: ${UX_BOLD}./graphify/setup.sh${UX_RESET} 후 Claude Code 에서 /reload-skills"
    ux_bullet "사내 모드(단일 계정 ~/.claude)는 링크가 필요 없다"
}

_graphify_help_rows_related() {
    ux_bullet "소개: ${UX_BOLD}https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652${UX_RESET}"
    ux_bullet "전체 명령: ${UX_BOLD}graphify --help${UX_RESET}"
    ux_bullet "Claude Code: ${UX_BOLD}claude-help${UX_RESET}"
}

_graphify_help_render_section() {
    ux_section "$1"
    "$2"
}

_graphify_help_section_rows() {
    case "$1" in
        concept)            _graphify_help_rows_concept ;;
        install|setup)      _graphify_help_rows_install ;;
        uninstall|remove)   _graphify_help_rows_uninstall ;;
        usage|use|commands) _graphify_help_rows_usage ;;
        output|out)         _graphify_help_rows_output ;;
        accounts|account)   _graphify_help_rows_accounts ;;
        related)            _graphify_help_rows_related ;;
        *)
            ux_error "Unknown graphify-help section: $1"
            ux_info "Try: graphify-help --list"
            return 1
            ;;
    esac
}

_graphify_help_full() {
    ux_header "graphify - AI Knowledge Graph"
    _graphify_help_render_section "Core Concept" _graphify_help_rows_concept
    _graphify_help_render_section "Install" _graphify_help_rows_install
    _graphify_help_render_section "Uninstall" _graphify_help_rows_uninstall
    _graphify_help_render_section "Usage" _graphify_help_rows_usage
    _graphify_help_render_section "Output" _graphify_help_rows_output
    _graphify_help_render_section "Multi-Account" _graphify_help_rows_accounts
    _graphify_help_render_section "Related Help" _graphify_help_rows_related
}

graphify_help() {
    case "${1:-}" in
        ""|-h|--help|help) _graphify_help_summary ;;
        --list|list|section|sections) _graphify_help_list_sections ;;
        --all|all)          _graphify_help_full ;;
        *)                  _graphify_help_section_rows "$1" ;;
    esac
}

alias graphify-help='graphify_help'
