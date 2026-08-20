# hermes

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/hermes_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic hermes --force`

## 호출

- Help 진입점: `hermes-help [section|--list|--all]`
- 통합 라우팅: `my-help hermes [section]`
- Alias: `hermes-help`

## 요약 (hermes-help)

- Usage: hermes-help [section|--list|--all]
- sections
    - concept: 코딩 에이전트 | 커스텀 OpenAI-compatible 엔드포인트
    - install: 공식 install.sh | ./hermes/setup.sh 가 하는 5단계
    - config: llm_endpoint.local.sh | hermes config set | 심링크 SSOT
    - pitfalls: api_key 위치 | agent-browser workspace | TLS 인터셉션 CA
    - browser: agent-browser 설치 옵션
    - example | related
    - details: hermes-help <section>  (example: hermes-help pitfalls)

## 섹션

### concept

- Hermes Agent (NousResearch) — 터미널에서 도는 코딩 에이전트
- OpenAI-compatible 엔드포인트면 무엇이든 붙는다 — 자체 호스팅 모델, 사내 LLM 게이트웨이, Gemini 호환 엔드포인트
- 이 저장소는 설치와 설정의 재현만 관리 — 에이전트 기능 자체는 upstream 소관
- config SSOT: hermes/config.yaml → ~/.hermes/config.yaml 심링크

### install

- 공식 설치: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sh
- dotfiles 경유(권장): ./setup.sh 또는 ./hermes/setup.sh — 멱등, 이미 설치돼 있으면 스킵
- 확인: hermes --version · hermes doctor (alias hermes-doctor)
**./hermes/setup.sh 가 하는 일 (5단계)**

- **Part** — 동작 — 실패 정책
- **1** — hermes/config.yaml → ~/.hermes/config.yaml 심링크 — hard-fail
- **2** — 공식 install.sh 실행 (설치돼 있으면 스킵) — soft-fail
- **3** — llm_endpoint.local.sh 읽어 base_url/api_key 주입 — soft-fail, 옵션
- **4** — agent-browser npm 의존성 설치 — soft-fail, 옵션
- **5** — root CA 를 Chromium NSS 저장소에 임포트 — soft-fail, 옵션
- Part 2-5 는 실패해도 경고만 — 부모 ./setup.sh 의 set -e 를 죽이지 않는다
**환경변수 (전부 선택)**

- **Variable** — 효과
- **HERMES_SKIP_INSTALL=1** — Part 2 (CLI 설치) 건너뛰기
- **HERMES_SKIP_BROWSER=1** — Part 4 (agent-browser) 건너뛰기
- **HERMES_AGENT_BROWSER_DIR** — agent-browser 의 package.json 이 있는 디렉터리 직접 지정
- **HERMES_BROWSER_FULL_INSTALL=1** — 데스크톱(Electron) workspace 까지 전체 설치
- **HERMES_CORP_CA_CERT** — NSS 저장소에 임포트할 root CA 인증서 경로

### config

- 커스텀 엔드포인트 값은 git 추적 파일에 절대 넣지 않는다 — 로컬 파일 경유
- cp hermes/llm_endpoint.local.example hermes/llm_endpoint.local.sh
- HERMES_LLM_BASE_URL / HERMES_LLM_API_KEY 두 값을 채운 뒤 ./hermes/setup.sh 재실행
- llm_endpoint.local.sh 는 .gitignore 의 *.local.sh 글롭이 커버 — 셸이 자동 source 하지 않고 setup.sh 만 읽는다
**시크릿 흐름**

- hermes/llm_endpoint.local.example  (추적, 값 없음)
    - cp ↓
- hermes/llm_endpoint.local.sh      (gitignored, 실제 base_url/api_key)
    - setup.sh Part 3 가 source ↓
- hermes config set model.api_key <value>   → ~/.hermes/config.yaml
**수동 설정**

- hermes config set model.base_url <url>    # OpenAI-compatible 엔드포인트 (/v1 포함)
- hermes config set model.api_key <key>     # .env 아님 — 함정 1 참조
- hermes doctor                             # 키/엔드포인트 인식 여부 확인
**config.yaml 은 이 저장소 심링크 — 시크릿 주입 전 자동 detach**

- 런타임 config ($HOME/.hermes/config.yaml) 은 기본적으로 hermes/config.yaml 심링크
- setup.sh 는 hermes config set 직전 그 심링크를 로컬 실파일로 바꿔치기한다 — api_key 는 저장소에 절대 안 들어감

### pitfalls

**1. 커스텀 provider 의 api_key 는 .env 가 아니라 config**

- 증상: model.provider 를 custom 으로 두고 ~/.hermes/.env 에 OPENAI_API_KEY 를 넣었는데 401
- 원인: hermes 가 자격증명 유출 방지로 OPENAI_API_KEY 를 openai.com / openai.azure.com 호스트에만 전달 (host-gate)
- 해결: hermes config set model.api_key "<key>" 로 config 에 직접 주입
**2. agent-browser 는 workspace 전체를 설치할 필요가 없다**

- 증상: agent-browser 설치가 불필요하게 무겁고, 제한된 네트워크에서 잘 깨짐
- 원인: 데스크톱 앱(Electron)이 같은 npm workspace 트리에 있어 같이 끌려온다
- 해결: npm install --workspaces=false — agent-browser 는 루트 package.json 의존성이라 정상 동작
- 이 저장소 기본값이 이 경량 설치 — 데스크톱이 필요하면 HERMES_BROWSER_FULL_INSTALL=1
**3. TLS 인터셉션 프록시 뒤에서 브라우저만 SSL 실패**

- 증상: curl / pip / uv 는 되는데 agent-browser 탐색만 전부 SSL 오류
- 원인: Chromium 은 시스템 CA 번들이 아니라 자체 NSS 저장소를 본다 — ~/.pki/nssdb
- snap Chromium 이면 경로가 다르다: ~/snap/chromium/<rev>/.pki/nssdb
- 해결: certutil (libnss3-tools) 로 회사 root CA 를 해당 NSS DB 에 임포트
- certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n corp-root-ca -i <cert.crt>
- setup.sh Part 5 가 대신 해준다 — HERMES_CORP_CA_CERT 지정 시 (미지정이면 sudo 프롬프트 없이 완전 스킵)
- HERMES_CORP_CA_CERT 미지정이면 shell-common/env/security.local.sh 의 $CA_CERT 를 폴백으로 쓴다

### browser

- agent-browser = hermes 의 브라우저 자동화 툴 (Chromium 구동)
- **설치 방식** — 명령 — 언제
- **루트 전용 (기본)** — npm install --workspaces=false — CLI 만 쓰는 대다수
- **전체** — npm install — Electron 데스크톱 앱도 필요할 때
- setup.sh 는 package.json 위치를 ~/.hermes, ~/.local/share/hermes 순으로 탐색
- 못 찾으면 건너뛰고 안내만 — HERMES_AGENT_BROWSER_DIR=<dir> 로 직접 지정
- TLS 인터셉션 환경이면 hermes-help pitfalls 3번 (NSS CA) 먼저 처리

### example

- ./hermes/setup.sh                                  # 설치 + 심링크 (멱등)
- cp hermes/llm_endpoint.local.example hermes/llm_endpoint.local.sh
- $EDITOR hermes/llm_endpoint.local.sh               # base_url + api_key 채우기
- ./hermes/setup.sh                                  # 재실행 — 엔드포인트 주입
- hermes doctor                                      # 설정 인식 확인
- HERMES_BROWSER_FULL_INSTALL=1 ./hermes/setup.sh    # 데스크톱 포함 설치
- HERMES_CORP_CA_CERT=/path/to/root-ca.crt ./hermes/setup.sh   # NSS CA 임포트

### related

- Upstream: https://github.com/NousResearch/hermes-agent
- 모듈 문서: hermes/AGENTS.md
- CA 인증서 일반: crt-help · 프록시: proxy-help
- 다른 코딩 에이전트: claude-help · codex-help · opencode-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/hermes.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/hermes_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
