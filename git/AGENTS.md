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
- **Internal hosts stay out of the SSOT (#2006)**: `git/.gitconfig` ends with `[include] path = ~/.gitconfig.internal.local` (and `ssh/config` starts with `Include ~/.ssh/config.internal.local`); internal PCs hold the GHES credential section / internal Host blocks there, seeded from git history by `scripts/internal-ssh-git-migrate.sh` (internal-mode `./setup.sh` runs it). `git/setup.sh` takes the GHES host from `DOTFILES_GHES_HOST` (`_gh_ghes_host`), never a literal.

# Testing Strategy

- Prefer `bash git/tests/test_hooks.sh` for integration-level verification of the 2-tier hook system.
- If a change targets repository-wide policy (naming, shebang, UX rules), also run `mise run lint-sh`.

# Global Hook Wrappers (issue #1664)

`git config --global core.hooksPath ~/.config/git/hooks` **replaces**
`.git/hooks` for every repo on the machine — git never merges the two and
never falls back. So a project hook only ever runs when a wrapper of the same
name exists in the global dir. `git/setup.sh` links every name in
`GIT_GLOBAL_HOOKS` (SSOT: `config/hook-config.sh`); anything missing there is
dead code, not a fallback.

`global-hooks/pre-commit` carries universal safety checks **and** delegates.
The other wrappers (`pre-push`, `commit-msg`, `prepare-commit-msg`, `post-commit`,
`post-checkout`, `post-merge`, `post-rewrite`) are delegation-only: they forward to the first of
`.githooks/<name>` → `git/hooks/<name>` → `.git/hooks/<name>` **relative to
the repo being operated on**, passing argv, stdin and the exit code through,
and are a silent no-op anywhere that path does not exist (never link
`git/hooks/*` into the global dir directly). One exception (#1838):
`post-merge`/`post-rewrite rebase`/`post-checkout` (fast-forward `git rebase` only)
first run `lib/graphify-refresh.sh` — a background `graphify update .` on the
default branch, opt-in by `graphify-out/graph.json`.

Third-party installers also write here (git-lfs owns `pre-push`,
`post-commit`, `post-checkout`, `post-merge`). setup.sh backs up a colliding
real file as `<name>.original` and warns; re-install that tool afterwards
(e.g. `git lfs install --force`).

Regression: `git/tests/test_hooks.sh` (delegation + no-op) and
`tests/bats/git/test_global_hooks.bats` (SSOT, setup.sh linking, hook_check).

# Local Smoke (issues #754, #2046)

`hooks/pre-push` Layer 0 runs `mise run test-smoke` (`scripts/test_smoke.sh`)
once per push over the push range: changed-shell `bash -n`/`zsh -n`, the bats
files mapped from changed paths, `pytest -m smoke`, under a 60s budget
(overrun = warn, not fail; `not ok` seen before the cut still fails). Full `mise run test` runs non-blocking in CI
(`.github/workflows/test.yml`) or locally with `PRE_PUSH_FULL_TEST=1`.
Bypass: `SKIP_LOCAL_PYTEST=1`; mise missing = silent skip. SSOT:
`docs/.ssot/local-test-policy.md`. Regression:
`tests/bats/git/test_pre_push_pytest.bats`, `tests/bats/scripts/test_smoke.bats`.

# Protected Branches (#2033)

`config/pre-push-rules.sh` `PROTECTED_BRANCHES` = `master`, `release/*`. `main` is
excluded on purpose: `git sync` (merge upstream, then `git push origin main`)
is the standard sync path. `gcp scan` is the fallback for widely diverged
history. Pre-commit `main_branch_guard` is unchanged.

# Upstream Leak Guard (#708, #1970)

Opt-in guard against internal identifiers reaching the public upstream, in
two stages reading the same env (SSOT `config/pre-push-rules.sh`, empty =
inert): `UPSTREAM_REMOTES_ERE` + `LEAK_PATTERNS_ERE`. `hooks/pre-push`
Layer 2 scans the push range; `hooks/checks/leak_pattern_check.sh` blocks
staged added lines at commit time, printing `file:line` only. When active,
the whole pre-commit output (global + project hook) is redacted via the
shared `global-hooks/lib/leak_guard.sh`. Escape hatch:
`SKIP_LEAK_GUARD=1` (both stages). Per-PC activation (fake patterns only),
dry-run check and tests: [doc/LEAK_GUARD.md](./doc/LEAK_GUARD.md).

# Context Map

- **[Hook Setup Script](./setup.sh)** — Symlinks and hook installation logic (called by root `./setup.sh`)
- **[Global Hooks](./global-hooks)** — User-level wrappers installed at `core.hooksPath`; `pre-commit` also runs universal checks, the rest delegate only
- **[Project Hook](./hooks/pre-commit)** — Project-level runner that delegates to checks
- **[Pre-push Hook](./hooks/pre-push)** — Test smoke + protected-branch (master, release/*) + upstream leak-guard layers
- **[Hook Checks](./hooks/checks)** — Modular checks executed by the project hook; `shellcheck_check.sh` mirrors `mise run lint-sh` (bash/, shell-common/: CI flags; other shell files: `-S error`; zsh skipped) so it is never stricter than CI (#2014)
- **[Hook Configuration](./config/hook-config.sh)** — Regex patterns, thresholds, and shared constants
- **[Pre-push Rules](./config/pre-push-rules.sh)** — Protected branches + leak-guard SSOT
- **[gcp-scan Skip List](./config/gcp-scan-skip.conf)** — Known-resolved SHAs `gcp scan` skips silently (issue #1039; `gcp scan --show-skip-list`, override `GCP_SCAN_SKIP_FILE`)
- **[Git Docs](./doc/README.md)** — Hook workflow and SSH setup guides
