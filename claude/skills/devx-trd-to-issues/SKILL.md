---
name: devx:trd-to-issues
description: >-
  TRD 를 Epic → Feature → Task 3단으로 분해하고, `--apply` 일 때만 GitHub
  Milestone/Issue 를 대량 등록한다. Use for /devx:trd-to-issues,
  /devx-trd-to-issues, "TRD를 마일스톤/이슈로 분해해줘", "TRD 로 이슈 일괄 등록",
  "decompose this TRD into issues". PRD → TRD 스캐폴드는 devx:prd-to-trd.
allowed-tools: Bash, Read, Edit, Write, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "TRD decomposition + bulk issue creation"
    claude: prefer
    non_claude: advisory-only
---

# devx:trd-to-issues — TRD → Milestones + Issues

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No API calls.**

## Step 1: Parse Args + Resolve Repo

Required positional: one or more `<trd-path>`. Flags: `--prd <path>`,
`--remote <name>` (default `origin`), `--dry-run` (default), `--apply`,
`--plan-out <path>` (default `.claude/.trd-to-issues.plan.md`),
`--no-ready`. See `references/help.md` for the full table.

Resolve `TARGET_REPO=<owner>/<repo>` per `references/repo-resolution.md`.
Missing remote → list `git remote -v` and stop. **No silent fallback.**
Every `<trd-path>` and `--prd <path>` must exist as a regular file; on
the first miss, list the missing path and stop.

## Step 2: Read TRD/PRD + Decompose

Load each TRD (and optional PRD) via `Read`. Decompose into three
levels — **Epic → Feature → Task** (Epic = the TRD-scale outcome,
Feature = a milestone-sized slice, Task = the issue that is actually
filed). Extract:

- Milestones — TRD-named structure first; if absent, write the
  proposed names directly into the dry-run plan (under each
  `## Milestone:` heading) so the user reviews them in the plan file
  and edits or re-runs before `--apply`. Never block mid-flow on a
  confirmation prompt — Claude Code is non-interactive and `read`
  would hang.
- Tasks — each must satisfy the criteria in
  `references/decomposition-rules.md` (≤ 3 ACs, unit-testable,
  independently committable). Items that fail the criteria are split
  further or reported as "decomposition failures" in the plan.
- Dependencies — extract `Depends on #...` keywords; emit virtual
  citations (`#new-1`, `#new-2`, ...) that resolve to real numbers
  during `--apply`.
- Labels — apply the `pro-friendly` / `max-only` heuristic from
  `references/decomposition-rules.md`; merge any priority labels named
  in the TRD.

## Step 3: Write Plan

Write the decomposition to `--plan-out` using
`references/plan-format.md` as the canonical skeleton. The plan is the
single review surface for the user — it must round-trip back into Step 4
without re-reading the TRD.

In `--dry-run`, **stop here** and print:

```
Plan written: <plan-out> (M milestones, N tasks)
Run with --apply to register on GitHub.
```

## Step 4: Apply (only if `--apply`)

Nothing is registered on GitHub without an explicit `--apply` — the
default `--dry-run` writes the plan and stops. Bulk registration (label
pre-validation → milestones via `gh api` → `gh issue create` per Task →
`#new-N` resolution → Ready promotion) and its mid-flow-failure rules:
[references/bulk-create-procedure.md](references/bulk-create-procedure.md).

## Step 5: Report

Print: `--plan-out` path, milestone count, task count, and (for
`--apply`) the URL of the first created milestone. End with the verdict:

```
[OK] devx:trd-to-issues plan=<path> milestones=<n> tasks=<n> [url=<repo-url>]
```

Operational constraints: see `references/constraints.md`.

## Related Skills

`devx:prd-to-trd` — previous pipeline stage (PRD → per-component TRD
scaffolds); this one starts from filled-in TRDs. `gh:issue-create` —
single-issue alternative when bulk decomposition is overkill.
