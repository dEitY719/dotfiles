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
| `external` | 1 | 최고 사양, **Ollama 로컬 서빙** | 회사에서 외부 접속 가능 | (이 세션 PC) |
| `public` | 2 | 노트북, 저사양 → **local LLM 불가** | 집 | |


## 3. 접근/동기화 규칙 (모드별)

| 모드 | GitHub (common) | GHES (company) | AI 자동 태깅 |
|------|-----------------|----------------|--------------|
| `internal` | **pull only** (upstream, push 절대 금지) | **read/write** | local LLM 있는 1대만 |
| `external` | read/write | 접속 불가 | Ollama 로컬 |
| `public` | read/write | 접속 불가 | 없음 (재태깅은 다른 PC에서) |

## 4. 모드가 바꾸는 것 (코드 SSOT)

| 항목 | 위치 | 비고 |
|------|------|------|
| Claude 계정 활성화 | `shell-common/env/claude.sh` | `internal` → work 계정만; 그 외 → personal/work/work1 |
| Git host 라우팅 | `shell-common/functions/gh_host.sh` | `internal` → GHES, 그 외 → github.com |
| 프록시 자동 정리 | `shell-common/util/setup_mode.sh` | WSL2 프록시 상속 방지 (레거시 숫자값만 매칭, 문자열 값 미지원 — issue #1051) |
| Bedrock 비용 위젯 | `claude/statusline-command.sh` | `internal` 에서만 표시 (레거시 숫자값 `2`는 미지원 — 별도 확인 필요) |
