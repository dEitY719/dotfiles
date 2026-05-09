# Samples — TRD fixture + expected plan

Fixture used to verify `devx:trd-to-issues` behavior end-to-end without
mutating GitHub.

## Files

- `trd-fixture.md` — small TRD with 3 Tasks across 2 Milestones,
  written to exercise:
  - TRD-named milestones (skill must NOT propose names),
  - dependency lifting (`Depends on T1, T2`),
  - priority labels lifted from the TRD (`⚡ High`),
  - both label heuristics (`pro-friendly` for M0a tasks, `max-only`
    for the multi-AC M0b task).
- `expected-plan.md` — the reference Markdown the skill should emit
  when run as:

  ```
  /devx:trd-to-issues claude/skills/devx-trd-to-issues/references/samples/trd-fixture.md \
      --plan-out /tmp/plan.md
  ```

  with `Target repo: dEitY719/dotfiles`. The `Generated:` timestamp
  obviously varies — diffs should ignore that line.

## Manual verification

```bash
diff <(grep -v '^Generated:' /tmp/plan.md) \
     <(grep -v '^Generated:' \
       claude/skills/devx-trd-to-issues/references/samples/expected-plan.md)
```

Expect zero diff. Anything else means the decomposition rules,
labeling heuristics, or plan format drifted — update **all three**
(`decomposition-rules.md`, `plan-format.md`, `expected-plan.md`)
before relying on the skill again.
