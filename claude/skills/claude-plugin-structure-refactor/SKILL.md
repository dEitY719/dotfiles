---
name: claude-plugin:structure-refactor
description: >-
  Fix a claude-plugin marketplace repo's directory structure toward the
  standard layout. Dry-run by default (plan only, no writes); `--apply`
  performs changes. Scope `--mp`/`--mandatory` fixes mandatory items M1-M6
  only (create dirs, `git mv`, minimal marketplace.json/plugin.json
  skeletons); `--op`/`--recommended` adds recommended R1-R4 fixes (empty
  placeholder stubs + naming correction). Idempotent. Use when the user
  says "fix my claude-plugin repo structure", "make this marketplace repo
  standard", "/claude-plugin:structure-refactor". Sister skill of
  `claude-plugin:structure-check` (which finds what this fixes). Does NOT
  generate real guide/usage content — stubs only.
compatibility:
  tools: Read, Glob, Grep, Write, Edit, Bash
metadata:
  model_recommendation:
    tier: sonnet
    reason: "structure correction: dir creation + git mv history-preserving moves + JSON skeletons + placeholder stubs; bounded multi-file write, no deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# claude-plugin Structure Refactorer

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No filesystem changes.

## Step 1: Parse Args + Resolve Path

Positional `[repo-path]` (default = current dir). Flags:

- `--apply` — execute changes. Absent → dry-run (plan only, no writes).
- `--mandatory` / `--mp` — scope = M1-M6 only (default scope).
- `--recommended` / `--op` — scope = M1-M6 + R1-R4.
- `--mp` and `--op` together → error + usage, stop.

Confirm the path exists. `test -d <path>/.git`: not a git repo → warn (moves
fall back to `mv`). Dirty tree → show the dry-run plan and require an
explicit `--apply` before writing (never auto-apply on a dirty tree).

## Step 2: Evaluate Current ↔ Target

Read `references/structure-spec.md` (embedded SSOT — identical copy to
structure-check's). Run the same M1-M6 / R1-R4 evaluation as
`claude-plugin:structure-check` to compute the current → target diff.
Discover plugins/skills dynamically (`plugins/*/`, `plugins/*/skills/*/`).

## Step 3: Build the Plan

Read `references/plan-and-report-templates.md`. Produce an ordered change
list, each tagged with its driving check ID (M1-M6, and R1-R4 only when
scope is `--op`). Already-correct items produce no action (idempotent).

## Step 4: Dry-run or Apply

- **Dry-run (default)**: print the plan only. Touch nothing.
- **`--apply`**: execute the plan in order, per
  `references/plan-and-report-templates.md` → "Apply rules":
  - create missing dirs: `.claude-plugin/`, `docs/skill-guides/`,
    `docs/skill-output/`, `plugins/<p>/skills/`;
  - move misplaced files with `git mv` when possible (else `mv`);
  - write minimal skeletons for a missing `marketplace.json` / `plugin.json`
    (filled with discovered plugin/skill names);
  - **`--op` only**: create empty R1/R2 placeholder stubs (TODO header +
    "fill with /devx:visualize" comment) and correct R4 naming mismatches.

## Step 5: Report

Use the completion report template in
`references/plan-and-report-templates.md`. End with `[OK]` or `[FAIL]` plus
a key=value summary, then the next-action hint:

- after a dry-run: `Next: /claude-plugin:structure-refactor <path> --apply [--op]`
- after `--apply`: `Next: /claude-plugin:structure-check <path>` (re-verify)

## Constraints

- Dry-run is the default — only `--apply` writes. Never auto-apply on a
  dirty tree.
- Idempotent: an already-standard repo (within scope) is a no-op.
- Placeholder stubs only — never call `/devx:visualize` or
  `/devx:excalidraw-diagram` to generate real content (that is out of
  scope; the stub carries a TODO pointing there).
- Prefer `git mv` to preserve history; fall back to `mv` outside a git repo.
- Repo-agnostic: discover plugins/skills by scan; the spec is embedded.
