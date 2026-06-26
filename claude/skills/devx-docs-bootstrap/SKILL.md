---
name: devx:docs-bootstrap
description: >-
  Scaffold a standard kind-split docs/ tree in an empty or new repository —
  the "folder = document kind, feature = filename" policy. Creates
  docs/{adr,product,design,architecture/{system,features},testing,guides,public}
  with a .gitkeep in every leaf directory (so git tracks the empty folders)
  and a single docs/README.md describing the documentation policy + three
  Docs-as-Code rules (status front-matter, ADR cross-linking, filename
  linter). Use when the user runs /devx:docs-bootstrap, /devx-docs-bootstrap,
  or asks "새 프로젝트 docs 구조 만들어줘", "빈 repo에 문서 폴더 스캐폴딩",
  "docs 디렉토리 골격 깔아줘", "scaffold docs structure", "bootstrap docs
  folders". Default mode is --dry-run (prints the plan, writes nothing);
  --apply creates the tree; --check is a read-only conformance audit
  (CI-friendly, non-zero exit on drift). Idempotent — existing files are
  skipped. Sister skill of [[gh-kanban-bootstrap]] (board) — this one is the
  docs-layout half of new-repo setup. Accepts -h/--help/help to print usage.
allowed-tools: Bash, Read
metadata:
  model_recommendation:
    tier: haiku
    reason: "Deterministic scaffolder — all logic lives in lib/scaffold.sh; the skill only dispatches and reports"
    claude: prefer
    non_claude: advisory-only
---

# devx:docs-bootstrap — scaffold a kind-split docs/ tree

All real work lives in `lib/scaffold.sh` (self-contained, copy-paste safe).
The skill's job is to dispatch the right mode and relay the result.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. **No filesystem access.**

## Step 1: Parse Args

Positional `[path]` (target repo root, default `.`). Flags: `--dry-run`
(default), `--check`, `--apply`, `--force`. Full table in `references/help.md`.
Mode priority: `--help` > `--check` > `--apply` > `--dry-run`.

Do not re-implement the layout — `lib/scaffold.sh` is the SSOT for the
8 leaf directories and the `docs/README.md` body
(`references/docs-readme-template.md`).

## Step 2: Run the scaffolder

Invoke the script with the parsed args, from the skill's own directory so the
relative template path resolves:

```bash
bash "$(dirname "$0")/lib/scaffold.sh" <path> [--check|--apply|--dry-run] [--force]
```

(When invoked as a skill, pass the user's args through verbatim; the script
parses them itself.)

- **`--dry-run` (default)** — prints the create/skip plan, writes nothing,
  always exits 0.
- **`--check`** — read-only audit; exits 0 if `docs/` already has all 8 leaf
  dirs + `.gitkeep` + `README.md`, non-zero otherwise (use as a CI gate).
- **`--apply`** — `mkdir -p` the tree, `touch` a `.gitkeep` per leaf, write
  `docs/README.md` (skipped if present unless `--force`).

The script is idempotent: existing paths are skipped with a `skip` line.

## Step 3: Report

Relay the script's `[OK]`/`[FAIL]` verdict and the create/skip plan. On
`--apply` success, remind the user the empty folders are tracked via
`.gitkeep` and can be deleted once real docs land. End with a `Next:` hint
(e.g. `git add docs/ && git commit`, or `/gh-kanban-bootstrap` for the board).

## Constraints

- Never author document bodies beyond `docs/README.md` — folders stay empty
  (just `.gitkeep`). Populating PRD/TRD/ADR content is out of scope.
- Never migrate an existing populated `docs/` — this skill only scaffolds.
- Never overwrite `docs/README.md` without `--force`.
- Default to `--dry-run`; only write on explicit `--apply`.
