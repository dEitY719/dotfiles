# Project Context

- **Objective**: Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
- **Stack**: Bash 5.x+, Python 3.10+, Tox, Ruff, Mypy.
- **Structure**: Modular Bash (`bash/`), Zsh (`zsh/`), shared shell (`shell-common/`), Tests (`tests/`), Docs (`docs/`), Git hooks (`git/`), Claude Code (`claude/`).

# Package Manager Configuration

All managed by `shell-common/setup.sh` (environment menu: public / internal / external).

| Manager | Config Dir | Target | Method | Gate |
|---------|-----------|--------|--------|------|
| npm | `npm/` | `~/.npmrc` | symlink | -- |
| pip | `pip/` | `~/.config/pip/pip.conf` | symlink | -- |
| uv | `uv/` | `~/.config/uv/uv.toml` | symlink | -- |
| Cargo | `cargo/` | `~/.cargo/config.toml` | symlink | -- |
| NuGet | `nuget/` | `~/.nuget/NuGet/` + `~/.config/NuGet/` | symlink (dual) | -- |
| RPM | `rpm/` | `/etc/yum.repos.d/ds.repo` | sudo copy | RHEL 8.x + yum/dnf |
| APT | `apt/` | `/etc/apt/sources.list` | sudo copy | Ubuntu + codename match |

- **User-level** (npm/pip/uv/cargo/nuget): symlink to `{dir}/{config}.internal`, backup+restore on switch.
- **System-level** (rpm/apt): sudo copy with 3-gate safety (tool exists, OS match, privilege), `MANAGED_BY_DOTFILES` marker.
- **Adding new manager**: create `{dir}/{config}.internal`, add `setup_{name}()`, wire into `main()` 3 menu cases.

# Operational Commands

- **Setup**: `./setup.sh` (Symlinks), `./install.sh` (Full install).
- **Linting (All)**: `tox` (Runs ruff, mypy, shellcheck, shfmt).
- **Linting (Python)**: `tox -e ruff` (fixes), `tox -e mypy`.
- **Linting (Bash)**: `tox -e shellcheck`, `tox -e shfmt` (formats).
- **Note**: Markdown linting (mdlint) is DISABLED. Do NOT perform markdown lint checks automatically.
- **Testing**: `./tests/test`, `pytest tests/`, manual validation via `shell-common/tools/custom/demo_ux.sh`.

# Golden Rules

## Immutable Constraints

- **100-Line Limit**: Every AGENTS.md file must be under 100 lines — use nested AGENTS.md files for detail.
- **No Emojis**: Strictly prohibited to save tokens.
- **Interactive Guards**: Bash files must guard execution: `[[ $- == *i* ]]`.
- **Loading Order**: Respect `bash/main.bash` priority (Env -> UX -> Alias -> App).
- **No Direct Writes**: Do not write to `~/.bashrc` directly; use symlinks via `setup.sh`.

## Do's & Don'ts

- **DO**: Use `ux_lib` functions (`ux_header`, `ux_success`) for ALL output.
- **DO**: Use snake_case for all Bash functions and filenames.
- **DO**: Run `tox` before committing.
- **DO**: Use environment variables (e.g., `$SHELL_COMMON`) for sourcing files across shell contexts.
- **DO**: Test scripts in both bash and zsh for cross-shell compatibility.
- **DO**: Follow directory placement rules — see **[Shell Common](./shell-common/AGENTS.md)**.
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency).
- **DON'T**: Hardcode paths; use `$HOME` or relative paths.
- **DON'T**: Commit secrets or sensitive data.
- **DON'T**: Use `${BASH_SOURCE[0]%/*}` for sourcing (bash-only, fails in zsh); use `${SHELL_COMMON}/path`.

See **[Shell Common](./shell-common/AGENTS.md)** for directory placement guide (aliases/ vs functions/ vs tools/),
Direct-Exec Guard pattern, Bash/Zsh compatibility rules, and diagnostic design standards.

# Design Principles

SRP/OCP/LSP/ISP apply per-file. DRY: move shared logic to `bash/util/` or `shell-common/tools/ux_lib/`.
Depend on `ux_lib` abstractions (not raw colors). See `shell-common/tools/ux_lib/UX_GUIDELINES.md`.

TDD cycle: Analyze → Write test (`pytest` or `demo_ux.sh`) → Implement minimal code → Refactor → `tox`.

# Standards & References

- **Coding Style**: See `shell-common/tools/ux_lib/UX_GUIDELINES.md` and `tox.ini`.
- **Command UX Standard**: See `docs/standards/command-guidelines.md` (SSOT for command/help interface and formatting).
- **Git Strategy**: Semantic commits (`Type: Summary`).
- **Project Board**: See `docs/standards/github-project-board.md` (SSOT for Issue kanban workflow and closing-keyword policy).
- **Known Pitfalls**: `Agent({ isolation: "worktree" })` is blocked by git-crypt smudge filter in this repo — see `claude/AGENTS.md` ("Known Pitfall: Agent isolation + git-crypt") and `docs/learnings/git-crypt-worktree-bootstrap.md`.
- **Maintenance**: Update AGENTS.md when adding new modules.

# Context Map

- **[Bash Module](./bash/AGENTS.md)** — Bash-specific configuration and utilities
- **[Zsh Module](./zsh/AGENTS.md)** — Zsh-specific configuration and applications
- **[Shell Common](./shell-common/AGENTS.md)** — POSIX-compatible shared utilities (env, aliases, functions, tools, projects)
- **[Git Hooks & Config](./git/AGENTS.md)** — Hook system, git config, and hook documentation
- **[Claude Code](./claude/AGENTS.md)** — Claude Code configuration, settings, skills, and automation
- **[Python Tests](./tests/AGENTS.md)** — pytest suite and cross-shell compatibility checks
- **[Documentation](./docs/AGENTS.md)** — Project docs, AGENTS.md master prompt, SOLID reviews

See **[Claude Code](./claude/AGENTS.md)** for skills management, multi-CLI registry, and commands.

# Naming Rules

- **Bash file names**: snake_case with `.sh` (e.g., `git_help.sh`, `install_docker.sh`).
- **Bash function names**: snake_case (e.g., `git_help`, `install_docker`).
- **Aliases**: dash-form for user commands, mapped from snake_case functions.
- **Markdown files**: dash-form (e.g., `setup-guide.md`, `ux-library-notes.md`).
