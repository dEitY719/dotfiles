---
name: devx:exception-merge-checklist
description: >-
  Run a 10-point read-only sanity check on a GitHub PR right before a
  merge on the "exception track" (CI green but hand-merged with extra
  scrutiny). Detects hidden regressions that ordinary CI gates miss:
  mid-rebase broken commits, OpenAPI lock drift, YAML indent breakage,
  over-scoped prettier writes, and missing test mocks for new framework
  calls (`cookies()` / `headers()` / `new NextRequest(`). Use when the
  user runs /devx:exception-merge-checklist,
  /devx-exception-merge-checklist, or asks "예외 트랙 머지 전 점검", "PR
  머지 직전 회귀 체크", "exception PR pre-merge audit". Read-only by
  default; `--auto-fix` only stages C8 / C9 fixes (no commit). Accepts
  `[<PR#>] [--skip-bisect] [--auto-fix] [--build-cmd <cmd>]` and
  `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit
metadata:
  model_recommendation:
    tier: haiku
    reason: "checklist generation with low reasoning; 10 read-only checks aggregated"
    claude: prefer
    non_claude: advisory-only
---

# devx:exception-merge-checklist — Pre-merge 10-point sanity check

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve PR

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Positional: `[<PR#>]`. Optional flags: `--skip-bisect`, `--auto-fix`,
`--build-cmd <cmd>`. Full table in `references/help.md`.

- `<PR#>` omitted → auto-detect via `gh pr view --json
  number,headRefName,baseRefName,url` on the current branch. No PR
  for the branch → exit 3.
- Resolve `TARGET_REPO=<owner>/<repo>` via `git remote get-url origin`
  (parse `https://github.com/<o>/<r>.git` or
  `git@github.com:<o>/<r>.git`). Missing remote → `git remote -v` and
  stop with exit 2.
- Bad / unknown flag → usage pointer and stop with exit 2.

## Step 2: Run 10 Checks

Read `references/checks.md` for the full definition of each check
(pass condition, command, recovery hint, rationale). Run C1–C5 and
C7–C10 in parallel; C6 is the only serial check because it walks
each commit. **No fail-fast** — every check runs to completion so
the report shows the full picture in one pass.

Each check returns one of `PASS` / `WARN` / `FAIL` / `N/A`. C6 is
fully opt-out via `--skip-bisect`. C7–C10 are **not** opt-outable —
they are the core regression detectors derived from the 2026-05-16
PR #727 retrospective (six concrete regressions, mapped one-to-one
to checks in `references/checks.md`).

## Step 3: Render Report

Read `references/report-template.md` for the exact format. The
report has the PR header, two tables (Gating C1–C5 + Regression
C6–C10), a Score line, a Verdict line, and a Recovery Actions
section with one bullet per WARN / FAIL (PASS / N/A produce no
bullet). Do NOT prepend filler prose.

## Step 4: Optional Auto-fix (`--auto-fix` only)

Only when `--auto-fix` is set AND the report shows at least one
deterministic FAIL among C8 (`.openapi-lock` regenerate via
`bash scripts/update-openapi-lock.sh`, then re-verify
`sha256sum -c`) or C9 (`bunx prettier --write` on the exact files
reported, scoped to `*.md` / `*.json` / `*.yml` / `*.yaml` only).
All other FAILs require human judgment and are never auto-fixed.

After fixes, `git add` the touched files only and stop. **Never run
`git commit`** — the user invokes `/gh:commit` separately so the
commit message is human-authored. Print the staged file list and a
hint pointing to `/gh-commit`.

## Step 5: AI Metrics Footer

Read `references/metrics-footer.md` for the comment format and
soft-fail policy. The footer is posted as a PR comment (not a body
edit) so it never conflicts with the per-step metric blocks written
by other skills. `GH_DISABLE_AI_METRICS=1` skips this step entirely
(issue #399 contract).

## Constraints

- **Read-only default.** Never merge, approve, push, or edit PR body/labels. Only `--auto-fix` mutates, and only as far as `git add` (never `git commit`).
- **No fail-fast.** All 10 checks run — aggregating in one pass is the whole point.
- **C6 opt-out via `--skip-bisect` only.** C7–C10 are not opt-outable — that would re-open the regression gap.
- **Exit codes**: `0` (all PASS or only WARN) / `1` (≥ 1 FAIL) / `2` (bad args, missing remote) / `3` (no PR detected).
- **Never silently switch the build command.** If `--build-cmd` is absent and `bun run build` does not exist, mark C6 `N/A` with the reason — do NOT guess `npm test`.
