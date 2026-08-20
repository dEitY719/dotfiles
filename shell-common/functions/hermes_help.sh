#!/bin/sh
# shell-common/functions/hermes_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_hermes_help_summary() {
    ux_info "Usage: hermes-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: 코딩 에이전트 | 커스텀 OpenAI-compatible 엔드포인트"
    ux_bullet_sub "install: 공식 install.sh | ./hermes/setup.sh 가 하는 5단계"
    ux_bullet_sub "config: llm_endpoint.local.sh | hermes config set | 심링크 SSOT"
    ux_bullet_sub "pitfalls: api_key 위치 | agent-browser workspace | TLS 인터셉션 CA"
    ux_bullet_sub "browser: agent-browser 설치 옵션"
    ux_bullet_sub "example | related"
    ux_bullet_sub "details: hermes-help <section>  (example: hermes-help pitfalls)"
}

_hermes_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "install"
    ux_bullet_sub "config"
    ux_bullet_sub "pitfalls"
    ux_bullet_sub "browser"
    ux_bullet_sub "example"
    ux_bullet_sub "related"
}

_hermes_help_rows_concept() {
    ux_bullet "Hermes Agent (NousResearch) — 터미널에서 도는 코딩 에이전트"
    ux_bullet "OpenAI-compatible 엔드포인트면 무엇이든 붙는다 — 자체 호스팅 모델, 사내 LLM 게이트웨이, Gemini 호환 엔드포인트"
    ux_bullet "이 저장소는 ${UX_BOLD}설치와 설정의 재현${UX_RESET}만 관리 — 에이전트 기능 자체는 upstream 소관"
    ux_bullet "config SSOT: ${UX_BOLD}hermes/config.yaml${UX_RESET} → ~/.hermes/config.yaml 심링크"
}

_hermes_help_rows_install() {
    ux_bullet "공식 설치: ${UX_BOLD}curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sh${UX_RESET}"
    ux_bullet "dotfiles 경유(권장): ${UX_BOLD}./setup.sh${UX_RESET} 또는 ${UX_BOLD}./hermes/setup.sh${UX_RESET} — 멱등, 이미 설치돼 있으면 스킵"
    ux_bullet "확인: ${UX_BOLD}hermes --version${UX_RESET} · ${UX_BOLD}hermes doctor${UX_RESET} (alias ${UX_BOLD}hermes-doctor${UX_RESET})"

    ux_section "./hermes/setup.sh 가 하는 일 (5단계)"
    ux_table_header "Part" "동작" "실패 정책"
    ux_table_row "1" "hermes/config.yaml → ~/.hermes/config.yaml 심링크" "hard-fail"
    ux_table_row "2" "공식 install.sh 실행 (설치돼 있으면 스킵)" "soft-fail"
    ux_table_row "3" "llm_endpoint.local.sh 읽어 base_url/api_key 주입" "soft-fail, 옵션"
    ux_table_row "4" "agent-browser npm 의존성 설치" "soft-fail, 옵션"
    ux_table_row "5" "root CA 를 Chromium NSS 저장소에 임포트" "soft-fail, 옵션"
    ux_bullet "Part 2-5 는 실패해도 경고만 — 부모 ./setup.sh 의 set -e 를 죽이지 않는다"

    ux_section "환경변수 (전부 선택)"
    ux_table_header "Variable" "효과"
    ux_table_row "HERMES_SKIP_INSTALL=1" "Part 2 (CLI 설치) 건너뛰기"
    ux_table_row "HERMES_SKIP_BROWSER=1" "Part 4 (agent-browser) 건너뛰기"
    ux_table_row "HERMES_AGENT_BROWSER_DIR" "agent-browser 의 package.json 이 있는 디렉터리 직접 지정"
    ux_table_row "HERMES_BROWSER_FULL_INSTALL=1" "데스크톱(Electron) workspace 까지 전체 설치"
    ux_table_row "HERMES_CORP_CA_CERT" "NSS 저장소에 임포트할 root CA 인증서 경로"
}

_hermes_help_rows_config() {
    ux_bullet "커스텀 엔드포인트 값은 git 추적 파일에 절대 넣지 않는다 — 로컬 파일 경유"
    ux_bullet "cp hermes/llm_endpoint.local.example hermes/llm_endpoint.local.sh"
    ux_bullet "HERMES_LLM_BASE_URL / HERMES_LLM_API_KEY 두 값을 채운 뒤 ./hermes/setup.sh 재실행"
    ux_bullet "llm_endpoint.local.sh 는 .gitignore 의 ${UX_BOLD}*.local.sh${UX_RESET} 글롭이 커버 — 셸이 자동 source 하지 않고 setup.sh 만 읽는다"

    ux_section "시크릿 흐름"
    ux_bullet "hermes/llm_endpoint.local.example  (추적, 값 없음)"
    ux_bullet_sub "cp ↓"
    ux_bullet "hermes/llm_endpoint.local.sh      (gitignored, 실제 base_url/api_key)"
    ux_bullet_sub "setup.sh Part 3 가 source ↓"
    ux_bullet "hermes config set model.api_key <value>   → ~/.hermes/config.yaml"

    ux_section "수동 설정"
    ux_bullet "hermes config set model.base_url <url>    # OpenAI-compatible 엔드포인트 (/v1 포함)"
    ux_bullet "hermes config set model.api_key <key>     # .env 아님 — 함정 1 참조"
    ux_bullet "hermes doctor                             # 키/엔드포인트 인식 여부 확인"

    ux_section "config.yaml 은 이 저장소 심링크 — 시크릿 주입 전 자동 detach"
    ux_bullet "런타임 config (\$HOME/.hermes/config.yaml) 은 기본적으로 hermes/config.yaml 심링크"
    ux_bullet "setup.sh 는 ${UX_BOLD}hermes config set${UX_RESET} 직전 그 심링크를 로컬 실파일로 바꿔치기한다 — api_key 는 저장소에 절대 안 들어감"
}

_hermes_help_rows_pitfalls() {
    ux_section "1. 커스텀 provider 의 api_key 는 .env 가 아니라 config"
    ux_bullet "증상: model.provider 를 custom 으로 두고 ~/.hermes/.env 에 OPENAI_API_KEY 를 넣었는데 401"
    ux_bullet "원인: hermes 가 자격증명 유출 방지로 OPENAI_API_KEY 를 ${UX_BOLD}openai.com / openai.azure.com${UX_RESET} 호스트에만 전달 (host-gate)"
    ux_bullet "해결: ${UX_BOLD}hermes config set model.api_key \"<key>\"${UX_RESET} 로 config 에 직접 주입"

    ux_section "2. agent-browser 는 workspace 전체를 설치할 필요가 없다"
    ux_bullet "증상: agent-browser 설치가 불필요하게 무겁고, 제한된 네트워크에서 잘 깨짐"
    ux_bullet "원인: 데스크톱 앱(Electron)이 같은 npm workspace 트리에 있어 같이 끌려온다"
    ux_bullet "해결: ${UX_BOLD}npm install --workspaces=false${UX_RESET} — agent-browser 는 루트 package.json 의존성이라 정상 동작"
    ux_bullet "이 저장소 기본값이 이 경량 설치 — 데스크톱이 필요하면 HERMES_BROWSER_FULL_INSTALL=1"

    ux_section "3. TLS 인터셉션 프록시 뒤에서 브라우저만 SSL 실패"
    ux_bullet "증상: curl / pip / uv 는 되는데 agent-browser 탐색만 전부 SSL 오류"
    ux_bullet "원인: Chromium 은 시스템 CA 번들이 아니라 자체 NSS 저장소를 본다 — ${UX_BOLD}~/.pki/nssdb${UX_RESET}"
    ux_bullet "snap Chromium 이면 경로가 다르다: ${UX_BOLD}~/snap/chromium/<rev>/.pki/nssdb${UX_RESET}"
    ux_bullet "해결: certutil (libnss3-tools) 로 회사 root CA 를 해당 NSS DB 에 임포트"
    ux_bullet "certutil -d sql:\$HOME/.pki/nssdb -A -t \"C,,\" -n corp-root-ca -i <cert.crt>"
    ux_bullet "setup.sh Part 5 가 대신 해준다 — HERMES_CORP_CA_CERT 지정 시 (미지정이면 sudo 프롬프트 없이 완전 스킵)"
    ux_bullet "HERMES_CORP_CA_CERT 미지정이면 shell-common/env/security.local.sh 의 \$CA_CERT 를 폴백으로 쓴다"
}

_hermes_help_rows_browser() {
    ux_bullet "agent-browser = hermes 의 브라우저 자동화 툴 (Chromium 구동)"
    ux_table_header "설치 방식" "명령" "언제"
    ux_table_row "루트 전용 (기본)" "npm install --workspaces=false" "CLI 만 쓰는 대다수"
    ux_table_row "전체" "npm install" "Electron 데스크톱 앱도 필요할 때"
    ux_bullet "setup.sh 는 package.json 위치를 ~/.hermes, ~/.local/share/hermes 순으로 탐색"
    ux_bullet "못 찾으면 건너뛰고 안내만 — ${UX_BOLD}HERMES_AGENT_BROWSER_DIR=<dir>${UX_RESET} 로 직접 지정"
    ux_bullet "TLS 인터셉션 환경이면 ${UX_BOLD}hermes-help pitfalls${UX_RESET} 3번 (NSS CA) 먼저 처리"
}

_hermes_help_rows_example() {
    ux_bullet "./hermes/setup.sh                                  # 설치 + 심링크 (멱등)"
    ux_bullet "cp hermes/llm_endpoint.local.example hermes/llm_endpoint.local.sh"
    ux_bullet "\$EDITOR hermes/llm_endpoint.local.sh               # base_url + api_key 채우기"
    ux_bullet "./hermes/setup.sh                                  # 재실행 — 엔드포인트 주입"
    ux_bullet "hermes doctor                                      # 설정 인식 확인"
    ux_bullet "HERMES_BROWSER_FULL_INSTALL=1 ./hermes/setup.sh    # 데스크톱 포함 설치"
    ux_bullet "HERMES_CORP_CA_CERT=/path/to/root-ca.crt ./hermes/setup.sh   # NSS CA 임포트"
}

_hermes_help_rows_related() {
    ux_bullet "Upstream: ${UX_BOLD}https://github.com/NousResearch/hermes-agent${UX_RESET}"
    ux_bullet "모듈 문서: ${UX_BOLD}hermes/AGENTS.md${UX_RESET}"
    ux_bullet "CA 인증서 일반: ${UX_BOLD}crt-help${UX_RESET} · 프록시: ${UX_BOLD}proxy-help${UX_RESET}"
    ux_bullet "다른 코딩 에이전트: ${UX_BOLD}claude-help${UX_RESET} · ${UX_BOLD}codex-help${UX_RESET} · ${UX_BOLD}opencode-help${UX_RESET}"
}

_hermes_help_render_section() {
    ux_section "$1"
    "$2"
}

_hermes_help_section_rows() {
    case "$1" in
        concept)              _hermes_help_rows_concept ;;
        install)              _hermes_help_rows_install ;;
        config|configure)     _hermes_help_rows_config ;;
        pitfall|pitfalls)     _hermes_help_rows_pitfalls ;;
        browser|agent-browser) _hermes_help_rows_browser ;;
        example|examples)     _hermes_help_rows_example ;;
        related)              _hermes_help_rows_related ;;
        *)
            ux_error "Unknown hermes-help section: $1"
            ux_info "Try: hermes-help --list"
            return 1
            ;;
    esac
}

_hermes_help_full() {
    ux_header "Hermes Agent - Coding Agent with Custom LLM Endpoints"
    _hermes_help_render_section "Core Concept" _hermes_help_rows_concept
    _hermes_help_render_section "Install" _hermes_help_rows_install
    _hermes_help_render_section "Configuration" _hermes_help_rows_config
    _hermes_help_render_section "Pitfalls" _hermes_help_rows_pitfalls
    _hermes_help_render_section "agent-browser" _hermes_help_rows_browser
    _hermes_help_render_section "Practical Example" _hermes_help_rows_example
    _hermes_help_render_section "Related Help" _hermes_help_rows_related
}

hermes_help() {
    case "${1:-}" in
        ""|-h|--help|help) _hermes_help_summary ;;
        --list|list|section|sections) _hermes_help_list_sections ;;
        --all|all)          _hermes_help_full ;;
        *)                  _hermes_help_section_rows "$1" ;;
    esac
}

alias hermes-help='hermes_help'
