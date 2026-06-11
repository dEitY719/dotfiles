---
name: devx:trd-to-issues
description: >-
  Decompose one or more TRD files (with optional companion PRD) into a
  three-level Epic → Feature → Task plan and, on `--apply`, register the
  resulting GitHub Milestones + Issues in bulk via `gh`. Use when the user
  runs /devx:trd-to-issues, /devx-trd-to-issues, or asks "TRD를 마일스톤/이슈로
  분해해줘", "PRD/TRD 파일로 일괄 등록", "decompose this TRD into milestones".
  Default mode is `--dry-run` — only writes a Markdown plan; `--apply` mutates
  GitHub. Refuses to auto-create missing labels and refuses an unknown remote.
  Accepts `-h`/`--help`/`help` to print usage.
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

Load each TRD (and optional PRD) via `Read`. Extract:

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

Detailed substep procedure: see [references/bulk-create-procedure.md](references/bulk-create-procedure.md)

## Step 5: Report

Print: `--plan-out` path, milestone count, task count, and (for
`--apply`) the URL of the first created milestone. End with the verdict:

```
[OK] devx:trd-to-issues plan=<path> milestones=<n> tasks=<n> [url=<repo-url>]
```

Operational constraints: see `references/constraints.md`.
