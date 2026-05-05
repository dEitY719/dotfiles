# gh:add-ai-metrics — Help

## Arguments

| # | Form | Default | Description |
|---|------|---------|-------------|
| positional | `issue#N` / `pr#M` | — | Cards to retrofit (case-insensitive prefix). Multiple allowed. |
| flag | `--type {issue\|PR}` | both | Limits date-filter mode to a single artifact kind. |
| flag | `--date <YYYY-MM-DD>` | — | Date-filter mode trigger. 10-char input used as-is; 8-char `YY-MM-DD` expanded to `20YY-MM-DD`; other lengths rejected. |
| flag | `--force` | off | Recompute metrics and replace an existing footer (default skips). |
| flag | `--remote <name>` | `origin` | Override the target remote. |
| flag | `-h` / `--help` / `help` | — | Print this help and stop. |

## Modes (mutually exclusive — first match wins)

1. **conversation-infer** (no args)
   Scans recent chat turns for `#NNN` paired with `issue` / `PR` / `pr`
   cues. Bare numbers without `#` are ignored (false-positive guard).
   No candidates → hard error.

2. **explicit-list** (positional cards)
   Parse `issue#N pr#M ...`. Order preserved, dupes deduplicated.

3. **date-filter** (`--date`, optional `--type`)
   Enumerates via
   `gh {issue,pr} list --search "created:<DATE>" --state all --limit 200`.
   `> 100` hits → confirmation prompt (`y/N`, default no).

`--date` and positional cards together → hard error (mutex).

## Examples

- `/gh:add-ai-metrics`
  → infers from chat (e.g. #317 + #320 just discussed in this turn).
- `/gh:add-ai-metrics issue#317 pr#320`
  → tags exactly those two.
- `/gh:add-ai-metrics --type issue --date 2026-04-30`
  → tags every issue created on 2026-04-30 in `origin`'s repo.
- `/gh:add-ai-metrics --type PR --date 26-04-30 --remote upstream`
  → date expansion (`26-04-30` → `2026-04-30`) + remote override.
- `/gh:add-ai-metrics issue#100 --force`
  → recomputes metrics for #100 even if it already has a footer.

## Behavior

- **Idempotent by default** — cards already carrying `<!-- ai-metrics -->`
  (or `<!-- ai-metrics:* -->`) skip without an `gh edit` API call.
- **`--force` recomputes** — does NOT just overwrite the literal block;
  re-fetches body, recomputes fresh `TOKENS` / `HUMAN_H` / `ELAPSED`,
  then replaces the existing block in place (no duplicate append).
- **Continue-on-error** — one card failing never blocks the rest. Final
  summary lists `added / replaced / skipped / failed` counts.
- **Body-preserving** — appends after a `---` separator on first run;
  in `--force` replace, regex matches the block markers exactly, leaving
  surrounding bytes untouched.
- **API quota friendly** — skip path performs zero `gh edit` calls.

## Footer format (matches PR #320 / `gh-issue-create`)

```
---
<!-- ai-metrics -->
📊 ~{TOKENS} tokens · 👤 ~{HUMAN_H} h · 🤖 ~{ELAPSED} min
<!-- /ai-metrics -->
```

The detection regex tolerates the optional `:<skill>` suffix
(`<!-- ai-metrics:gh-issue-create -->` etc.) for forward-compat with
`metrics-helper.md`'s newer scheme.

## Post-hoc metric estimation

When backfilling, the original Claude session is gone, so values are
estimated. Detail in `post-hoc-metrics.md`; summary:

| Metric | Estimation rule |
|--------|-----------------|
| `TOKENS` | `(title + body chars) ÷ 4`, rounded to nearest 500, min 1000 |
| `HUMAN_H` | conventional-commit prefix in title → `gh-issue-create/references/metrics-baseline.md`; fallback `misc` (2 h) |
| `ELAPSED` | `max(1, HUMAN_H × 0.05)` — assumes AI took ~5% of the human estimate |

These values are deterministic given the same body, so re-running the
skill with `--force` produces stable output (no flapping).

## What this skill will NOT do

- Re-run the original AI conversation to recover real token counts.
- Modify card body outside the footer block.
- Auto-create labels, assignees, or milestones.
- Silently fall back to `origin` when `--remote <name>` is missing.
- Process more than 100 cards without explicit `y` confirmation.
- Mutate cards on the skip path (no body diff, no API call).
