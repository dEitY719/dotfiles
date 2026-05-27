# devx:prd-to-trd — Help

## Usage

```
/devx:prd-to-trd <prd-path> [flags]
/devx-prd-to-trd docs/requirement/product-requirements.md
/devx-prd-to-trd docs/prd.md --apply
/devx:prd-to-trd -h            # show this help
/devx:prd-to-trd --help        # show this help
/devx:prd-to-trd help          # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `<prd-path>` | yes | Path to the PRD Markdown file. v1 supports a single PRD only. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | **on** | Default. Writes the plan; **never** writes TRD scaffolds. |
| `--apply` | off | Reads the plan and writes per-component TRD scaffolds to `<prd-dir>/trd/<slug>.md`. |
| `--plan-out <path>` | `.claude/.prd-to-trd.plan.md` | Where the plan Markdown lands. |
| `--force` | off | Overwrite an existing TRD scaffold on `--apply` (otherwise skipped + logged). |

## Examples

```
# 1. Inspect proposed decomposition (no file writes):
/devx-prd-to-trd docs/requirement/product-requirements.md

# 2. Custom plan path:
/devx-prd-to-trd docs/prd.md --plan-out /tmp/prd-plan.md

# 3. Apply (writes <prd-dir>/trd/<slug>.md per component):
/devx-prd-to-trd docs/prd.md --apply

# 4. Force-overwrite existing scaffolds:
/devx-prd-to-trd docs/prd.md --apply --force
```

## What the skill does

1. Reads the PRD and proposes 6–8 per-component slugs + a
   responsibility map of each PRD `F-#` / `D-#` / `NF-#` item.
2. Locates the TRD template — `<prd-dir>/trd/_template.md` first,
   else the built-in `references/template-fallback.md`.
3. Writes a Markdown plan to `--plan-out` matching
   `references/plan-format.md`. The plan is the **single review
   surface** before `--apply`.
4. **`--apply` only** — re-reads the plan (round-trip) and writes the
   8-section TRD scaffold per slug under `<prd-dir>/trd/<slug>.md`.
   Existing files are skipped unless `--force` is set.

## What the skill will NOT do

- Auto-draft the full TRD body — scaffolds carry an 8-section header
  + guidance blockquotes only. The 500-800 line body is human work
  (agent-toolbox "AI 범위 폭주 차단" convention).
- Modify the PRD — input only. PRD gaps are reported, not patched.
- Create GitHub Issues / Milestones — that is [[devx-trd-to-issues]].
- Generate a single mega-TRD — agent-toolbox `_template.md` forbids
  it. PRDs too small to split into ≥ 2 components are refused.
- Write outside `<prd-dir>/trd/` — output is path-scoped to the PRD's
  directory tree.
- Roll back partial writes on a mid-flow `--apply` failure — reports
  partial state and stops; the user owns cleanup.

## Prerequisites

- A PRD Markdown file with discoverable `F-#` / `D-#` / `NF-#` items
  (or section headers the heuristic can parse — see
  `references/decomposition-rules.md`).
- Write access to `<prd-dir>/trd/` for `--apply`.

## Pairs with

- [[devx-trd-to-issues]] — the **next** step. Takes the TRDs this
  skill scaffolds (after a human fills them in) and decomposes them
  into GitHub Milestones + Issues.
- `gh:issue-create` — single-issue alternative when batch
  decomposition is overkill.
