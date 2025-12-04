# Repository Guidelines

## Project Structure & Module Organization
- `bash/`: Main Bash dotfiles. `main.bash` is the entrypoint, `alias/` for shortcuts, `app/` for tool integrations (git, pyenv, postgres, mysql, npm, etc.), `env/` for environment variables, `ux_lib/` for shared logging/UX helpers, and `setup.sh` to link into `~/.bashrc` and `~/.bash_profile`.
- `git/`: Git config and `setup.sh` to symlink `.gitconfig`.
- `install.sh`: Optional extras (Claude/Codex helpers, statusline, agents).
- `tests/`: Placeholder for future checks; add new tests here.
- Python project metadata lives in `pyproject.toml`; tox config in `tox.ini`.

## Build, Test, and Development Commands
- Install dev deps: `uv pip install -e .[dev]` (or `pip install -e .[dev]`).
- Symlink dotfiles: `./setup.sh` (creates `~/.bashrc` → `bash/main.bash` and `~/.bash_profile` → `bash/profile.bash`).
- Optional extras: `./install.sh` (Claude/Codex assets).
- Lint/format shell: `tox -e shellcheck`, `tox -e shfmt`.
- Python quality: `tox -e ruff`, `tox -e mypy`.
- Run all configured checks: `tox`.

## Coding Style & Naming Conventions
- Bash: Keep scripts POSIX/Bash-compatible; prefer functions over inline scripts. Use `shfmt` defaults and fix warnings flagged by `shellcheck`.
- Python (utility tooling): Follow ruff/mypy guidance; type where practical. Use snake_case for files/functions.
- Aliases/functions: Descriptive, lower_snake_case (e.g., `git_prune`, `mysql_dmc_dev`). Place tool-specific logic under `bash/app/`.

## Testing Guidelines
- No formal unit suite yet; rely on tox jobs. Add new shell or Python checks under `tests/` and wire them into `tox.ini`.
- When adding interactive helpers, include a non-interactive guard and a dry-run path if possible.

## Commit & Pull Request Guidelines
- Commit messages follow `Type: Summary` (e.g., `Fix: Prevent dotfiles init in non-interactive environments`, `Cleanup: Remove deprecated module`).
- Keep commits focused; explain behavioral changes in the body when non-trivial.
- PRs: describe scope, risks, and verification (commands run). Link related issues; include screenshots/terminal snippets if UX output changes.

## Security & Environment Notes
- Default guards: `DOTFILES_SKIP_INIT=1` skips sourcing; `DOTFILES_FORCE_INIT=1` forces load; `CODEX_CLI`/Codex environments should skip heavy init to avoid sandbox write errors.
- Files that write to `$HOME` (e.g., DB configs) must remain opt-in for non-interactive/sandboxed sessions.
- Preserve Korean-only user comms when interacting via Codex/agents; internal notes and code comments stay concise in English.
