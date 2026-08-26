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

`claude/statusline-command.sh`, `claude/skills/`, and `claude/docs/` are symlinked into each account's Claude config dir; `claude/settings.json` is copied as a real file (not symlinked) so `/model` writes don't dirty the tracked SSOT. Full symlink-vs-copy scheme and rationale: `claude/AGENTS.md` → "Configuration Files".

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

## 변경 기록 (changelog)

- 사용자 가시·운영·스키마·배포·비자명 동작 변경을 완료하면 `docs/public/changelog.d/` 에 **fragment 파일 1개**를 추가한다(항목이 불필요하면 그 이유를 명시). 단일 `changelog.md` 는 #1471 에서 제거됐다 — 모든 PR 이 같은 줄에 삽입해 충돌이 상시화되고 중복 날짜 헤더까지 뚫렸기 때문이다.
- 파일명은 `<YYYY-MM-DD>-<issue>.md` (예: `docs/public/changelog.d/2026-08-26-1471.md`). 날짜를 파일명이 들고 있으므로 **파일 안에는 `##` 날짜 헤더를 쓰지 않는다**.
- 내용은 한 줄 = 한 항목, `- 변경: **요약**` 형식. 한 이슈가 항목을 여러 개 남기면 같은 파일에 여러 줄로 적는다. 줄바꿈·하위 불릿은 금지(수집기가 비어 있지 않은 모든 줄을 항목으로 싣는다).
- 같은 날짜 안 정렬은 파일명 오름차순이다.
- 포맷 강제: `mise run lint-docs` (`scripts/lint_changelog_fragments.sh`). 회귀 테스트는 `tests/bats/lint/changelog_fragments.bats`.
- 이 changelog는 일일/주간 보고 허브(my-share)가 수집해 보고서를 생성한다.
