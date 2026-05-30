---
name: devx:pr-to-ssot-issue
description: >-
  Reverse-engineer an exception PR (already merged or in-flight without a
  matching PRD/TRD issue) into a SSOT-tracking GitHub issue so the project's
  normal Issue → PRD → TRD → 구현 → PR workflow regains coverage. Use when the
  user runs /devx:pr-to-ssot-issue, /devx-pr-to-ssot-issue, or asks "예외 PR
  을 SSOT 이슈로", "이 PR 의 PRD 갭을 issue 로 등록", "reverse-engineer this PR
  into a tracking issue". Read-only on the source PR; the only mutation is a
  new GitHub issue (plus optional backlink comment on the parent). Refuses
  when `--reason` is empty or shorter than 10 characters — the exception
  audit trail is mandatory. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Edit, Write, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "PR reverse-engineering + 8-section SSOT issue body; subagent gap detection; structured reasoning"
    claude: prefer
    non_claude: advisory-only
---

# devx:pr-to-ssot-issue — Exception PR → SSOT-recovery Issue

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No API calls.**

## Step 1: Parse Args + Resolve Repo + Preconditions

Record `START_TS=$(date +%s)` immediately (used in Step 6).

Required positional: `<PR#>`. Full flag table in `references/help.md`.
Control-flow flags: `--reason "<text>"` (≥ 10 chars, mandatory),
`--remote <name>` (default `origin`; resolve `TARGET_REPO` per
`references/repo-resolution.md`), `--dry-run`, `--force-overlap`.

Preconditions (fail-fast, parallel): (1) `<PR#>` is a positive integer;
(2) `--reason` length ≥ 10 after trim — else exit 2; (3) `gh pr view
<PR#>` returns `state ∈ {OPEN, MERGED}` — `CLOSED` (unmerged) → exit 1.

## Step 2: PR Diff Fetch + 4-Bucket Classification

Fetch PR meta + file list via `gh pr view --json …` and `gh pr diff
--name-only`. Classify every changed file into exactly one of **code /
schema / infra / docs** per `references/gap-detection.md` "Bucket
rules". One-line gap hypothesis per bucket; empty buckets stay in the
table with `0` and `(none)`.

**Overlap guard.** If any `Closes #N` / `Fixes #N` linked issue body
contains a PRD or TRD section (`## PRD`, `## TRD`, `### Goals`,
`### Requirements`) → exit 3 unless `--force-overlap` is set.

## Step 3: Subagent Gap Analysis

Invoke one foreground subagent (prefer `Explore`; fall back to
`general-purpose`). Pass the verbatim prompt from
`references/gap-detection.md` → "Subagent prompt" plus the classified
bucket table and PR meta. Cap output at ~300 lines.

Agent returns five blocks: A. Glossary, B. API 계약, C. Data Models,
D. Deployment, E. Cross-refs. Empty blocks stay as `(none)`.

**Empty-gap refuse.** Every block exactly `(none)` → exit 4.

## Step 4: Render Issue Body

Render the 8-section body per `references/issue-body-template.md`:
Why · Scope (bucket table + subagent report) · Acceptance Criteria ·
Out of Scope · Parent / Related · Audit (`--reason` verbatim in
`> [!IMPORTANT]`) · TODO 후속 · 관계 / Cross-refs.

Append the ai-metrics footer per `references/metrics-footer.md`. Title
format: `docs(ssot): #<PR#> 역공학 — <PR title (truncated to 60 chars)>`.

## Step 5: Confirm + Create

Follow `references/create-cmd.md` 5.1 – 5.7: write draft, preview,
`--dry-run` exit, label/milestone pre-validation, `gh issue create
--body-file`, optional parent backlink (soft-fail, suppressed by
`GH_DISABLE_AI_METRICS=1`), and source-PR read-only enforcement.

## Step 6: Report

Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`. Output the
success / `--dry-run` / failure block per `references/report-format.md`.
Suppress the `Next:` line when `--no-next-hint` is set.

## Constraints

See `references/constraints.md` for the full list. Highlights:

- `--reason` ≥ 10 chars (audit trail). Source PR is read-only — no
  `gh pr edit/comment/review`. Never auto-create labels or milestones.
  Fail-closed on overlap / empty-gap / unknown-remote. Respect
  `GH_DISABLE_AI_METRICS=1`. No automatic rollback on mid-flow
  failure. No auto-chaining to `/gh-issue-flow`.

## Sister skill

`/devx:exception-merge-checklist` (TODO, 별도 이슈) — entry-side
recovery (this skill) + exit-side gate (sister skill) together form
the exception-PR roundtrip.
