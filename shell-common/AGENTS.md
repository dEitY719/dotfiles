# Module Context

- **Purpose**: POSIX-compatible shared shell utilities for bash + zsh
- **Scope**: env vars, aliases, functions, external tool integrations, project utilities
- **Structure**: `env/` · `aliases/` · `functions/` · `tools/{integrations,custom,ux_lib}/` · `projects/`
- **Dependencies**: 없음 (self-contained, `bash/main.bash`와 `zsh/main.zsh`가 source 함)
- **Loading core (#2134)**: 진입점은 `util/bootstrap.sh`(skip 가드·#589 정규화·counter·safe_source·ux_lib) 후 `util/loader.sh` 의 `dotfiles_load_all` 1회 호출 — env → aliases → functions → `tools/integrations` → projects. 모든 파일은 `safe_source` 경유(오류 노출 #1454/#1504 + `SOURCED_FILES_COUNT`, `DEBUG_DOTFILES=1` 시 `DEBUG: Loaded:` 1줄). shell-specific(`bash/env`, `zsh/app`)은 그 **뒤**.

# Operational Commands

- **Lint**: `mise run lint-sh` — shellcheck covers `bash/` + `shell-common/`, checked per-file under **default POSIX-sh dialect** (enforces the Golden Rules below). Files that genuinely branch on `_UX_IS_BASH`/`_UX_IS_ZSH` carry a `# shellcheck shell=bash` directive as their second line so the intentional branch doesn't false-positive — that opt-in is per-file, not directory-wide, so it never silences a real POSIX violation elsewhere. shfmt diff stays `bash/`-only (#1305).
- **Format**: `shfmt -w -i 4 shell-common/`
- **Reload / Syntax**: `source ~/.bashrc` · `source ~/.zshrc` / `bash -n <file>` · `zsh -n <file>`

# Golden Rules

## POSIX Compatibility

- **DO**: `>/dev/null 2>&1`, `[ ]`, `#!/bin/sh`
- **DON'T**: `&>/dev/null`, `[[ ]]` (shell-detected branch 외), bash array (detection 없이), `< <(cmd)`/`<<<` (→ `<<EOF` heredoc)
- **dash 파싱 예외 (#1889)**: 연관배열이 필수인 `functions/my_help.sh`·`util/help_registry.sh`(`declare -gA`/`typeset -gA`)와 `env/path.sh` `clean_paths` bash/zsh 분기(POSIX fallback 분기 별도)는 `sh -n` 실패를 감수한다.
- **Shebang exception**: `tools/custom/*.sh` 진입점(직접 실행, source 안 됨)은 `#!/bin/bash`.
  그 하위 디렉터리(`tools/custom/lib/*.sh` 등 source 전용)는 `#!/bin/sh` 유지.
  SSOT: `git/config/hook-config.sh` (`DOTFILES_HOOKS_SHEBANG_SHELL_COMMON_CUSTOM`), 강제: `git/hooks/checks/shebang_check.sh`

## Bash/Zsh Sourcing Rules

bash 와 zsh 양쪽 loader 에서 source 되는 파일에서:

- **`BASH_SOURCE` 금지 / `${SHELL_COMMON}` 경유**: 루트 [`AGENTS.md`](../AGENTS.md) Golden Rules (`${DOTFILES_ROOT}` 도 허용)
- **Acceptable (executable script만)**: `source "$(dirname "$0")/file.sh"`
- **Test**: `bash -i -c 'source main.bash && fn'` + `zsh -c 'source main.zsh && fn'`
- **Skill 이 standalone `.` 하는 파일** (예: `gh_pr_review.sh`): #1454/#1505 foreign-checkout
  guard 필수 — 스니펫: cheatsheet → "Foreign-Checkout Guard Snippet"
- **Interactive guard 위치/예외 (#1877)**: 출력 산출 파일은 첫 10줄 안(shebang·`# shellcheck` 직후). 예외(guard 없음, 헤더에 사유 주석) —
  비대화형으로 source 되는 순수 함수 라이브러리(skill/hook/setup/test 소비, 예: `gh_host.sh`), 직접 실행 스크립트(`tools/custom/*.sh`). `mount.sh` 는 순수 함수를 의도적으로 guard 위에 둔다.
- **ZSH compat guard (#1879)**: `local`/배열/`set -x` 를 쓰는 함수 본문 첫 줄에 `[ -n "${ZSH_VERSION-}" ] && emulate -L sh`. 예외(guard 금지) —
  `tools/custom/` (bash 로 실행됨, dead code), 파일을 source 하는 loader(`util/loader.sh`, `util/safe_source.sh`, `aliases/core.sh` `src`: setopt 원복·sh 모드 source), zsh 문법/옵션 의존(`env/path.sh` `clean_paths`, `functions/my_help.sh` setopt+`command_not_found_handler`), 프롬프트 헬퍼(`integrations/git.sh` `_short_pwd`/`_prompt_virtualenv`/`__git_ps1`), 첫 문장이 `$?` 캡처, 한 줄 함수 (#2195 wrapper 는 `local _exe` 없이 `"${SHELL_COMMON:-...}"/tools/custom/<name>.sh "$@"` 한 줄 — naming check 가 이 모양만 면제, #2255).

## Output Standards

- **ux_lib 필수 / raw `echo` 금지**: 루트 [`AGENTS.md`](../AGENTS.md) Golden Rules. 아래는 shell-common 고유 예외
- **Exception**: ux_lib 미로드 시 단순 에러는 `echo ... >&2`
- **변환 범위 (#1881)**: 사람이 읽는 장식/상태/usage 출력만 ux_lib 로 바꾼다. 제외 — 호출자가 파싱하는 출력(`$(...)` 캡처·eval·`key=value`·JSON·경로·`TARGET_SHA=` 류, skill/cron/hook 이 읽는 stdout·stderr 계약 → 필요 시 `echo` 대신 `printf '%s\n'`, 바이트 동일), git hook·check 모듈, 테스트·fixture, ux_lib 로드 전 단계(bootstrap·`install.sh`), bats 가 바이트 단위로 단언하는 출력(같은 PR 에서 테스트를 고치지 않는 한).
- **`-h|--help` (#1880)**: 인자를 받는 사용자 명령(함수·`tools/custom` 진입점·`./setup.sh`)만 대상 — 부작용 전에 `*_help` 로 위임 후 `return 0`.
  N/A — 인자 없는 명령, `_` private 함수만 있는 source 라이브러리, `env/`·`aliases/`·`util/`·`ux_lib`, git hook check 모듈, test fixture, `./setup.sh` 가 호출하는 하위 `*/setup.sh`. `"$@"` 를 help 가진 스크립트로 넘기는 래퍼는 충족, 외부 CLI 패스스루 래퍼(`codex`, `pycharm`)는 `-h` 를 원본 도구로 넘긴다.

## Naming

- 파일: `snake_case.sh` · 함수: `snake_case` 또는 `tool_command`
- alias: dash 가능 (`bat-help` → `bat_help`) · private: `_` 접두사

# Decision Tree (새 파일을 어디에 둘지)

1. 단순 alias? → `aliases/*.sh`
2. env 변수 export? → `env/*.sh` — 사내 식별값(호스트·URL·경로)은 tracked 금지: `env/<topic>.local.sh`(gitignored, `env/<topic>.sh` 가 `_dotfiles_source_local <topic>` 로 source — `util/local_env.sh`) + `.local.example`(가짜 placeholder), 미설정 시 경고/skip (#1944). 모드별 분기는 `= internal` 직접 비교 대신 정책 함수(`_dotfiles_setup_mode_is/_accounts/_gh_host/_ca/_proxy`) 사용 (#2158)
   - 개인 비밀값(API 키·쿠키)은 env 로 export 하지 않는다 → repo `.enc.env` + `secret-run` 실행 시점 주입 (`functions/secret_run.sh`, #2096). 새 키 추가 절차 SSOT: `sops-help secrets`. 사내 식별값·AWS 값은 `.enc.env` 금지
3. help 함수 (apt_help, git_help)? → `functions/*_help.sh`
4. 셸에서 호출하는 유틸 함수? → `functions/*.sh`
5. 3rd-party 도구 wrapper (npm, docker)? → `tools/integrations/*.sh`
6. 명시적 실행 스크립트? → `tools/custom/*.sh` (본체가 커지면 로직은 `tools/custom/lib/*.sh` 로 분리하고 진입점은 라우팅만)
7. bash/zsh-only? → `bash/*.bash` 또는 `zsh/*.zsh`
8. 프로젝트별? → `projects/<project>/*.sh`
9. 비대화형 소비자(skill/hook/cron/setup) 전용 순수 라이브러리? → `lib/*.sh` (자동 로드 안 됨, 소비자가 직접 source, #2154)

# Quick Reference Table

| Type | Location | Auto-sourced? | Example |
|------|----------|---|---------|
| Alias | `aliases/*.sh` | yes | `gs='git status'` |
| Environment | `env/*.sh` | yes | `export PATH=...` |
| Help function | `functions/*_help.sh` | yes | `apt_help()` — row 함수는 `docs/guide/commands/` 자동생성 소스 (#1262) |
| Utility function | `functions/*.sh` | yes | `devx()`, `gitlog()` — 사용자가 직접 치는 함수면 정의 파일 끝에 `_register_func <name> "설명"` 을 둬야 `my-help` 팔레트 `/func` 에 뜬다 (#1740, #2135) |
| 3rd-party wrapper | `tools/integrations/*.sh` | yes | `npm.sh`, `docker.sh` |
| Executable script | `tools/custom/*.sh` (+ `lib/*.sh`) | **no** | `install_npm.sh` · `aicron.sh` + `lib/aicron_*.sh` · `session_doctor_cron.sh` + `lib/session_doctor_*.sh` · cron 진입점 공용 부트스트랩·lock `lib/cron_common.sh` (#2144) — Python 로직은 `cron_py` 로 `tools/py/dotfiles_tools` 호출, 경계 규칙 `docs/.ssot/shell-vs-python.md` (#2157) · `my_help_preview.sh` (my-help 팔레트 preview) · `diagnose_internal.sh` (사내 PC read-only 진단, #2099) · `claude_accounts.sh` + `lib/claude_accounts_{auth,lifecycle,skills}.sh` (`claude_accounts` 함수는 `integrations/claude.sh` 에 남아 위임; auth lib 은 셸 상주, 나머지 `_claude_*` 는 lazy-load wrapper, `claude/setup.sh` 는 lib 직접 source, #2146) · 셸 상태를 안 바꾸는 디스패처 `gcp_scan.sh` (+ `lib/gcp_scan_{probe,conflict,lists,run}.sh`) · `gh_audit_builtin_workflows.sh` · `ghes_mirror.sh` · `ai_usage.sh` · `wsl_check.sh` — `~/.local/bin/<dash-name>` 노출은 `config/symlinks.conf`, `functions/` 의 동명 함수는 thin wrapper(`ghes_mirror` 는 clone 경로를 받아 `cd`) (#2155). #2195 가 나머지 37개(`gh_flow`·`gh_pr_{approve,reply,review}` 는 helper 라이브러리를 functions/ 에 두고 `_<name>_main` 호출, `devx`·`gcp`·`aicron`·`skill_loader` 등)를 같은 패턴으로 전환 — 목록은 `config/symlinks.conf` |
| Guard-free pure lib | `util/setup_mode_read.sh`, `util/local_env.sh`, `util/win_home.sh`, `util/help_registry.sh` | **no** (각 소비자가 직접 source — hook/스크립트 포함; `help_registry.sh` 는 loader 가 functions/ 앞에서 source) | `_dotfiles_setup_mode` + 정책 질의 `_dotfiles_setup_mode_{is,accounts,gh_host,ca,proxy}` (#2158), `_dotfiles_source_local`, `_win_home`, `_register_help` |
| Pure lib | `lib/*.sh`, `lib/setup/{common,link,runner,mode}.sh` | **no** (소비자가 `SHELL_COMMON` 경유 직접 source) | #2154: `gh_host`·`gh_pr_merge_train`·`devx_pr_review_all`·`dotfiles_root` 등 20개 — `functions/` stub 은 #2225 로 삭제, 모든 소비자가 `lib/<X>.sh` 를 직접 source. 대화형 소비자는 lib 를 직접/lazy source(`bootstrap`→`dotfiles_root`, `env/browser.sh`→`windows_chrome`, `codex.sh`→`skill_sources`). setup lib: `dotfiles_ensure_link`, `step_run` (#2137), `setup.d/*.sh` (#2140), `lib/agent_launch.sh` (#2156) |
| Shell-specific | `bash/*.bash` 또는 `zsh/*.zsh` | varies | bash prompt setup |
| Project-specific | `projects/<name>/*.sh` | yes | finrx utilities |

# Adding a New Tool Integration (2-Step Pattern)

새 외부 도구(예: bun, foo) 통합 시 2개 파일이면 된다 — `my_help.sh` 는 고치지 않는다 (#2135):

1. **`tools/integrations/<tool>.sh`** (자동 로드) — PATH export, alias, install/uninstall 함수 (`<tool>_install`/`<tool>_uninstall` + `<tool>-install` alias, 옛 이름은 alias 로 보존 — #2148).
   ux_lib guard 패턴 포함. 상세: [`docs/guide/playbooks/shell-common-cheatsheet.md`](../docs/guide/playbooks/shell-common-cheatsheet.md) → "Tool Integration UX-lib Guard"
2. **`functions/<tool>_help.sh`** (자동 로드) — `<tool>_help()` + `alias <tool>-help='<tool>_help'`. `ux_table_row` / `ux_section` / `ux_bullet` 사용.
   파일 끝에 `command -v _register_help >/dev/null 2>&1 || return 0` 가드 + `_register_help <tool>_help "[Category] 설명" <category>` 한 줄
   (`util/help_registry.sh` 가 functions/ 보다 먼저 로드됨). 카테고리: `development`, `devops`, `ai`, `cli`, `config`, `docs`, `system`, `meta`.
   여러 topic 을 한 파일에 묶은 카테고리 help 파일(`cc_help.sh`, `database_help.sh`)도 공식 허용 — topic 마다 한 줄.

참조 예시: `npm.sh` + `package_managers_help.sh` 끝의 `_register_help npm_help ...`

# References

- **[Bash](../bash/AGENTS.md)** · **[Zsh](../zsh/AGENTS.md)** · **[Root](../AGENTS.md)** · **[UX Guidelines](./tools/ux_lib/UX_GUIDELINES.md)** · **[Command UX SSOT](../docs/.ssot/command-guidelines.md)**
- **Vendoring**: 배너에 `# SSOT: dEitY719/dotfiles` 가 있는 파일(예: `functions/devx_pr_verify_live_*.sh`)은 gh-* skill repo 에 통째로 vendoring 된다 — 고친 뒤 `harness-skills` 의 `scripts/sync-shell-common-vendor.sh` 로 동기화. #2154 로 옮긴 lib 는 vendor 쪽도 `lib/vendor/shell-common/lib/<X>.sh` + 배너 `shell-common/lib/<X>.sh` 이고(#2225), lib 본문의 형제 source 경로도 `lib/` 다. `gwt` 는 `functions/git_worktree.sh` + `git_worktree_spawn.sh` + `gwt_help.sh` + `lib/agent_launch.sh` 4파일로 나뉘었다(#2156) — vendor 시 함께 동기화
- **[Cheatsheet](../docs/guide/playbooks/shell-common-cheatsheet.md)** — file-structure 템플릿, shell detection 분기, 흔한 실수,
  Agent View·multi-account 통합(#640), skill repo vendoring 절차
