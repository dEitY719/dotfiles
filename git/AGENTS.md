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
- **~/.gitconfig include model (NOT a symlink)**: `git/setup.sh` creates `~/.gitconfig` as a **real machine-local file** whose first section is `[include] path = <repo>/git/.gitconfig`. Never symlink `~/.gitconfig` to the tracked SSOT. Reason: tools that run `git config --global` — chiefly `gh auth setup-git` (triggered by `gh auth login`/`refresh`) — write **through** a symlink and rewrite the SSOT's portable credential-helper line (`git/scripts/gh-credential-helper.sh`, which probes multiple `gh` install paths across PCs) into a machine-specific absolute path, breaking portability. With the include model those writes land in the local file and the SSOT stays clean. Same principle as CLAUDE.md's settings.json "real file, not symlink" rule. Defense in depth: `gh/config.yml` sets `git_protocol: ssh` so `gh` stops managing HTTPS credential helpers at all.

# Testing Strategy

- Prefer `bash git/tests/test_hooks.sh` for integration-level verification of the 2-tier hook system.
- If a change targets repository-wide policy (naming, shebang, UX rules), also run `mise run lint-sh`.

# Local Pytest (issue #754)

`hooks/pre-push` runs `mise run test` once per push (Layer 0, before the
per-ref loop). This replaces the GitHub Actions `Test (mise)` job — CI now
runs lint only. SSOT: `docs/.ssot/local-test-policy.md`.

Skip mechanisms:
- `SKIP_LOCAL_PYTEST=1` — explicit opt-out (logged, exit 0).
- `mise` not on `PATH` — silent skip with one stderr note (external
  contributor / CI fallback).
- `SKIP_PRE_PUSH=1` — bypasses this layer along with the rest.

Regression: `tests/bats/git/test_pre_push_pytest.bats` (4 cases — skip,
missing, success, failure).

# Upstream Push Leak Guard

`hooks/pre-push` Layer 2 runs after the protected-branch check: when the
push target URL matches `UPSTREAM_REMOTES_ERE`, it scans the push range
(commit messages + added/modified file contents) against `LEAK_PATTERNS_ERE`
and blocks the push on any match.

Both variables default to the empty string, so the mechanism is inert until
the user opts in. Activate by exporting in your shell rc or a gitignored
local file:

```sh
export UPSTREAM_REMOTES_ERE='github\.com[:/]<owner>/<repo>(\.git)?$'
export LEAK_PATTERNS_ERE='<your-private-host>\.example\.com|/your-private-overlay/'
```

Escape hatches: `SKIP_PRE_PUSH=1` (whole hook), `SKIP_LEAK_GUARD=1` (this
layer only — protected-branch check still runs). SSOT lives in
`config/pre-push-rules.sh`; regression tests in `test/test-pre-push.sh`
(T-1..T-7).

# Context Map

- **[Hook Setup Script](./setup.sh)** — Symlinks and hook installation logic (called by root `./setup.sh`)
- **[Global Hook](./global-hooks/pre-commit)** — User-level hook wrapper (`core.hooksPath`)
- **[Project Hook](./hooks/pre-commit)** — Project-level runner that delegates to checks
- **[Pre-push Hook](./hooks/pre-push)** — Protected-branch + upstream leak-guard layers
- **[Hook Checks](./hooks/checks)** — Modular checks executed by the project hook
- **[Hook Configuration](./config/hook-config.sh)** — Regex patterns, thresholds, and shared constants
- **[Pre-push Rules](./config/pre-push-rules.sh)** — Protected branches + leak-guard SSOT
- **[gcp-scan Skip List](./config/gcp-scan-skip.conf)** — Known-resolved SHAs `gcp scan` skips silently (issue #1039; `gcp scan --show-skip-list`, override `GCP_SCAN_SKIP_FILE`)
- **[Git Docs](./doc/README.md)** — Hook workflow and SSH setup guides
