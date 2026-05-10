# Operational Constraints — devx:trd-to-issues

These rules are mandatory and apply to every invocation. They protect the
GitHub target repository from silent mutations and keep the decomposition
plan as the single review surface for the human user.

## Mutation safety

- Default is `--dry-run`. `--apply` must be explicit — never assume it.
- Never auto-create labels. Pre-validate with `gh label list` and stop on
  the first missing label (memory:
  `feedback_gh_label_no_autocreate.md`).
- Never silently fall back when `--remote <name>` is missing. Print the
  remote list and stop.

## Plan integrity

- Never collapse the plan. The plan written to `--plan-out` is the SSOT
  that the user reviews before `--apply` mutates GitHub.
- Decomposition criteria (see `references/decomposition-rules.md`) are
  mandatory. Tasks that fail the criteria go into a
  "decomposition failures" section in the plan — never silently dropped
  and never silently merged into other tasks.

## Mid-flow failure

- On failure during `--apply`, report the partial state (created
  milestones / issues so far) and stop.
- No automatic rollback. The user decides whether to delete the partial
  artifacts or re-run with the patched plan.
