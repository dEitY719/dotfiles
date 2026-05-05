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
`pr#M` (case-insensitive), flags `--type`, `--date`, `--force`, `--remote`,
plus the pacing flags `--pace`, `--limit`, `--budget`, `--dry-run`.

`--date` accepts four shapes — single day, whole month, or half-open range —
parsed by `parse_date_arg` in `references/date-parsing.md`:

| Length / shape          | Form                | Meaning                          |
|-------------------------|---------------------|----------------------------------|
| 5 chars `YY-MM`         | month               | whole month, 1st through last day |
| 7 chars `YYYY-MM`       | month               | same                             |
| 8 chars `YY-MM-DD`      | single              | one day (existing)               |
| 10 chars `YYYY-MM-DD`   | single              | one day (existing)               |
| contains `..` or `~`    | range `[start, end)` | end-day excluded; `~` normalized to `..` |

Other inputs → format error and stop.

`--pace`, `--budget` accept duration strings (`30s` / `5m` / `1h` / `1h30m`)
parsed by `parse_duration` in `references/pace-control.md`. `--limit` takes
a positive integer. `--dry-run` is a boolean flag.

Resolve `TARGET_REPO` via the shared flow in
`gh-issue-create/references/repo-resolution.md`. Missing remote → list
`git remote -v` and stop (no silent fallback). `--date` + positional
cards is a hard error: print
`Error: --date and positional cards are mutually exclusive.` and stop.

## Step 2: Determine Mode + Build Target List

First match wins:

1. `--date` present → **date-filter mode**.
   Feed the value through `parse_date_arg` → three-token output
   (`single|month|range <a> [<b>]`) → `build_search_clause` → the
   `created:...` fragment for the GitHub query. Then run `gh issue list`
   and/or `gh pr list` (filtered by `--type` if given) with
   `--search "<clause>" --state all --limit 200 --json number,title`.
   The `--limit 200` cap stays — for month/range queries that would exceed
   it the user must narrow the date or split into sub-ranges.
2. Positional cards present → **explicit-list mode**. Parse, validate
   each `N` as a positive integer, dedupe, preserve order.
3. Otherwise → **conversation-infer mode**. Scan recent chat turns for
   `#NNN` mentions paired with `issue` / `PR` / `pr` cues — bare numbers
   without `#` are ignored to avoid false positives. No candidates →
   print `Error: no issue/PR references in conversation; pass them explicitly.`
   and stop.

If `|targets| > 100`, print the count and prompt
`Continue with N cards? [y/N]:`. Default no → stop. `--limit <N>` does
**not** suppress this prompt — the prompt protects against accidentally
huge target lists (e.g. a typo'd month range), independent of how many
the loop will actually modify.

## Step 3: Per-Card Loop

If `--dry-run` was passed, take the dry-run branch in
`references/pace-control.md` → "`--dry-run` branch" — same per-card view
fetch, but emits `· will-write` / `· will-skip` / `· will-force-replace`
classification rows and the dry-run summary line, **never calling
`gh edit`**. Then stop.

Otherwise, for each `(type, N)` follow `references/footer-detection.md`:

1. **Stop check (top of iteration)** — before fetching this card.
   Compute `elapsed_secs=$(( $(date +%s) - START_TS ))` here (seconds,
   matching `check_budget`'s contract — Step 4's `ELAPSED` is a separate
   minutes-rounded display value, do not reuse it):
   - `check_budget "$elapsed_secs" "$BUDGET_SECS"` true → break with
     `stop_reason="--budget"`. (Skipped when `--budget` not set.)
   - `--limit` set and `modified_count >= LIMIT` → break with
     `stop_reason="--limit"`.
   See `references/pace-control.md` → "Stop-reason composition".
2. `gh {issue,pr} view N --repo "$TARGET_REPO" --json title,body` → fetch.
3. Detect `<!-- ai-metrics -->` (also matches `<!-- ai-metrics:<skill> -->`).
4. Branch:
   - **No footer** → compute metrics → append (after a `---` separator).
   - **Footer + no `--force`** → print `→ skipped #N <title>` and continue
     **without sleeping**. Do NOT call `gh edit` (saves API quota).
   - **Footer + `--force`** → recompute fresh metrics → in-place replace
     (single regex pass, no append).
5. On modification only: write the new body to `mktemp`, call
   `gh {issue,pr} edit N --repo "$TARGET_REPO" --body-file <tmp>`,
   increment `modified_count`, then `sleep_pace "$PACE_SECS"` (no-op when
   `--pace` not set, skipped on the last card so no trailing wait).
6. Print the one-line status string per the "Per-card status output
   format" section in `references/footer-detection.md`. Continue on
   failure — never abort the loop.

Metric values follow `references/post-hoc-metrics.md` (TOKENS / HUMAN_H /
ELAPSED formulas, SSOT lookup table, post-hoc estimation rules).

## Step 4: Final Report

After the loop, print the summary line + context-only ai-metrics line per
the "Final report output format" section in `references/footer-detection.md`.
Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))` just before printing.

When the loop exited early via `--limit` or `--budget`, append a third line
naming the trigger and the count remaining in the original target list:

```
Stopped early: <stop_reason>; <X> cards remaining. Re-run the same command to resume (skip-existing makes this idempotent).
```

For `--dry-run`, the final report is the dry-run summary block from
`references/pace-control.md` instead — no per-card metrics line, no
edit-counters.

## Constraints

- Always pass `--repo "$TARGET_REPO"` — no implicit repo detection.
- Body byte-identical outside the footer: stripping the new footer must
  yield the original body verbatim. No rewrap, no language change.
- `--force` is **recompute → replace**, never blind overwrite or
  duplicate-append. If no footer exists, `--force` degrades to plain append.
- Continue-on-error: a single card failure never stops the loop.
- Skip path is API-silent — no `gh edit` call, no body diff, **no sleep**.
- Conversation-infer mode rejects bare numbers (`123` without `#`).
- > 100 hits require explicit `y` confirmation; no `--yes` flag.
- `--pace` sleeps **after** each successful modify, **never before**, and
  **never after the last card** — no trailing wait.
- `--dry-run` makes zero `gh edit` calls. `gh view` is still allowed
  (needed to classify will-write vs will-skip vs will-force-replace).
- `--limit` counts only cards that took the modify path (skipped cards
  do not advance the counter — this makes "process N new backfills"
  deterministic across re-runs).
- `--limit` and `--budget` compose with **OR semantics** — whichever
  fires first stops the loop. Stop reason is reported in the summary.
