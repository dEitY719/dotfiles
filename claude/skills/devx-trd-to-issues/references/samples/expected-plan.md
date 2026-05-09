# TRD-to-Issues Plan
Generated: 2026-05-09T00:00:00
Source TRD: claude/skills/devx-trd-to-issues/references/samples/trd-fixture.md
Source PRD: (none)
Target repo: dEitY719/dotfiles
Mode: dry-run

## Milestone: M0a — Scaffold & Tooling
Description: Project skeleton, lint, and test scaffolding for the
example-cli package. First milestone — eligible for Ready promotion
on `--apply` unless `--no-ready` is set.

- [ ] #new-1 chore(scaffold): bun + Next-style project bootstrap
  - Labels: pro-friendly, ⚡ High
  - Depends on: (none)
  - AC:
    - [ ] `bun install` succeeds on a fresh checkout.
    - [ ] `bun test` runs zero tests successfully (scaffolding only).

- [ ] #new-2 chore(ci): tox lint pipeline
  - Labels: pro-friendly
  - Depends on: #new-1
  - AC:
    - [ ] `tox -e ruff` passes on an empty src dir.
    - [ ] `tox -e shellcheck` passes on an empty bash/ dir.

## Milestone: M0b — Commands
Description: User-facing `example-cli init` and `example-cli build`
commands, including `--dry-run` support and unit tests.

- [ ] #new-3 feat(cli): example-cli init / build with --dry-run
  - Labels: max-only
  - Depends on: #new-1, #new-2
  - AC:
    - [ ] `example-cli init` creates `./example.config.json`.
    - [ ] `example-cli build --dry-run` prints the build plan and
          exits 0 without writing files.
    - [ ] Unit tests cover both commands.

## Decomposition failures
_no failures._
