# Decomposition Rules — PRD → per-component TRDs

Heuristic the skill applies to every PRD to produce 6–8 per-component
TRD slugs plus a responsibility map. Goal: per-component split
matching the agent-toolbox convention (mega-TRD forbidden).

## Extraction order

1. **PRD §3 `D-#` (Decisions)** — treat as cross-cutting constraints.
   Each `D-#` may be cited on multiple TRDs as a premise but is not
   *owned* by any single TRD.
2. **PRD §4 `F-#` (Functional)** — primary signal for component
   grouping. Group `F-#` items by code-module boundary (Auth / Data
   Model / Pipeline / UI / Security / Deployment / Observability /
   ...). Each group becomes one TRD slug.
3. **PRD §5 `NF-#` (Non-functional)** — assign each `NF-#` to its
   highest-impact TRD as the primary. Cross-citation on adjacent TRDs
   is allowed; redefinition is not (NF-# is PRD-owned).
4. **Adjacent-TRD pairs** — slugs that share an explicit contract
   (data schema, API surface, event topic) get a bidirectional
   `인접 TRD` entry in their frontmatter.

## Target counts

- **Component count** — 6 to 8 slugs per PRD. Lower bound 2 (PRDs
  yielding < 2 viable groups are refused with a `[WARN] PRD too
  small` verdict).
- **Items per TRD** — 1 to 7 PRD items (`F-#` + `D-#` + `NF-#`
  cross-cites). A TRD carrying ≥ 8 items is flagged as a
  split-candidate in the plan's `## Suggested splits` section but
  not auto-split (the user decides).

## Slug naming

- kebab-case, 1–3 domain words: `auth-session`, `submission-pipeline`,
  `item-model`, `observability-tracing`.
- No version suffixes (`-v1`, `-2025q2`). The TRD frontmatter carries
  the version.
- No PRD-section numbers in the slug (`f4-auth` is wrong —
  agent-toolbox slugs are component-named, not numerically
  cross-referenced).

## Mapping table (lives in the plan)

```
| Slug | 책임 F-# | 책임 D-# | NF-# (primary) | NF-# (cited) | 인접 TRD |
|------|----------|----------|----------------|--------------|----------|
| auth-session | F-1, F-2 | D-3 | NF-1 | NF-2, NF-4 | submission-pipeline |
```

This table is the round-trip surface — `--apply` reads it back from
the plan to fill each TRD's frontmatter.

## Failure cases

- **PRD too small** (< 2 viable groups) → `[WARN] PRD too small —
  single mega-TRD refused.` Stop with no plan written.
- **`F-#` items not enumerable** (no F-#/section-header structure)
  → propose section-heading-based groups, but emit
  `[WARN] PRD lacks F-#/D-#/NF-# enumeration — slugs are
  heading-derived` in the plan header.
- **Slug collision** (heuristic proposes the same kebab-case twice)
  → suffix `-a` / `-b` and surface in the plan's `## Manual review`
  section.

## Hard rules

- **Never invent PRD items.** If `F-#`/`D-#`/`NF-#` are not present
  in the source PRD, do not synthesize them.
- **Never merge unrelated `F-#` into a single TRD** just to hit the
  6-slug lower bound. If the PRD is too small, refuse and tell the
  user to enrich the PRD.
- **PRD is read-only.** This skill never writes back to the PRD path.

## Pairs with

- `references/plan-format.md` — exact skeleton for the plan + scaffold.
- `references/template-fallback.md` — TRD scaffold contents when
  `<prd-dir>/trd/_template.md` is missing.
