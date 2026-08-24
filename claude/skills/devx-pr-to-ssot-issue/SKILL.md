---
name: devx:pr-to-ssot-issue
description: >-
  PRD/TRD 없이 진행된 예외 PR(이미 머지됐거나 대응 이슈 없이 진행 중)을 역산해
  SSOT 추적 이슈로 등록한다. Use for /devx:pr-to-ssot-issue,
  /devx-pr-to-ssot-issue, "예외 PR 을 SSOT 이슈로", "이 PR 의 PRD 갭을 이슈로
  등록", "reverse-engineer this merged PR into a tracking issue".
allowed-tools: Bash, Read, Edit, Write, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "PR reverse-engineering + 8-section SSOT issue body; subagent gap detection; structured reasoning"
    claude: prefer
    non_claude: advisory-only
---

# devx:pr-to-ssot-issue — Exception PR → SSOT-recovery Issue

An **exception PR** is one that bypassed the project's normal
`Issue → PRD → TRD → 구현 → PR` workflow — it is already merged, or in
flight with no matching PRD/TRD issue. This skill reverse-engineers such
a PR into a SSOT-tracking issue so the workflow regains coverage. The
source PR is read-only; the only mutations are the new issue plus an
optional backlink comment on the parent.

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
--name-only`. Classify files and apply overlap guard per
[references/gap-detection.md](references/gap-detection.md) "Bucket rules".

## Step 3: Subagent Gap Analysis

Invoke subagent per [references/gap-detection.md](references/gap-detection.md)
"Subagent prompt". Apply empty-gap refusal if all five blocks are `(none)` → exit 4.

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

## Related Skills

`/devx:exception-merge-checklist` — entry-side recovery (this skill) +
exit-side gate (sister) together form the exception-PR roundtrip.
