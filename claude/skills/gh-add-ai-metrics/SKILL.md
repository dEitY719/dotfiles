---
name: gh:add-ai-metrics
description: >-
  Backfill the ai-metrics footer (📊 tokens · 👤 human-h · 🤖 ai-min) into
  pre-existing GitHub Issues and PRs that were created before issue #317 /
  PR #320 introduced automatic metric capture. Use when the user runs
  /gh:add-ai-metrics, /gh-add-ai-metrics, or asks "기존 이슈에 메트릭
  소급 부착", "지난주 PR 들에 ai-metrics 붙여줘", "retrofit metrics
  on issue #N", "backfill ai-metrics". Three call patterns:
  (1) no args → infer targets from current chat context;
  (2) explicit list `issue#N pr#M` (case-insensitive `issue#`/`pr#` prefix);
  (3) `--type [issue|PR] --date <YYYY-MM-DD>` for date-bounded bulk
  enumeration via `gh {issue,pr} list --search`. Idempotent — skips cards
  that already carry an `<!-- ai-metrics -->` block. With `--force`,
  re-computes metrics fresh and replaces the existing block in place
  (recompute, not blind overwrite). Never modifies issue/PR body content
  other than the footer. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:add-ai-metrics — Retrofit ai-metrics footer onto past Issues/PRs

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for the final summary line.

Parse args per the table in `references/help.md` — positional `issue#N` /
`pr#M` (case-insensitive), flags `--type`, `--date`, `--force`, `--remote`.
`--date` accepts either `YYYY-MM-DD` (10 chars, used as-is) or `YY-MM-DD`
(8 chars, expanded to `20YY-MM-DD`); other lengths → format error and stop.
Resolve `TARGET_REPO` via the shared flow in
`gh-issue-create/references/repo-resolution.md`. Missing remote → list
`git remote -v` and stop (no silent fallback). `--date` + positional
cards is a hard error: print
`Error: --date and positional cards are mutually exclusive.` and stop.

## Step 2: Determine Mode + Build Target List

First match wins:

1. `--date` present → **date-filter mode**.
   Run `gh issue list` and/or `gh pr list` (filtered by `--type` if given)
   with `--search "created:<DATE>" --state all --limit 200 --json number,title`.
2. Positional cards present → **explicit-list mode**. Parse, validate
   each `N` as a positive integer, dedupe, preserve order.
3. Otherwise → **conversation-infer mode**. Scan recent chat turns for
   `#NNN` mentions paired with `issue` / `PR` / `pr` cues — bare numbers
   without `#` are ignored to avoid false positives. No candidates →
   print `Error: no issue/PR references in conversation; pass them explicitly.`
   and stop.

If `|targets| > 100`, print the count and prompt
`Continue with N cards? [y/N]:`. Default no → stop.

## Step 3: Per-Card Loop

For each `(type, N)` follow `references/footer-detection.md`:

1. `gh {issue,pr} view N --repo "$TARGET_REPO" --json title,body` → fetch.
2. Detect `<!-- ai-metrics -->` (also matches `<!-- ai-metrics:<skill> -->`).
3. Branch:
   - **No footer** → compute metrics → append (after a `---` separator).
   - **Footer + no `--force`** → print `→ skipped #N <title>` and continue.
     Do NOT call `gh edit` (saves API quota).
   - **Footer + `--force`** → recompute fresh metrics → in-place replace
     (single regex pass, no append).
4. On modification only, write the new body to `mktemp` and call
   `gh {issue,pr} edit N --repo "$TARGET_REPO" --body-file <tmp>`.
5. Print the one-line status string per the "Per-card status output
   format" section in `references/footer-detection.md`. Continue on
   failure — never abort the loop.

Metric values follow `references/post-hoc-metrics.md` (TOKENS / HUMAN_H /
ELAPSED formulas, SSOT lookup table, post-hoc estimation rules).

## Step 4: Final Report

After the loop, print the summary line + context-only ai-metrics line per
the "Final report output format" section in `references/footer-detection.md`.
Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))` just before printing.

## Constraints

- Always pass `--repo "$TARGET_REPO"` — no implicit repo detection.
- Body byte-identical outside the footer: stripping the new footer must
  yield the original body verbatim. No rewrap, no language change.
- `--force` is **recompute → replace**, never blind overwrite or
  duplicate-append. If no footer exists, `--force` degrades to plain append.
- Continue-on-error: a single card failure never stops the loop.
- Skip path is API-silent — no `gh edit` call, no body diff.
- Conversation-infer mode rejects bare numbers (`123` without `#`).
- > 100 hits require explicit `y` confirmation; no `--yes` flag.
