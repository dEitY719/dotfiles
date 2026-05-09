# TRD: example-cli

> **Status**: Draft v1 (2026-05-09)
> **Owner**: @example
> **Adjacent TRDs**: (none)

## 1. Overview

A tiny example TRD used as a fixture for `devx:trd-to-issues`. It
intentionally describes only three Tasks across two Milestones so the
expected plan stays short enough to diff by eye.

## 2. Goals / Non-Goals

### Goals

- Ship `example-cli init` and `example-cli build` commands.
- Provide a flag `--dry-run` on both commands.

### Non-Goals

- Plugin loading.
- Multi-tenant config.

## 3. Architecture

```
+-----------+      +-----------+
|   shell   | ---> | example-  | --> ./build/
|           |      |    cli    |
+-----------+      +-----------+
```

## 4. Milestones

This TRD is decomposed into the following milestones:

- **M0a — Scaffold & Tooling**: project skeleton, lint, test scaffolding.
- **M0b — Commands**: user-facing `init` and `build` commands.

## 5. Tasks

### M0a — Scaffold & Tooling

#### T1 — chore(scaffold): bun + Next-style project bootstrap

Priority: ⚡ High

Acceptance Criteria:

- [ ] `bun install` succeeds on a fresh checkout.
- [ ] `bun test` runs zero tests successfully (scaffolding only).

#### T2 — chore(ci): tox lint pipeline

Priority: (none)

Depends on T1.

Acceptance Criteria:

- [ ] `tox -e ruff` passes on an empty src dir.
- [ ] `tox -e shellcheck` passes on an empty bash/ dir.

### M0b — Commands

#### T3 — feat(cli): example-cli init / build with --dry-run

Acceptance Criteria:

- [ ] `example-cli init` creates `./example.config.json`.
- [ ] `example-cli build --dry-run` prints the build plan and exits 0
      without writing files.
- [ ] Unit tests cover both commands.

Depends on T1, T2.
