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

- Milestones — TRD-named structure first; if absent, propose names and
  ask the user to confirm before continuing.
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

1. **Pre-validate labels** —
   `gh label list --repo "$TARGET_REPO" --json name --jq '.[].name'`.
   Any label referenced by the plan that is missing → stop with the
   missing list. **Never POST `/labels`** (memory:
   `feedback_gh_label_no_autocreate.md`).
2. **Bulk-create milestones** —
   `gh api repos/$TARGET_REPO/milestones -X POST -f title=... -f description=...`.
   Title collision → stop and report (no silent skip/merge).
3. **Create issues** — `gh issue create --repo "$TARGET_REPO" --title ...
   --body-file <tmp> --milestone <title> --label <name>...` per task.
4. **Resolve `#new-N` citations** — substitute virtual numbers with the
   real numbers returned by step 3, then `gh issue edit <real-N>
   --body-file <patched>`.
5. **Promote first milestone to Ready** (skip if `--no-ready`) —
   `claude-set-issue-status <real-N> "Ready"` per first-milestone issue.

Mid-flow failure: report partial state (created milestones / issues so
far) and stop — no automatic rollback.

## Step 5: Report

Print: `--plan-out` path, milestone count, task count, and (for
`--apply`) the URL of the first created milestone for human verification.

## Constraints

- Default is `--dry-run`. `--apply` must be explicit.
- Never auto-create labels — pre-validate, stop on miss.
- Never silently fall back when `--remote <name>` is missing.
- Never collapse the plan; the plan is the SSOT review surface.
- Decomposition criteria are mandatory; failed items go into a
  "decomposition failures" section, never silently dropped.
