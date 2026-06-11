# gh-pr-resolve-ci-fail: Constraints

Never:

- `--force` / `--force-with-lease` — fast-forward push only.
- Run on the default branch.
- Push when local lint/test is red (CI infinite-loop guard).
- Remove the `CI fail` label before push succeeds.
- Auto-create missing labels — absent label → soft-fail.
- Auto-stash — working tree must be clean before the skill runs.
- Delegate to `gh:commit` inside composition — inline the commit instead
  (avoids re-prompt inside a composed skill run).
