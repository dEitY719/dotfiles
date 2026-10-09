# PC Environment (SSOT)

내 개발 환경: **5개 PC 환경의 단일 진실 공급원(SSOT)**.

> 비밀(토큰·CA·내부 호스트·회사명)은 이 문서에 적지 않는다.
> 이 repo 가 public 이면 이 문서는 토폴로지만 담아야 한다.

## 1. 공통 전제

- 모든 PC: **Windows + WSL**. Windows 사용자명과 WSL 사용자명은 **PC마다 다름**
  → 경로를 하드코딩하지 말고 런타임에 탐지한다 (부트스트랩 스크립트 참고).
- 모드 스위치: `~/.dotfiles-setup-mode` 파일에 `internal` | `external` | `public` 중 하나 (`public` = home/개인 PC; `shell-common/setup.sh` 가 쓰는 실제 값).

## 2. PC 인벤토리 (5대)

| 모드 | 대수 | 사양 / LLM | 네트워크 | 비고 |
|------|------|-----------|----------|------|
| `internal` | 2 | 1대만 사내 local LLM 연동 가능 | 사내망 | GHES 사용 |
| `external` | 1 | 최고 사양, **Ollama 로컬 서빙** | 회사에서 외부 접속 가능 | (이 세션 PC) · Obsidian vault WSL 단일 클론 통합 (2026-09-06, Windows-native 앱 폐기) |
| `public` | 2 | 노트북, 저사양 → **local LLM 불가** | 집 | 1대: Obsidian vault WSL 단일 클론 + Linux AppImage + Local REST API 이관 (2026-10-02, Windows-native 앱은 검증 후 제거 예정) |


## 3. 접근/동기화 규칙 (모드별)

| 모드 | GitHub (common) | GHES (company) | AI 자동 태깅 |
|------|-----------------|----------------|--------------|
| `internal` | **pull only** (upstream, push 절대 금지) | **read/write** | local LLM 있는 1대만 |
| `external` | read/write | 접속 불가 | Ollama 로컬 |
| `public` | read/write | 접속 불가 | 없음 (재태깅은 다른 PC에서) |

## 4. 모드가 바꾸는 것 (코드 SSOT)

| 항목 | 위치 | 비고 |
|------|------|------|
| Claude Code 인증 | `gateway-cli setup` (조직 LLM Gateway) | `internal` → 2026-08-18~ `gateway-cli` 소유; 상세: `docs/guide/internal-pc.md` |
| Claude 계정 활성화 | `shell-common/env/claude.sh` | `internal` → work 계정만; 그 외 → personal/work/work1 |
| 사내 식별값 | `shell-common/env/internal.local.sh` (gitignored) | `internal` PC 는 `internal.local.example` 을 복사해 실제 값 입력 (예: `DOTFILES_GHES_HOST`) — #1944. `proxy`/`security` 템플릿도 가짜 placeholder 이며 `shell-common/setup.sh` 는 기존 `*.local.sh` 를 덮어쓰지 않는다(모드 재선택 시 `*.backup.local.sh` 로 옮겼다 복원) — #1969 |
| Git host 라우팅 | `shell-common/functions/gh_host.sh` | `internal` → GHES, 그 외 → github.com |
| 프록시 자동 정리 | `shell-common/util/setup_mode.sh` | WSL2 프록시 상속 방지. `_dotfiles_setup_mode` (`shell-common/util/setup_mode_read.sh`) 로 읽으므로 문자열·레거시 숫자값 모두 지원 (#1810) |
| Bedrock 비용 위젯 | `claude/statusline-command.sh` | `internal` 에서만 표시. `_dotfiles_setup_mode` 가 레거시 `2` 를 `internal` 로 정규화한다 (#1810) |
| 패키지 레지스트리 설정 | `shell-common/setup.sh` `_internal_src` | `internal` → npm/bun/uv/pip/cargo/nuget symlink · rpm 복사의 소스로 gitignored `<file>.internal.local` 이 있으면 우선, 없으면 tracked `*.internal` — #1968 (아래 §5) |

## 5. internal PC: `*.internal` 실값 이관 순서 (#1968)

tracked `*.internal` 은 internal PC 에서 `~/.npmrc` 등이 직접 가리키는 **live symlink 소스**다. 이 파일들은 나중에 placeholder 로 교체될 예정이므로, 그 교체가 pull 되기 **전에** 각 internal PC 에서 한 번 (internal 모드 `./setup.sh` 가 2단계를 `--apply` 로 자동 호출하므로 1→3 만 해도 수렴한다):

1. `git pull` (이 메커니즘이 포함된 main — placeholder 교체 커밋 이전)
2. `scripts/internal-config-migrate.sh` (dry-run 으로 대상 확인) → `scripts/internal-config-migrate.sh --apply` — 각 `*.internal` 을 gitignored `*.internal.local` 로 복사(기존 파일은 절대 덮어쓰지 않음, 내용 출력 없음, `cmp` 검증, 멱등)
3. `./setup.sh` — symlink 가 `*.internal.local` 로 재지정된다

검증: `readlink ~/.npmrc ~/.config/pip/pip.conf ~/.config/uv/uv.toml ~/.cargo/config.toml` 가 모두 `*.internal.local` 로 끝나는지, `check-npm` 등 진단 명령이 Internal 로 표시되는지 확인. 이미 placeholder 로 바뀐 tracked 파일은 helper 가 건너뛰므로(경고) 그 경우 실값을 `*.internal.local` 에 직접 넣는다.
