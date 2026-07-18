# agy/ — AGENTS.md

Antigravity CLI(`agy`) 통합 모듈. `agy` 는 Google 이 배포한 에이전틱 CLI
바이너리(`~/.local/bin/agy`)로, `gemini`/`codex` 와 동일 층위의 도구다.
`agy --help` 에 `--model` / `--mode` / `--continue` / `plugin` / `models`
서브커맨드가 있다. 이 파일은 AI 에이전트·리뷰어용 SSOT 안내다.

## 책임 (SRP)

| 파일 | 책임 |
|---|---|
| `setup.sh` | `agy` 바이너리 존재/실행 가능 여부 확인. 없으면 공식 설치 커맨드 안내 후 정상 종료. 심볼릭 링크·PATH·셸 프로파일 **미변경** |
| `AGENTS.md` | 이 파일 — AI/리뷰어용 SSOT (≤100 줄) |

shell 자동 로드 레이어와 help 시스템은 이 폴더가 아니라
`shell-common/` 에 있다 (3-Step 패턴):
- `shell-common/tools/integrations/agy.sh` — alias + `agy_install()` / `agy_uninstall()`
- `shell-common/functions/agy_help.sh` — `agy_help()` + `alias agy-help`
- `shell-common/functions/my_help.sh` — 카테고리/설명 수동 등록

## setup.sh 가 심볼릭 링크를 만들지 않는 이유

`gemini/setup.sh` 는 `~/.gemini/GEMINI.md` 로 메모리 파일을 심볼릭 링크했다.
`agy` 는 그에 대응하는 프로젝트/글로벌 메모리 파일 관례(예: `ANTIGRAVITY.md`)가
현재 공식 문서·`agy --help` 에서 **확인되지 않는다**. 따라서 링크할 대상이 없어
`setup.sh` 는 바이너리 존재 확인만 수행한다. 향후 그런 관례가 도입되면
심볼릭 링크 로직을 추가하는 후속 이슈가 필요하다 (#1180 Open Question).

## PATH 재발 리스크 (중요)

`agy` 는 자체 인스톨러 `agy install` 을 갖고 있고, 이 인스톨러는
셸 프로파일에 PATH 를 append 하고 alias 를 purge 한다
(`--skip-path` / `--skip-aliases` 플래그로 각 동작을 우회 가능).
설치 스크립트(`curl … | bash`)는 실제로 `bash/main.bash`,
`bash/profile.bash`, `zsh/zshrc` 끝에 `export PATH="$HOME/.local/bin:$PATH"`
를 직접 삽입한 이력이 있다.

그러나 dotfiles 는 이미 `shell-common/env/path.sh` 에서 `~/.local/bin` 을
PATH SSOT 로 관리한다. 따라서:

- `agy/setup.sh` 는 절대 PATH·셸 프로파일을 건드리지 않는다 (SSOT 는 `path.sh`).
- `agy install` 을 직접 실행해야 한다면 `--skip-path --skip-aliases` 로
  셸 프로파일 오염을 막는 것이 권장된다.
- `bash/main.bash` / `bash/profile.bash` / `zsh/zshrc` 끝에 하드코딩된
  `export PATH=".../.local/bin:$PATH"` 라인이 다시 나타나면 그것은
  `agy install` 이 재삽입한 중복이므로 제거한다.

## Non-Goals

- `antigravity`(WSL 이 상속한 Windows VS Code 계열 GUI 실행기) 통합 — 별개 도구.
- `~/.gemini/skills` 합성 로직(`scripts/setup-skills-ssot.sh`) — `agy` 의 OAuth
  토큰이 `~/.gemini/antigravity-cli/` 에 저장되므로 Gemini 런타임 디렉토리는
  그대로 둔다.
- Gemini CLI(`gemini` 바이너리) 자체 제거 — 이 모듈은 shell 통합 레이어만 다룬다.

## References

- **[Root](../AGENTS.md)** · **[shell-common](../shell-common/AGENTS.md)** ("Adding a New Tool Integration (3-Step Pattern)")
- 근거: `agy --help`, `agy help install`, `agy models`, 설치 스크립트 `https://antigravity.google/cli/install.sh`
