---
name: devx:prd-to-trd
description: >-
  PRD 1건을 컴포넌트별 TRD 스캐폴드로 분해한다. Use for /devx:prd-to-trd,
  /devx-prd-to-trd, "PRD를 TRD로 분해해줘", "PRD 한 개를 컴포넌트별 TRD 로
  쪼개줘", "scaffold TRDs from this product spec". TRD 를 Epic/Feature/Task
  이슈로 등록하는 것은 devx:trd-to-issues.
allowed-tools: Bash, Read, Edit, Write, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "PRD → multi-TRD decomposition; 8-section standard mapping; structured reasoning"
    claude: prefer
    non_claude: advisory-only
---

# devx:prd-to-trd — PRD → per-component TRD scaffolds

## Help

If arg #1 is `-h`/`--help`/`help`, read `references/help.md`, output it
verbatim, then stop. **No API calls, no file mutation.**

## Step 1: Parse Args + Validate PRD

Required positional: exactly one `<prd-path>`. Flags (`--dry-run`
default, `--apply`, `--plan-out <path>`, `--force`): full table in
`references/help.md`.

The `<prd-path>` must exist as a regular file — on a miss, print
`[FAIL] devx:prd-to-trd: PRD not found: <path>` and stop with exit 1.
v1 supports a single PRD only; if more than one positional argument
is supplied, stop with `[FAIL] multi-PRD input not supported in v1`
(multi-PRD batching is OQ-4 for a follow-up).

## Step 2: Read PRD + Propose Decomposition

Load the PRD via `Read`. Apply the heuristic in
`references/decomposition-rules.md` to extract component slugs (6–8,
kebab-case), responsibility mapping of each PRD `F-#` / `D-#` / `NF-#`
item, and adjacent-TRD pairs that share a contract.

PRDs with fewer than 2 viable groups → `[WARN] PRD too small —
single mega-TRD refused. Add more F-#/D-# or split.` and stop.

Locate the TRD template: search `<prd-dir>/trd/_template.md` first;
on miss, fall back to `references/template-fallback.md`. Both sources
missing → `[FAIL] template unavailable` + exit 1. Either template is the
agent-toolbox **8-section standard**: AI Spec-Driven 6 sections (AWS
Kiro / Spec Kit / Cursor) + Google Design Doc 2 sections (Goals /
Non-Goals, Alternatives Considered).

## Step 3: Write Plan

Write the decomposition to `--plan-out` using
`references/plan-format.md` as the canonical skeleton. The plan is
the single review surface — the user edits slugs and mappings, then
re-invokes with `--apply`.

In `--dry-run` (default), **stop here** and print:

```
Plan written: <plan-out> (<n> components)
Run with --apply to write TRD scaffolds.
```

## Step 4: Apply (only if `--apply`)

1. **Re-read plan** — round-trip the user-edited plan from
   `--plan-out`. Missing plan → stop with
   `[FAIL] plan not found at <path> — run --dry-run first`.
2. **For each component slug** — resolve `<prd-dir>/trd/<slug>.md`.
   - File exists + no `--force` → `[INFO] skip existing: <path>`
     and continue (idempotent).
   - Otherwise → render the template with frontmatter (책임 PRD
     항목, 인접 TRD, 소유자 placeholder) and write the 8-section
     scaffold per `references/plan-format.md` → "Scaffold layout" —
     headers + guidance blockquotes only, **never an AI-drafted body**.
3. `mkdir -p <prd-dir>/trd/` if needed (never above `<prd-dir>`).

Mid-flow write failure → report partial state (slugs written so far),
emit `[FAIL] devx:prd-to-trd <reason>` + exit 1. **No auto-rollback.**

## Step 5: Report

Print the verdict:

```
[OK] devx:prd-to-trd plan=<path> components=<n> [scaffolds=<n> skipped=<n>]
```

`scaffolds=` and `skipped=` appear only on `--apply`. For dry-run, append
`Next: review <plan-out>, then re-run with --apply`. Operational
constraints: see `references/constraints.md`.

## Related Skills

`devx:trd-to-issues` — next pipeline stage (human fills the scaffolds,
then TRD → Milestones + Issues); this skill owns the PRD → TRD slot.
