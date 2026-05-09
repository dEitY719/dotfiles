# Plan Markdown Format

Canonical skeleton for the file `devx:trd-to-issues` writes to
`--plan-out` (default `.claude/.trd-to-issues.plan.md`). The plan is
the single review surface between dry-run and apply — it must
round-trip back into Step 4 (`--apply`) without re-reading the TRD.

## Top-level structure

```markdown
# TRD-to-Issues Plan
Generated: <ISO 8601 local time>
Source TRD: <comma-separated paths>
Source PRD: <comma-separated paths or "(none)">
Target repo: <owner/repo>
Mode: dry-run

## Milestone: <M0a-name> — <one-line summary>
Description: <2-3 line milestone description>

- [ ] #new-1 <conventional-commit title>
  - Labels: <pro-friendly|max-only>, <priority-label?>
  - Depends on: <#new-K, #new-L> | (none)
  - AC:
    - [ ] <criterion 1>
    - [ ] <criterion 2>

- [ ] #new-2 ...

## Milestone: <M0b-name> — ...

## Decomposition failures
<empty list, OR>
- <task title> — <reason: AC count > 3 / not unit-testable / not independent>
```

## Field rules

- **`#new-N`** — virtual citation. `--apply` rewrites these to the real
  GitHub issue numbers returned by `gh issue create` and patches the
  `Depends on:` lines via `gh issue edit --body-file`.
- **Labels** — exactly one of `pro-friendly` / `max-only`, plus
  optional priority labels lifted from the TRD. Any label referenced
  here that is missing on the target repo is caught during `--apply`'s
  pre-validation (no auto-create).
- **AC** — 1 to 3 checkboxes. Items requiring more get split or land
  in "Decomposition failures".
- **Depends on** — references must be `#new-N` (this skill's virtual
  numbers). Cross-plan cites against pre-existing issues use the real
  `#<number>` and pass through unchanged on `--apply`.

## Round-trip invariant

A plan written by this skill must be re-parseable by this skill, so:

- Heading levels and ordering are stable (one `## Milestone:` per
  milestone, tasks as `- [ ] #new-N <title>` first-line).
- Labels list is comma-separated, single line.
- AC always nested under a `- AC:` bullet (two-space indent), exactly.
- Decomposition failures live under one bottom-level `## Decomposition
  failures` heading; an empty list is rendered as a single line `_no
  failures._` to keep the section discoverable.

If a future variant changes the skeleton, update both this file and
`samples/expected-plan.md` in lock-step — the round-trip parser is
verified against the sample.
