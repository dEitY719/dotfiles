# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Setup
./setup.sh          # Symlinks + environment config
./install.sh        # Full install

# Lint (all)
tox                 # ruff, mypy, shellcheck, shfmt

# Lint (targeted)
tox -e shellcheck   # Shell script validation
tox -e shfmt        # Shell script formatting (bash/ only)
tox -e ruff         # Python format + fix
tox -e mypy         # Python type check

# Tests
./tests/test        # All tests (bats + pytest + golden rules)
./tests/test -v     # Verbose
pytest tests/integration/test_help_topics.py -v  # Single pytest file
./tests/bats/lib/bats-core/bin/bats tests/bats/functions  # Bats only

# UX demo
shell-common/tools/custom/demo_ux.sh
```

Markdown linting (`tox -e mdlint`) is **disabled** — do not run it.

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

### Claude Code Integration

`claude/settings.json` and `claude/statusline-command.sh` are symlinked into `~/.claude/`. The `claude/skills/` directory is bind-mounted to `~/.claude/skills/` (not symlinked).

## Critical Rules

**POSIX compatibility in shell-common/**
- Use `>/dev/null 2>&1` (not `&>/dev/null`)
- Use `[ ]` (not `[[ ]]`) unless inside a shell-detection branch
- Use `#!/bin/sh` shebang

**Sourcing across shells** — forbidden pattern:
```bash
# WRONG — bash-only, breaks in zsh
source "${BASH_SOURCE[0]%/*}/file.sh"

# CORRECT
source "${SHELL_COMMON}/path/to/file.sh"
```

**Interactive guard** — every file that produces output must start with:
```bash
case $- in *i*) ;; *) return 0 ;; esac
```

**No direct writes to `~/.bashrc`** — use symlinks via `setup.sh`.

**After adding a module**: update the `AGENTS.md` in the module root.

**On lint/test failure**: fix the root cause — do not use `--no-verify` or skip hooks.

**Agent isolation is blocked in this repo.** `Agent({ isolation: "worktree" })` triggers a `git-crypt` smudge filter failure. Use sequential dispatch (no `isolation` key) or the `ai-worktree-spawn` skill. See `claude/AGENTS.md` and `docs/learnings/git-crypt-worktree-bootstrap.md`.

## Standards & References

- Command/help interface: `docs/standards/command-guidelines.md`
- GitHub Project board: `docs/standards/github-project-board.md`
- Git strategy: Semantic commits (`Type: Summary`)
- Naming: `snake_case` for functions and filenames; dash-form for user-facing aliases
- No emojis anywhere (token efficiency) — **단 하나의 예외**: `<!-- ai-metrics -->` ~ `<!-- /ai-metrics -->` 블록 내부의 `📊 👤 🤖` 글리프. 이는 GitHub Issue/PR 카드 footer 의 의도된 시각 디자인이며 #317 F-2 요구사항 + PR #320 으로 SSOT 확정됨. 다른 어떤 위치에도 이모지 사용 금지.
- For AGENTS.md files, aim to keep them under 100 lines each
