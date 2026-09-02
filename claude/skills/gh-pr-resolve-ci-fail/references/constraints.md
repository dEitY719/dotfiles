# gh-pr-resolve-ci-fail: Constraints

Never:

- `--force` / `--force-with-lease` — fast-forward push only.
- Run on the default branch.
- Push when local lint/test is red (CI infinite-loop guard).
- Remove the `CI fail` label before push succeeds.
- Remove `review-blocked`, or independently *decide* to add either verdict
  label — `devx:pr-review-all` owns issuance (#1563). Dropping `review-passed`
  after a successful push is mandatory and unconditional (#1705): a CI fix
  changes content by definition, so the patch-id "keep" path that
  `gh:pr-resolve-outdated` / `gh:pr-resolve-conflict` have never applies here,
  and a stale verdict on an unreviewed head is the bug this prevents.
- Auto-create missing labels — absent label → soft-fail.
- Auto-stash — working tree must be clean before the skill runs.
- Delegate to `gh:commit` inside composition — inline the commit instead
  (avoids re-prompt inside a composed skill run).
