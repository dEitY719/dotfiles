# Module Context

- **Purpose**: POSIX-compatible shared shell utilities for bash + zsh
- **Scope**: env vars, aliases, functions, external tool integrations, project utilities
- **Structure**: `env/` · `aliases/` · `functions/` · `tools/{integrations,custom,ux_lib}/` · `projects/`
- **Dependencies**: 없음 (self-contained, `bash/main.bash`와 `zsh/main.zsh`가 source 함)

# Operational Commands

- **Lint**: `tox -e shellcheck -- shell-common/**/*.sh`
- **Format**: `shfmt -w -i 4 shell-common/`
- **Reload**: `source ~/.bashrc` (bash) 또는 `source ~/.zshrc` (zsh)
- **Syntax**: `bash -n <file>` / `zsh -n <file>`

# Golden Rules

## POSIX Compatibility

- **DO**: `>/dev/null 2>&1`, `[ ]`, `#!/bin/sh`
- **DON'T**: `&>/dev/null`, `[[ ]]` (shell-detected branch 외), bash array (detection 없이)

## Bash/Zsh Sourcing Rules

bash 와 zsh 양쪽 loader 에서 source 되는 파일에서:

- **Forbidden**: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, zsh 깨짐)
- **Required**: `source "${SHELL_COMMON}/path/to/file.sh"` 또는 `${DOTFILES_ROOT}` 사용
- **Acceptable (executable script만)**: `source "$(dirname "$0")/file.sh"`
- **Test**: `bash -i -c 'source main.bash && fn'` + `zsh -c 'source main.zsh && fn'`

## Output Standards

- **DO**: `ux_lib` 함수 (`ux_header`, `ux_success`, `ux_error`)
- **DON'T**: raw `echo`/`printf`
- **Exception**: ux_lib 미로드 시 단순 에러는 `echo ... >&2`

## Naming

- 파일: `snake_case.sh` · 함수: `snake_case` 또는 `tool_command`
- alias: dash 가능 (`bat-help` → `bat_help`) · private: `_` 접두사

# Decision Tree (새 파일을 어디에 둘지)

1. 단순 alias? → `aliases/*.sh`
2. env 변수 export? → `env/*.sh`
3. help 함수 (apt_help, git_help)? → `functions/*_help.sh`
4. 셸에서 호출하는 유틸 함수? → `functions/*.sh`
5. 3rd-party 도구 wrapper (npm, docker)? → `tools/integrations/*.sh`
6. 명시적 실행 스크립트? → `tools/custom/*.sh`
7. bash/zsh-only? → `bash/*.bash` 또는 `zsh/*.zsh`
8. 프로젝트별? → `projects/<project>/*.sh`

# Quick Reference Table

| Type | Location | Auto-sourced? | Example |
|------|----------|---|---------|
| Alias | `aliases/*.sh` | yes | `gs='git status'` |
| Environment | `env/*.sh` | yes | `export PATH=...` |
| Help function | `functions/*_help.sh` | yes | `apt_help()` |
| Utility function | `functions/*.sh` | yes | `devx()`, `gitlog()` |
| 3rd-party wrapper | `tools/integrations/*.sh` | yes | `npm.sh`, `docker.sh` |
| Executable script | `tools/custom/*.sh` | **no** | `install_npm.sh`, `setup.sh` |
| Shell-specific | `bash/*.bash` 또는 `zsh/*.zsh` | varies | bash prompt setup |
| Project-specific | `projects/<name>/*.sh` | yes | finrx utilities |

# Adding a New Tool Integration (3-Step Pattern)

새 외부 도구(예: bun, foo) 통합 시 항상 3개 파일이 필요:

1. **`tools/integrations/<tool>.sh`** (자동 로드) — PATH export, alias, install/uninstall 함수.
   ux_lib guard 패턴 포함. 상세: [`docs/playbooks/shell-common-cheatsheet.md`](../docs/playbooks/shell-common-cheatsheet.md) → "Tool Integration UX-lib Guard"
2. **`functions/<tool>_help.sh`** (자동 로드) — `<tool>_help()` + `alias <tool>-help='<tool>_help'`.
   `ux_table_row` / `ux_section` / `ux_bullet` 사용
3. **`functions/my_help.sh` 수동 등록** (자동 안 됨!) —
   `HELP_CATEGORY_MEMBERS[<category>]`에 토픽 추가 + `HELP_DESCRIPTIONS[<tool>_help]` 항목 추가.
   카테고리: `development`, `devops`, `ai`, `cli`, `config`, `docs`, `system`, `meta`

참조 예시: `npm.sh` + `npm_help.sh` + `my_help.sh` 의 npm 항목

# Agent View 와 Multi-account 통합 (#640)

- **Supervisor 격리**: `claude` background supervisor 는 `CLAUDE_CONFIG_DIR` 단위.
  multi-account 환경에서는 계정마다 별도 view — `claude-yolo --user work agents`.
- **Read-only bypass**: `claude-yolo {agents|attach|logs|stop|kill|respawn|rm}` 은
  main 위에서도 `scratch/*` 미생성. opt-in 아님, 자동 적용.
- **Worktree dispatch**: `gwt spawn --launch --bg [task]` (claude 전용) 로
  worktree 생성 → cd → `claude_yolo --bg "<task>"` 일괄 실행. `--user` 와 조합 가능.

# Cheatsheet & Pitfalls

자주 헷갈리는 패턴/실수 (file-structure 템플릿, shell detection 분기, 6대 mistake)
는 분리되어 있다 — [`docs/playbooks/shell-common-cheatsheet.md`](../docs/playbooks/shell-common-cheatsheet.md) 참조.

# References

- **[Bash Module](../bash/AGENTS.md)** · **[Zsh Module](../zsh/AGENTS.md)** · **[Root](../AGENTS.md)**
- **[UX Guidelines](./tools/ux_lib/UX_GUIDELINES.md)** — 출력 스타일 표준
- **[Cheatsheet](../docs/playbooks/shell-common-cheatsheet.md)** — 패턴 / 실수 예시
- **[Command UX SSOT](../docs/.ssot/command-guidelines.md)** — 명령/help 인터페이스 정책
