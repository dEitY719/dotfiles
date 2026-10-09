# Module Context

- **Purpose**: POSIX-compatible shared shell utilities for bash + zsh
- **Scope**: env vars, aliases, functions, external tool integrations, project utilities
- **Structure**: `env/` · `aliases/` · `functions/` · `tools/{integrations,custom,ux_lib}/` · `projects/`
- **Dependencies**: 없음 (self-contained, `bash/main.bash`와 `zsh/main.zsh`가 source 함)

# Operational Commands

- **Lint**: `mise run lint-sh` — shellcheck covers `bash/` + `shell-common/`, checked per-file under **default POSIX-sh dialect** (enforces the Golden Rules below). Files that genuinely branch on `_UX_IS_BASH`/`_UX_IS_ZSH` carry a `# shellcheck shell=bash` directive as their second line so the intentional branch doesn't false-positive — that opt-in is per-file, not directory-wide, so it never silences a real POSIX violation elsewhere. shfmt diff stays `bash/`-only (#1305).
- **Format**: `shfmt -w -i 4 shell-common/`
- **Reload**: `source ~/.bashrc` (bash) 또는 `source ~/.zshrc` (zsh)
- **Syntax**: `bash -n <file>` / `zsh -n <file>`

# Golden Rules

## POSIX Compatibility

- **DO**: `>/dev/null 2>&1`, `[ ]`, `#!/bin/sh`
- **DON'T**: `&>/dev/null`, `[[ ]]` (shell-detected branch 외), bash array (detection 없이), `< <(cmd)`/`<<<` (→ `<<EOF` heredoc)
- **dash 파싱 예외 (#1889)**: 연관배열이 필수인 `functions/my_help.sh`(`declare -gA`/`typeset -gA`)와 `env/path.sh` `clean_paths` bash/zsh 분기(POSIX fallback 분기 별도)는 `sh -n` 실패를 감수한다.
- **Shebang exception**: `tools/custom/*.sh` 진입점(직접 실행, source 안 됨)은 `#!/bin/bash`.
  그 하위 디렉터리(`tools/custom/lib/*.sh` 등 source 전용)는 `#!/bin/sh` 유지.
  SSOT: `git/config/hook-config.sh` (`DOTFILES_HOOKS_SHEBANG_SHELL_COMMON_CUSTOM`), 강제: `git/hooks/checks/shebang_check.sh`

## Bash/Zsh Sourcing Rules

bash 와 zsh 양쪽 loader 에서 source 되는 파일에서:

- **Forbidden**: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, zsh 깨짐)
- **Required**: `source "${SHELL_COMMON}/path/to/file.sh"` 또는 `${DOTFILES_ROOT}` 사용
- **Acceptable (executable script만)**: `source "$(dirname "$0")/file.sh"`
- **Test**: `bash -i -c 'source main.bash && fn'` + `zsh -c 'source main.zsh && fn'`
- **Skill 이 standalone `.` 하는 파일** (예: `gh_pr_review.sh`): #1454/#1505 foreign-checkout
  guard 필수 — 스니펫: cheatsheet → "Foreign-Checkout Guard Snippet"
- **Interactive guard 위치/예외 (#1877)**: 출력 산출 파일은 첫 10줄 안(shebang·`# shellcheck` 직후). 예외(guard 없음, 헤더에 사유 주석) —
  비대화형으로 source 되는 순수 함수 라이브러리(skill/hook/setup/test 소비, 예: `gh_host.sh`), 직접 실행 스크립트(`tools/custom/*.sh`). `mount.sh` 는 순수 함수를 의도적으로 guard 위에 둔다.
- **ZSH compat guard (#1879)**: `local`/배열/`set -x` 를 쓰는 함수 본문 첫 줄에 `[ -n "${ZSH_VERSION-}" ] && emulate -L sh`. 예외(guard 금지) —
  `tools/custom/` (bash 로 실행됨, dead code), 파일을 source 하는 loader(`util/loader.sh`, `util/safe_source.sh`, `aliases/core.sh` `src`: setopt 원복·sh 모드 source), zsh 문법/옵션 의존(`env/path.sh` `clean_paths`, `util/path_resolver.sh` `${(%)…}`, `functions/my_help.sh` setopt+`command_not_found_handler`, `zz_help_standard_adapter.sh` assoc 배열), 프롬프트 헬퍼(`integrations/git.sh` `_short_pwd`/`_prompt_virtualenv`/`__git_ps1`), 첫 문장이 `$?` 캡처, 한 줄 함수.

## Output Standards

- **DO**: `ux_lib` 함수 (`ux_header`, `ux_success`, `ux_error`)
- **DON'T**: raw `echo`/`printf`
- **Exception**: ux_lib 미로드 시 단순 에러는 `echo ... >&2`
- **변환 범위 (#1881)**: 사람이 읽는 장식/상태/usage 출력만 ux_lib 로 바꾼다. 제외 — 호출자가 파싱하는 출력(`$(...)` 캡처·eval·`key=value`·JSON·경로·`TARGET_SHA=` 류, skill/cron/hook 이 읽는 stdout·stderr 계약 → 필요 시 `echo` 대신 `printf '%s\n'`, 바이트 동일), git hook·check 모듈, 테스트·fixture, ux_lib 로드 전 단계(bootstrap·`install.sh`), bats 가 바이트 단위로 단언하는 출력(같은 PR 에서 테스트를 고치지 않는 한).
- **`-h|--help` (#1880)**: 인자를 받는 사용자 명령(함수·`tools/custom` 진입점·`./setup.sh`)만 대상 — 부작용 전에 `*_help` 로 위임 후 `return 0`.
  N/A — 인자 없는 명령, `_` private 함수만 있는 source 라이브러리, `env/`·`aliases/`·`util/`·`ux_lib`, git hook check 모듈, test fixture, `./setup.sh` 가 호출하는 하위 `*/setup.sh`. `"$@"` 를 help 가진 스크립트로 넘기는 래퍼는 충족, 외부 CLI 패스스루 래퍼(`codex`, `pycharm`)는 `-h` 를 원본 도구로 넘긴다.

## Naming

- 파일: `snake_case.sh` · 함수: `snake_case` 또는 `tool_command`
- alias: dash 가능 (`bat-help` → `bat_help`) · private: `_` 접두사

# Decision Tree (새 파일을 어디에 둘지)

1. 단순 alias? → `aliases/*.sh`
2. env 변수 export? → `env/*.sh` — 사내 식별값(호스트·URL·경로)은 tracked 금지: `env/<topic>.local.sh`(gitignored, `env/<topic>.sh` 가 source) + `.local.example`(가짜 placeholder), 미설정 시 경고/skip (#1944)
3. help 함수 (apt_help, git_help)? → `functions/*_help.sh`
4. 셸에서 호출하는 유틸 함수? → `functions/*.sh`
5. 3rd-party 도구 wrapper (npm, docker)? → `tools/integrations/*.sh`
6. 명시적 실행 스크립트? → `tools/custom/*.sh` (본체가 커지면 로직은 `tools/custom/lib/*.sh` 로 분리하고 진입점은 라우팅만)
7. bash/zsh-only? → `bash/*.bash` 또는 `zsh/*.zsh`
8. 프로젝트별? → `projects/<project>/*.sh`

# Quick Reference Table

| Type | Location | Auto-sourced? | Example |
|------|----------|---|---------|
| Alias | `aliases/*.sh` | yes | `gs='git status'` |
| Environment | `env/*.sh` | yes | `export PATH=...` |
| Help function | `functions/*_help.sh` | yes | `apt_help()` — row 함수는 `docs/guide/commands/` 자동생성 소스 (#1262) |
| Utility function | `functions/*.sh` | yes | `devx()`, `gitlog()` — 사용자가 직접 치는 함수면 `my_help.sh` 의 `_my_help_func_registry` 에도 등록해야 `my-help` 팔레트 `/func` 에 뜬다 (#1740) |
| 3rd-party wrapper | `tools/integrations/*.sh` | yes | `npm.sh`, `docker.sh` |
| Executable script | `tools/custom/*.sh` (+ `lib/*.sh`) | **no** | `install_npm.sh` · `aicron.sh` + `lib/aicron_*.sh` · `session_doctor_cron.sh` + `lib/session_doctor_*.sh` · `my_help_preview.sh` (my-help 팔레트 preview) |
| Guard-free pure lib | `util/setup_mode_read.sh`, `util/win_home.sh` | **no** (각 소비자가 직접 source — hook/스크립트 포함) | `_dotfiles_setup_mode`, `_dotfiles_setup_mode_proxy`, `_win_home` |
| Shell-specific | `bash/*.bash` 또는 `zsh/*.zsh` | varies | bash prompt setup |
| Project-specific | `projects/<name>/*.sh` | yes | finrx utilities |

# Adding a New Tool Integration (3-Step Pattern)

새 외부 도구(예: bun, foo) 통합 시 항상 3개 파일이 필요:

1. **`tools/integrations/<tool>.sh`** (자동 로드) — PATH export, alias, install/uninstall 함수.
   ux_lib guard 패턴 포함. 상세: [`docs/guide/playbooks/shell-common-cheatsheet.md`](../docs/guide/playbooks/shell-common-cheatsheet.md) → "Tool Integration UX-lib Guard"
2. **`functions/<tool>_help.sh`** (자동 로드) — `<tool>_help()` + `alias <tool>-help='<tool>_help'`.
   `ux_table_row` / `ux_section` / `ux_bullet` 사용
3. **`functions/my_help.sh` 수동 등록** (자동 안 됨!) —
   `HELP_CATEGORY_MEMBERS[<category>]`에 토픽 추가 + `HELP_DESCRIPTIONS[<tool>_help]` 항목 추가.
   카테고리: `development`, `devops`, `ai`, `cli`, `config`, `docs`, `system`, `meta`

참조 예시: `npm.sh` + `npm_help.sh` + `my_help.sh` 의 npm 항목

# Agent View 와 Multi-account 통합 (#640)

- **Supervisor 격리**: `claude` background supervisor 는 `CLAUDE_CONFIG_DIR` 단위.
  multi-account 환경에서는 계정마다 별도 view — `claude-yolo --user work agents`.
- **main/master 가드 제거 (#647)**: `claude-yolo` 는 main 위에서도 그대로 실행된다.
  격리가 필요하면 `gwt spawn --launch --ai claude --wt-name <slug>` 가 SSOT —
  자동 `scratch/*` 분기, `CLAUDE_YOLO_STAY` env, read-only 화이트리스트의
  누적 복잡도가 같이 사라졌다.
- **Worktree dispatch (#650 grammar)**: `gwt spawn --launch --bg --wt-name
  <slug> [--prompt <text...>]` (claude 전용) 로 worktree 생성 → cd →
  `claude_yolo --bg "<prompt>"` 일괄 실행. `--user` 와 조합 가능.
  `--prompt` 없이 `--bg` 단독 호출 시 `--bg ''` 로 dispatch — Agent View
  진입 후 `claude agents` 에서 입력. `--bg` 없이 `--prompt` 만 주면
  `claude_yolo "<prompt>"` 로 TUI 첫 메시지로 전달.

# Cheatsheet & Pitfalls

자주 헷갈리는 패턴/실수 (file-structure 템플릿, shell detection 분기, 6대 mistake)
는 분리되어 있다 — [`docs/guide/playbooks/shell-common-cheatsheet.md`](../docs/guide/playbooks/shell-common-cheatsheet.md) 참조.

# References

- **[Bash Module](../bash/AGENTS.md)** · **[Zsh Module](../zsh/AGENTS.md)** · **[Root](../AGENTS.md)**
- **[UX Guidelines](./tools/ux_lib/UX_GUIDELINES.md)** — 출력 스타일 표준
- **[Cheatsheet](../docs/guide/playbooks/shell-common-cheatsheet.md)** — 패턴 / 실수 예시
- **[Command UX SSOT](../docs/.ssot/command-guidelines.md)** — 명령/help 인터페이스 정책

## Vendoring to skill repos

`functions/devx_pr_verify_live_*.sh` (and other files whose banner reads `# SSOT: dEitY719/dotfiles ...`) are vendored whole into the gh-* skill repos under `lib/vendor/shell-common/`. The sync tool is NOT in this repo: `scripts/sync-shell-common-vendor.sh` lives in `harness-skills` (`${WORKSPACE_ROOT:-~/para/project/skills}/harness-skills/`). Run `scripts/sync-shell-common-vendor.sh [--check] --ssot <this checkout> <repo>...` there. It only refreshes files a consumer already vendors; adding a new one (e.g. `devx_pr_verify_live_serving_identity.sh` in gh-verify-skills) is that repo's own copy-in.
