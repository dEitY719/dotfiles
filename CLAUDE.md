# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Setup
./setup.sh          # Symlinks + environment config
./install.sh        # Full install

# Lint / test tasks
mise tasks          # SSOT for lint / fix / test / lint-docs — read mise.toml, not this file

# Tests (non-obvious invocations only)
./tests/test        # Runner invoked directly (mise run test wraps it in `uv run`)
./tests/test -v     # Verbose
pytest tests/integration/test_help_topics.py -v  # Single pytest file
./tests/bats/lib/bats-core/bin/bats tests/bats/functions  # Bats only

# UX demo
shell-common/tools/custom/demo_ux.sh
```

## Architecture

This repo is a modular dotfiles system. Shell config is split into three layers:

- **`bash/`** — Bash-specific entry point (`main.bash`), env, utils
- **`zsh/`** — Zsh-specific entry point (`main.zsh`), env, apps
- **`shell-common/`** — POSIX-compatible shared code, sourced by both loaders

### shell-common/ Directory Placement

See `shell-common/AGENTS.md` → "Decision Tree" and "Quick Reference Table" for the full placement guide.

Key rule: `tools/custom/` is **never auto-sourced** — scripts there must be called explicitly.

### Adding a New Tool Integration

See `shell-common/AGENTS.md` → "Adding a New Tool Integration (3-Step Pattern)" for the required 3-file sequence (`tools/integrations/`, `functions/*_help.sh`, `functions/my_help.sh` registration).

### UX Library

All output must use `ux_lib` functions (`ux_header`, `ux_success`, `ux_error`, `ux_info`). Never use raw `echo`, `printf`, or `tput` in app scripts. Source: `shell-common/tools/ux_lib/ux_lib.sh`. Guidelines: `shell-common/tools/ux_lib/UX_GUIDELINES.md`.

### Git Hooks

`git/` manages a 2-tier hook system. Config SSOT is `git/config/hook-config.sh`. Debug with `GIT_HOOKS_DEBUG=1 git commit -m "msg"`. Test with `bash git/tests/test_hooks.sh`.

`git/hooks/pre-push` runs a protected-branch check plus an upstream leak guard (SSOT: `git/config/pre-push-rules.sh`). The leak guard is inert until you export `UPSTREAM_REMOTES_ERE` and `LEAK_PATTERNS_ERE`; see `git/AGENTS.md` for the activation snippet and escape hatches.

### Claude Code Integration

`claude/statusline-command.sh` and `claude/docs/` are symlinked into each account's Claude config dir; `claude/settings.json` is copied as a real file (not symlinked) so `/model` writes don't dirty the tracked SSOT. Full symlink-vs-copy scheme and rationale: `claude/AGENTS.md` → "Configuration Files".

**Skills no longer live in this repo (#1680)** — the 73 skills moved to 15 standalone marketplace repos, registered in `claude/plugin/{marketplaces,plugins}.json`. The only skill source is now the workspace: repos cloned side by side under `${WORKSPACE_ROOT:-~/para/project/skills}/<repo>/skills/<skill>/SKILL.md`. `shell-common/functions/skill_sources.sh` (`_skill_workspace_root` / `_skill_workspace_dirs`) is the enumeration SSOT; `scripts/setup-skills-ssot.sh` entry-level symlink-composes them into Codex / OpenCode / Gemini / agy (its own `~/.gemini/config/skills` root — it does **not** inherit Gemini's, #1731) / Hermes, and `_claude_compose_workspace_skills` (via `claude/setup.sh`) does the same for each Claude Code account.

**Personal overrides (model, env vars)** — `claude/settings.local.json` is gitignored (#924). Create `settings.local.json` in your active Claude config directory for machine-specific settings:

- Single-account: `~/.claude/settings.local.json`
- Multi-account: `~/.claude-personal/settings.local.json` (or whichever `$CLAUDE_CONFIG_DIR` is active)

```json
{ "model": "sonnet" }
```

Claude Code merges this with `settings.json` natively (local wins). Running `/model` writes into the per-account **real-file** `settings.json` copy — since #940 this no longer dirties the repo. Re-running `claude/setup.sh` refreshes the copy from the SSOT and auto-migrates any `/model`-written `model` key into `settings.local.json`. See `claude/AGENTS.md` → "Configuration Files" for the full merge/migration behavior.

## Critical Rules

**POSIX compatibility & cross-shell sourcing** — see `shell-common/AGENTS.md` → "Golden Rules" for full detail.
- Use `>/dev/null 2>&1` (not `&>/dev/null`) and `[ ]` (not `[[ ]]`) unless inside a shell-detection branch.
- Forbidden: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, breaks in zsh). Use `source "${SHELL_COMMON}/path/to/file.sh"`.

**Interactive guard** — every file that produces output must start with:
```bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
```

**No direct writes to `~/.bashrc`** — use symlinks via `setup.sh`.

**After adding a module**: update the `AGENTS.md` in the module root.

**On lint/test failure**: fix the root cause — do not use `--no-verify` or skip hooks.

## Codebase Map (선탐색 인덱스)

아키텍처/오리엔테이션/"X 어디 있나"/"Y가 뭘 호출하나" 류 질문은 소스 전체를 grep 하기 전에 `.understand-anything/knowledge-graph.json` 을 **먼저 구조적으로 쿼리**한다 — 정밀 슬라이스는 `jq` 로 노드 `summary`/`tags`/`edges` 만 뽑고, 노드명 빠른 위치 확인은 grep 으로 (파일 통독 금지, 약 1.1MB). 파일·함수 지도는 여기서 얻고, 정확한 코드 확인은 소스로 fallback 한다.

**주의**: 그래프는 마지막 `/understand` 실행 시점 스냅샷 (`.understand-anything/meta.json` 의 `gitCommitHash`). 그 이후 변경된 파일은 드리프트 가능 — 소스가 최종 진실이다. 크게 어긋나면 `/understand` 재실행.

## Standards & References

- 운영 교훈 지식 베이스: `docs/guide/learnings/` (반복 실수 예방용 패턴 모음)
- PC 환경 SSOT (5개 PC, `~/.dotfiles-setup-mode` 모드): `docs/.ssot/pc-environment.md` — 환경에 따라 동작이 달라지는 작업(계정 전환, git host, 프록시)을 다룰 때는 먼저 `cat ~/.dotfiles-setup-mode` 로 현재 모드를 확인한다.
- Command/help interface: `docs/.ssot/command-guidelines.md`
- GitHub Project board: `docs/.ssot/github-project-board.md`
- GitHub Discussions 운영: `docs/.ssot/discussions-policy.md`
- Git strategy: Semantic commits (`Type: Summary`)
- Naming: `snake_case` for functions and filenames; dash-form for user-facing aliases
- No emojis anywhere (token efficiency) — **단 하나의 예외**: `ai-metrics` footer (`<details>` 래퍼 및 `<!-- ai-metrics -->` 블록) 내부의 `📊 👤 🤖` 글리프. 이는 GitHub Issue/PR 카드 footer 의 의도된 시각 디자인이며 #317 F-2 요구사항 + PR #320 으로 SSOT 확정됨 (#367 의 `<details><summary>🤖 AI Metrics</summary>` 래퍼 포함). 다른 어떤 위치에도 이모지 사용 금지.
- For AGENTS.md files, aim to keep them under 100 lines each

## 변경 기록 (changelog) — 중단 (2026-09-02)

- fragment 작성 요구는 **중단됐다** — 토큰 소모가 커서 잠정 정지. 완료 후 fragment 파일을 만들지 않는다.
- `mise run lint-docs` 에서도 `scripts/lint_changelog_fragments.sh` 호출을 뺐다 — 게이트 비활성.
- 과거 규칙(파일명 `<YYYY-MM-DD>-<issue>.md`, `- 변경: **요약**` 포맷)과 스크립트/`tests/bats/lint/changelog_fragments.bats` 는 재개를 위해 그대로 남겨뒀다. 재개 시 이 섹션과 `mise.toml` 의 `lint-docs` 를 되돌린다.
- **my-share 영향**: 일일/주간 보고 허브(`my-share`)의 수집기(`scripts/report_range.py`)는 `changelog.d/` 가 비어 있어도 에러 없이 빈 결과를 반환한다 — 이 기간 동안 dotfiles 항목은 보고서에서 조용히 빠진다(수집기 오작동이 아니라 fragment 부재의 정상 결과). 재개 전까지는 dotfiles 변경 사항을 daily/weekly 보고서에서 볼 수 없다는 뜻이다.
