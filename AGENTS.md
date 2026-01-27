# Project Context

- **Objective**: Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
- **Stack**: Bash 5.x+, Python 3.10+, Tox, Ruff, Mypy.
- **Structure**: Modular Bash (`bash/`), Zsh (`zsh/`), shared shell (`shell-common/`), Tests (`tests/`), Docs (`docs/`), Git hooks (`git/`), Claude Code (`claude/`).

# Operational Commands

- **Setup**: `./setup.sh` (Symlinks), `./install.sh` (Full install).
- **Linting (All)**: `tox` (Runs ruff, mypy, shellcheck, shfmt).
- **Linting (Python)**: `tox -e ruff` (fixes), `tox -e mypy`.
- **Linting (Bash)**: `tox -e shellcheck`, `tox -e shfmt` (formats).
- **Note**: Markdown linting (mdlint) is DISABLED. Do NOT perform markdown lint checks automatically.
- **Testing**: `./tests/test`, `pytest tests/`, manual validation via `shell-common/tools/custom/demo_ux.sh`.

# Golden Rules

## Immutable Constraints

- **500-Line Limit**: Every AGENTS.md file must be under 500 lines.
- **No Emojis**: Strictly prohibited to save tokens.
- **Interactive Guards**: Bash files must guard execution: `[[ $- == *i* ]]`.
- **Loading Order**: Respect `bash/main.bash` priority (Env -> UX -> Alias -> App).
- **No Direct Writes**: Do not write to `~/.bashrc` directly; use symlinks via `setup.sh`.

## Do's & Don'ts

- **DO**: Use snake_case for all Bash functions and filenames.
- **DO**: Use `ux_lib` functions (`ux_header`, `ux_success`) for ALL output.
- **DO**: Run `tox` before committing.
- **DO**: Use environment variables (e.g., `$SHELL_COMMON`) or absolute paths when sourcing files across shell contexts.
- **DO**: Test scripts in both bash and zsh for cross-shell compatibility.
- **DO**: Place shell functions in `shell-common/functions/` (auto-sourced by main.bash/main.zsh).
- **DO**: Place executable utility scripts in `shell-common/tools/custom/` (run explicitly, not sourced).
- **DO**: Add direct-exec guard to ALL executable scripts in `shell-common/tools/custom/` (see Guard Pattern below).
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency).
- **DON'T**: Hardcode paths; use `$HOME` or relative paths.
- **DON'T**: Commit secrets or sensitive data.
- **DON'T**: Use bash-specific variables (e.g., `${BASH_SOURCE[0]}`) without fallback; this breaks zsh compatibility.
- **DON'T**: Place functions in `shell-common/tools/custom/` (won't be auto-sourced; breaks initialization).

## shell-common Directory Structure Guide

**CRITICAL**: Correct directory placement prevents "function not found" and "command not found" errors.

### shell-common/functions/ - AUTO-SOURCED FUNCTIONS
Loaded automatically by `main.bash` and `main.zsh` during shell initialization.

**Use this for:** Commands that users call from the terminal, wrapper functions, helper functions.
**Pattern**: `shell-common/functions/COMMAND_help.sh` or `shell-common/functions/COMMAND.sh`.

### shell-common/tools/custom/ - EXECUTABLE UTILITY SCRIPTS
Run explicitly as scripts, NOT auto-sourced. Used for development tools, CLI utilities, analysis scripts.

**Use this for:** Command-line utilities meant to be executed directly, standalone scripts, tools called by Makefile/tox.
**Pattern**: `shell-common/tools/custom/TOOL_NAME.sh` (has shebang, executable, never sourced).

### shell-common/tools/external/ - THIRD-PARTY TOOL WRAPPERS
Auto-sourced. Thin wrappers around system tools or external packages.

**Use this for:** Wrapper functions for external CLIs (npm, pip, etc.), system tool integrations.

### Decision Tree
1. Will users call this as a command? -> `shell-common/functions/`
2. Is this a standalone utility script? -> `shell-common/tools/custom/`
3. Is this a wrapper for an external tool? -> `shell-common/tools/external/`

## Direct-Exec Guard Pattern (CRITICAL)

**RULE**: All files in `shell-common/tools/custom/` MUST have a direct-exec guard at END of script.

### Why This Matters
- Prevents code execution when file is sourced (e.g., during initialization)
- Avoids console pollution, side effects, and shell conflicts (p10k instant prompt, etc)
- Required for POSIX shell compatibility (bash, zsh, sh)
- **ENFORCED**: Pre-commit hook will reject files without proper guards

### Required Pattern

Place at **END of script**, after ALL function definitions:

```bash
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
```

### What Each Condition Does

| Condition | When True | Scenario |
|-----------|-----------|----------|
| `"${BASH_SOURCE[0]}" = "$0"` | Script executed directly in bash | User runs: `./script.sh` or `bash script.sh` |
| `-z "$BASH_SOURCE"` | BASH_SOURCE is empty (POSIX sh) | User runs: `sh script.sh` |
| Both false | File being sourced | User runs: `source script.sh` or `.  script.sh` |

### Example: Complete Executable Script

```bash
#!/usr/bin/env bash
# tool-name.sh - Description

# Try to load ux_lib
if ! type ux_header >/dev/null 2>&1; then
    if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# Function definitions
main() {
    ux_header "Tool Name"
    ux_success "Operation completed"
}

# CRITICAL: Direct-exec guard (end of file)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
```

### Testing Your Guard

```bash
# Test 1: Direct execution (should run)
./script.sh
# Expected: Output from main()

# Test 2: Sourcing (should NOT run main, only define functions)
bash -c "source script.sh; type main"
# Expected: "main is a function" (no other output)

# Test 3: Zsh compatibility
zsh -c "source script.sh; type main"
# Expected: "main is a function" (no other output)
```

## Bash/Zsh Compatibility Rules

- **Forbidden**: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, fails in zsh).
- **Required**: Use environment variables: `source "${SHELL_COMMON}/tools/custom/file.sh"`.
- **Test command**: Verify in both: `bash -i -c 'function_name'` and `zsh -c 'source main.zsh && function_name'`.

# SOLID & Design Principles

- **SRP**: Each Bash file manages ONE domain (e.g., `docker.bash` only for Docker).
- **OCP**: Extend behavior via new files in `bash/env/`, `bash/util/`, or `shell-common/`; don't clutter `bash/main.bash` or `zsh/main.zsh`.
- **LSP**: Wrapper functions must preserve expected behavior; avoid breaking existing flags and output contracts.
- **ISP**: Prefer small focused functions over monolithic “do-everything” commands.
- **DRY**: Replicate logic? Move to `bash/util/` or `shell-common/tools/ux_lib/`.
- **DIP**: Scripts should depend on `ux_lib` abstractions, not raw colors.

# TDD Protocol

1. **Analyze**: Understand the feature or bug.
2. **Test**: Write a test case (Python `pytest` or manual `shell-common/tools/custom/demo_ux.sh` scenario).
3. **Implement**: Write minimal Bash/Python code.
4. **Refactor**: Optimize while keeping tests green.
5. **Verify**: Run `tox` to ensure style compliance.

# Standards & References

- **Coding Style**: See `shell-common/tools/ux_lib/UX_GUIDELINES.md` and `tox.ini`.
- **Git Strategy**: Semantic commits (`Type: Summary`).
- **Maintenance**: Update AGENTS.md when adding new modules.

# Context Map

- **[Bash Module](./bash/AGENTS.md)** — Bash-specific configuration and utilities
- **[Zsh Module](./zsh/AGENTS.md)** — Zsh-specific configuration and applications
- **[Shell Common](./shell-common/AGENTS.md)** — POSIX-compatible shared utilities (env, aliases, functions, tools, projects)
- **[Git Hooks & Config](./git/AGENTS.md)** — Hook system, git config, and hook documentation
- **[Claude Code](./claude/AGENTS.md)** — Claude Code configuration, settings, skills, and automation
- **[Python Tests](./tests/AGENTS.md)** — pytest suite and cross-shell compatibility checks
- **[Documentation](./docs/AGENTS.md)** — Project docs, AGENTS.md master prompt, SOLID reviews

# Skills Management

## Multi-CLI Skills Registry

Skills are reusable AI agent behaviors stored in `./claude/skills/`. Each skill directory contains a `SKILL.md` file with YAML frontmatter (name, description, allowed-tools) and markdown instructions.

## Using Skills Across CLIs

### Claude Code (Built-in Support)
Use the built-in `/skill` command to load skills interactively within Claude Code sessions.

### Other CLIs (Codex, Gemini, etc.)
Use `skill-loader` to get the absolute path to skill files, then pipe into other CLIs:
```bash
# Get skill path
skill-loader req-define

# View skill content directly
cat "$(skill-loader cli-dev)"

# Pass skill to Codex
codex -p "$(cat "$(skill-loader req-define)")"

# Pass skill to Gemini
gemini -p @"$(skill-loader cli-dev)"
```

### Common Skills

| Skill | Description | Use Case |
|-------|-------------|----------|
| cli-dev | CLI development with TDD | Implement REQ-CLI-* requirements |
| req-define | Convert freeform to REQ format | Define feature requirements |
| req-workflow | 4-phase REQ implementation | Build features systematically |
| agents-md | AGENTS.md system generator | Create/update documentation |
| tox-lint | Auto-fix lint issues | Pre-commit standardization |

## Commands

```bash
skill-loader <skill-name>    # Get absolute path to skill file
skill-loader --list          # List all available skills
claude-skills                # List all available skills (function)
claude-help                  # Show Claude Code configuration
```

## Environment Variable

```bash
export CLAUDE_SKILLS_PATH="${DOTFILES_ROOT}/claude/skills"
```

# Naming Rules (Bash/Zsh)

- **File names**: snake_case with `.sh` (e.g., `git_help.sh`, `install_docker.sh`).
- **Function names**: snake_case (e.g., `git_help`, `install_docker`).
- **Aliases**: dash-form for user commands, mapped from snake_case functions.

# Naming Rules (Docs)

- **Markdown files**: dash-form (e.g., `setup-guide.md`, `ux-library-notes.md`); avoid camelCase or snake_case.
