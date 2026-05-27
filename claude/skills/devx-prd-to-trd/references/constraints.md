# Operational Constraints — devx:prd-to-trd

These rules are mandatory and apply to every invocation. They protect
the PRD source from silent edits, keep the plan as the single review
surface, and enforce the "AI 범위 폭주 차단" convention from
agent-toolbox.

## Mutation safety

- **Default is `--dry-run`.** `--apply` must be explicit — never
  assume it.
- **Never modify the PRD.** This skill is input-only on the PRD path.
  Reported PRD gaps go in the plan's `## Manual review` section; the
  user edits the PRD.
- **Never write outside `<prd-dir>/trd/`.** Output is scoped to the
  PRD's directory tree. `mkdir -p` may create `<prd-dir>/trd/` but
  never anything above it.
- **Skip-on-exists is the default** — existing TRD scaffolds are
  protected from accidental overwrite. `--force` is the only way to
  replace them, and it overwrites with no merge attempt.

## Content safety (anti-hallucination)

- **Never AI-draft the TRD body.** `--apply` writes the 8-section
  scaffold with blockquoted guidance prompts only. The 500–800 line
  technical body is human work.
- **Never invent PRD items.** If the source PRD lacks `F-#` / `D-#`
  / `NF-#` enumeration, the plan header carries a warning and the
  mapping table is heading-derived — not synthesized.
- **Never collapse to a mega-TRD.** PRDs too small to split into ≥ 2
  components are refused. Single-TRD output violates the agent-
  toolbox convention.

## Plan integrity

- **Plan is the SSOT.** The user's edits to slugs / mappings on the
  plan are absolute trust — `--apply` reads the plan, not the PRD.
  (Open Question OQ-1 in the source issue resolved to "plan = SSOT".)
- **Plan must round-trip.** A plan written by this skill must be
  re-parseable by `--apply` without re-reading the PRD. See
  `references/plan-format.md` for the round-trip invariants.

## Mid-flow failure

- On `--apply` write failure, report the partial state (slugs
  written, slugs skipped, slug that failed) and stop. **No automatic
  rollback** — written scaffolds remain on disk; the user decides
  whether to delete or keep.
- Template load failure with both `<prd-dir>/trd/_template.md` and
  `references/template-fallback.md` missing is unrecoverable — exit
  with `[FAIL] template unavailable`.

## v1 scope limits

- **Single PRD per invocation.** Multi-PRD batching is out of scope
  (Open Question OQ-4). Multi-PRD input → stop with `[FAIL] multi-PRD
  input not supported in v1`.
- **`--components <slug1>,<slug2>,...` override is NOT in v1.** The
  user edits the plan instead. (Open Question OQ-3.)
- **Directory-style TRD layouts** (`<prd-dir>/feature/<slug>/trd.md`)
  are NOT in v1 — output path is fixed as `<prd-dir>/trd/<slug>.md`.
  (Open Question OQ-2.)
