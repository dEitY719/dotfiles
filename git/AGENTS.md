# Module Context

- **Purpose**: Git configuration, hooks, and hook documentation for this dotfiles repo.
- **Scope**: `git/` only (setup scripts, hook logic, hook docs, minimal tests).

# Operational Commands

- **Setup (via root)**: `./setup.sh` (installs git config and hooks as part of dotfiles setup)
- **Setup (direct)**: `bash git/setup.sh` (only if you know what it does; prefers running via `./setup.sh`)
- **Hook Tests**: `bash git/tests/test_hooks.sh`
- **Hook Debug**: `GIT_HOOKS_DEBUG=1 git commit -m "msg"` (shows why a commit is blocked)

# Golden Rules

- **No Credentials**: Never commit `*.git-credentials` or SSH keys; keep them ignored and local-only.
- **SSOT Config**: Treat `git/config/hook-config.sh` as the single source of truth for patterns and thresholds.
- **No Surprises**: Hook changes must be fast, deterministic, and explain failures clearly.
- **Test First**: Add a failing case to `git/tests/test_hooks.sh` before tightening checks.

# Testing Strategy

- Prefer `bash git/tests/test_hooks.sh` for integration-level verification of the 2-tier hook system.
- If a change targets repository-wide policy (naming, shebang, UX rules), also run `tox -e shellcheck`.

# Context Map

- **[Hook Setup Script](./setup.sh)** — Symlinks and hook installation logic (called by root `./setup.sh`)
- **[Global Hook](./global-hooks/pre-commit)** — User-level hook wrapper (`core.hooksPath`)
- **[Project Hook](./hooks/pre-commit)** — Project-level runner that delegates to checks
- **[Hook Checks](./hooks/checks)** — Modular checks executed by the project hook
- **[Hook Configuration](./config/hook-config.sh)** — Regex patterns, thresholds, and shared constants
- **[Git Docs](./doc/README.md)** — Hook workflow and SSH setup guides
