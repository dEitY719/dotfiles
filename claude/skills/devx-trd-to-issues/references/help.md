# devx:trd-to-issues — Help

## Usage

```
/devx:trd-to-issues <trd-path>... [flags]
/devx-trd-to-issues docs/architecture/interface-ui.md
/devx-trd-to-issues docs/trd-foo.md docs/trd-bar.md --prd docs/prd.md --apply
/devx:trd-to-issues -h          # show this help
/devx:trd-to-issues --help      # show this help
/devx:trd-to-issues help        # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1+ | `<trd-path>` | yes | One or more TRD Markdown paths. Multiple TRDs are unioned. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--prd <path>` | none | Companion PRD path. Multi-allowed. Used as cross-reference context for decomposition. |
| `--remote <name>` | `origin` | Git remote whose repo will receive the milestones+issues on `--apply`. Missing remote → stop with `git remote -v` listing. |
| `--dry-run` | **on** | Default. Writes the plan; **never** mutates GitHub. |
| `--apply` | off | Mutate GitHub: bulk-create milestones + issues, resolve `#new-N` citations, promote first-milestone issues to Ready (unless `--no-ready`). |
| `--plan-out <path>` | `.claude/.trd-to-issues.plan.md` | Where the plan Markdown lands. |
| `--no-ready` | off | Skip Project board "Ready" promotion of first-milestone issues during `--apply`. Useful when the board is missing or the user wants manual triage. |

## Examples

```
# 1. Inspect what would happen (no GitHub mutation):
/devx-trd-to-issues docs/architecture/interface-ui.md

# 2. Multiple TRDs + PRD context, custom plan path:
/devx-trd-to-issues docs/trd-a.md docs/trd-b.md \
    --prd docs/product-requirements.md \
    --plan-out /tmp/trd-plan.md

# 3. Apply (real GitHub mutation), no Ready promotion:
/devx-trd-to-issues docs/trd-a.md --apply --no-ready

# 4. Apply on a different remote than origin:
/devx-trd-to-issues docs/trd-a.md --apply --remote upstream
```

## What the skill does

1. Reads each TRD (and optional PRD) and decomposes them into a
   three-level **Epic → Feature → Task** plan.
2. Groups Tasks under Milestones — TRD-named structure first, otherwise
   the skill proposes names and asks the user to confirm.
3. Validates each Task against the decomposition rules in
   `references/decomposition-rules.md`. Items that fail are split or
   reported in the plan's "decomposition failures" section.
4. Applies the `pro-friendly` / `max-only` heuristic plus any priority
   labels carried in the TRD.
5. Writes a Markdown plan to `--plan-out` matching
   `references/plan-format.md`. The plan is the **single review
   surface** before `--apply`.
6. **`--apply` only** — pre-validates labels (no auto-create), bulk-
   creates milestones, creates issues, resolves `#new-N` virtual
   citations to real numbers, and promotes first-milestone issues to
   Ready unless `--no-ready` is set.

## What the skill will NOT do

- Auto-create missing labels on `--apply` — pre-validates via `gh label
  list` and stops with the missing list. Reason:
  `feedback_gh_label_no_autocreate.md`.
- Silently fall back to `origin` when `--remote <name>` is missing.
- Auto-author TRD or PRD content — input only.
- Auto-create Project board columns — uses the existing board.
- Roll back partial mutations on a mid-flow `--apply` failure — reports
  partial state and stops; the user owns cleanup.
- Run on `--apply` without explicit `--apply` — `--dry-run` is the
  default.

## Prerequisites

- A `gh` CLI authenticated against the target remote's host.
- The target repo already has the labels referenced by the plan
  (run a dry-run first, then create any missing labels manually).
- For `--apply` Ready promotion: a Project board attached to the repo
  with a `Status` field that includes a `Ready` option, or pass
  `--no-ready`.

## Pairs with

- `requirement-spec` / `requirement-draft` — author the TRD/PRD before
  invoking this skill.
- `gh:issue-implement` / `gh:issue-flow` — pick up Task issues this
  skill registered and implement them.
- `gh:issue-create` — single-issue alternative when batch decomposition
  is overkill.
