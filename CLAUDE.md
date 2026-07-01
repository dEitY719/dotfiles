# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Setup
./setup.sh          # Symlinks + environment config
./install.sh        # Full install

# Lint (all)
mise run lint       # ruff + mypy + shellcheck + shfmt -d (read-only)
mise run fix        # ruff --fix + ruff format + shfmt -w (mutating)

# Lint (targeted)
mise run lint-sh    # Shell lint (shellcheck + shfmt diff)
mise run fix-sh     # Shell format (shfmt -w bash/)
mise run lint-py    # Python lint (ruff + mypy, read-only)
mise run fix-py     # Python format + fix (ruff, mutating)

# Tests
mise run test       # All tests (bats + pytest + golden rules)
./tests/test        # Same runner invoked directly
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
