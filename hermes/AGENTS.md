# Module Context

- **Purpose**: [Hermes Agent](https://github.com/NousResearch/hermes-agent) 설치·설정을 이 저장소로 재현
- **Scope**: 설치 + config SSOT + 커스텀 OpenAI-compatible 엔드포인트 연동. 에이전트 기능 자체는 upstream 소관
- **Structure**: `setup.sh` · `config.yaml` (SSOT) · `llm_endpoint.local.example` (템플릿)
- **Dependencies**: `shell-common/tools/ux_lib` · (옵션) `npm`, `certutil`(libnss3-tools)
- **대칭 모듈**: `herdr/` — 동일한 hard-fail/soft-fail 구조

# Operational Commands

- **Setup**: `./hermes/setup.sh` (루트 `./setup.sh` 가 호출, 멱등)
- **Help**: `hermes-help` / `hermes-help pitfalls` / `hermes-help --all`
- **Verify**: `hermes --version` · `hermes doctor` (alias `hermes-doctor`)
- **Syntax**: `bash -n hermes/setup.sh`

# setup.sh 5단계

| Part | 동작 | 실패 정책 |
|---|---|---|
| 1 | `hermes/config.yaml` → `~/.hermes/config.yaml` 심링크 | **hard-fail** (dangling link = 조용한 기본값 복귀) |
| 2 | 공식 `install.sh` 실행 (`command -v hermes` 로 스킵) | soft-fail |
| 3 | `llm_endpoint.local.sh` 읽어 `model.base_url`/`model.api_key` 주입 | soft-fail, 옵션 |
| 4 | `agent-browser` npm 의존성 설치 | soft-fail, 옵션 |
| 5 | root CA 를 Chromium NSS 저장소에 임포트 | soft-fail, 옵션 |

Part 2-5 는 네트워크/호스트 상태에 의존하므로 실패해도 경고만 남기고 계속한다 —
부모 `./setup.sh` 는 `set -e` 로 돌기 때문에 이 스크립트는 항상 `exit 0` 으로 끝난다.

**환경변수 (전부 선택)**: `HERMES_SKIP_INSTALL` · `HERMES_SKIP_BROWSER` ·
`HERMES_AGENT_BROWSER_DIR` · `HERMES_BROWSER_FULL_INSTALL` · `HERMES_CORP_CA_CERT`

# 시크릿 흐름

```
hermes/llm_endpoint.local.example   (git 추적, 값 없음, 안내 주석만)
        │  cp
        ▼
hermes/llm_endpoint.local.sh        (.gitignore 의 *.local.sh 글롭이 커버)
        │  setup.sh Part 3 이 실행 시점에 한 번 source
        ▼
hermes config set model.api_key "<value>"   → ~/.hermes/config.yaml
```

`llm_endpoint.local.sh` 는 셸이 자동 source 하지 않는다 (`shell-common/env/*.local.sh`
와 다른 점) — API 키가 매 셸 환경변수로 떠 있지 않게 하기 위함이다.

Part 1 은 `~/.hermes/config.yaml` 을 이 저장소로 심링크하지만, Part 3 는 `hermes
config set` 을 실행하기 직전 그 심링크를 로컬 실파일로 교체한다
(`_hermes_materialize_config`) — 시크릿은 로컬 사본에만 쓰이고 이 저장소의
`hermes/config.yaml` 에는 도달하지 않는다. 다음 실행의 Part 1 이 그 사본을
백업하고 저장소 기본값으로 다시 심링크한다.

# 3가지 함정 (`hermes-help pitfalls` 가 SSOT)

1. **`model.provider: custom` 의 API 키는 `.env` 가 아니라 config** — hermes 는
   `OPENAI_API_KEY` 를 `openai.com` / `openai.azure.com` 호스트로만 전달하는
   host-gate 를 걸어둔다. 커스텀 `base_url` 이면 키가 조용히 누락되어 401 이 난다.
   해결: `hermes config set model.api_key "<key>"`.
2. **`agent-browser` 는 workspace 전체를 설치할 필요가 없다** — 데스크톱 앱(Electron)이
   같은 npm workspace 트리에 있어 같이 끌려온다. `agent-browser` 는 루트
   `package.json` 의존성이라 `npm install --workspaces=false` 로 충분하다 (기본값).
3. **TLS 인터셉션 프록시 뒤에서는 브라우저만 SSL 실패** — Chromium 은 시스템 CA
   번들이 아니라 자체 NSS 저장소(`~/.pki/nssdb`, snap 이면
   `~/snap/chromium/<rev>/.pki/nssdb`)를 본다. `certutil` 로 root CA 를 명시적으로
   임포트해야 한다.

# 검증되지 않은 부분

- **Part 4 의 경로 탐색**: `agent-browser` 의 `package.json` 위치는 upstream 설치
  레이아웃에 달렸다. `~/.hermes` → `~/.local/share/hermes` 순으로만 탐색하고,
  못 찾으면 스킵 + 안내한다. 실제 위치는 설치 후 확인해 `HERMES_AGENT_BROWSER_DIR`
  로 지정하거나 이 탐색 목록을 갱신할 것.
- **`config.yaml` 스키마**: 검증되지 않은 키를 지어내지 않기 위해 주석만 두었다.
  설정을 추가할 때는 설치된 버전의 `hermes config` 로 키를 먼저 확인할 것.

# References

- **[Root](../AGENTS.md)** · **[shell-common](../shell-common/AGENTS.md)** · **[herdr](../herdr/)**
- **Upstream**: https://github.com/NousResearch/hermes-agent
- **Symlink SSOT**: `shell-common/config/symlinks.conf`
