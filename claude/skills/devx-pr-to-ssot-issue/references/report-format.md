# Report Format — Step 6 output

Step 6 of `SKILL.md` prints exactly one of the templates below. Pick by
exit path:

| Exit path | Template |
|-----------|----------|
| Success (issue created) | `[OK] devx:pr-to-ssot-issue ...` (below) |
| `--dry-run` success | `[DRY-RUN] devx:pr-to-ssot-issue ...` (below) |
| `--reason` missing / short (exit 2) | `[FAIL] devx:pr-to-ssot-issue reason=missing-or-short ...` |
| Overlap guard (exit 3) | `[FAIL] devx:pr-to-ssot-issue reason=overlap-detected linked=#<M>` |
| Empty gap (exit 4) | `[FAIL] devx:pr-to-ssot-issue reason=empty-gap` |
| Other (`gh` error, missing label, missing remote) | `[FAIL] devx:pr-to-ssot-issue reason=<short>` |

## Success template

```
[OK] devx:pr-to-ssot-issue pr=#<PR#> issue=#<new> elapsed=~<ELAPSED> min
  Title: <rendered title>
  Buckets: code=<n> schema=<n> infra=<n> docs=<n>
  Gaps: A=<y/n> B=<y/n> C=<y/n> D=<y/n> E=<y/n>
  Audit reason: "<first 80 chars>..."
  URL: <issue URL>

Next: /gh-issue-flow <new>
```

- `Buckets:` mirrors the Step 2 bucket table (file counts per bucket).
- `Gaps:` is a 5-letter `y/n` matrix from the subagent report. `y`
  means the block had content; `n` means `(none)`.
- The `Next:` line is **omitted** when `--no-next-hint` is passed. The
  rest of the block is unchanged.

## `--dry-run` template

```
[DRY-RUN] devx:pr-to-ssot-issue pr=#<PR#> draft=<path> elapsed=~<ELAPSED> min
  Title: <rendered title>
  Buckets: code=<n> schema=<n> infra=<n> docs=<n>
  Gaps: A=<y/n> B=<y/n> C=<y/n> D=<y/n> E=<y/n>
  Audit reason: "<first 80 chars>..."

Re-run without --dry-run to register on GitHub.
```

No `Next:` line — the issue doesn't exist yet, so `/gh-issue-flow <N>`
would be wrong to suggest.

## Failure templates

Match the verdict shape used by sister skills (`devx:trd-to-issues`,
`gh:issue-create`):

```
[FAIL] devx:pr-to-ssot-issue reason=<short> pr=#<PR#> elapsed=~<ELAPSED> min
  Detail: <one-line concrete cause>
  <optional fix hint>
```

Examples:

```
[FAIL] devx:pr-to-ssot-issue reason=missing-or-short pr=#727
  Detail: --reason is mandatory and must be >=10 chars after trim.
  Fix: re-run with --reason "<exception 사유>".
```

```
[FAIL] devx:pr-to-ssot-issue reason=overlap-detected pr=#727 linked=#500
  Detail: PR #727 already references SSOT issue #500 (PRD section present).
  Fix: re-run with --force-overlap to register a parallel SSOT issue,
  or amend / extend #500 manually.
```

```
[FAIL] devx:pr-to-ssot-issue reason=empty-gap pr=#727
  Detail: subagent returned (none) for every SSOT section (A–E).
  Fix: PR scope too small for SSOT tracking — recommend a normal review.
```

```
[FAIL] devx:pr-to-ssot-issue reason=missing-label pr=#727
  Detail: label "<name>" not present on TARGET_REPO.
  Fix: create the label manually (`gh label create ...`), then re-run.
```

## Why this shape

- `[OK]` / `[FAIL]` / `[DRY-RUN]` first token — greppable by
  `gh-issue-flow` and CI dashboards.
- `reason=<short>` (failures) is a stable enum, not free prose — keeps
  CI alerting simple.
- `Buckets:` + `Gaps:` always visible — the human reviewer can confirm
  the SSOT scope at a glance without opening the issue.
- `Next:` last — `gh-issue-flow` strips this line when composing.

## Pairs with

- `SKILL.md` Step 6 — invocation site.
- `references/help.md` — `--no-next-hint` flag definition.
- `references/issue-body-template.md` — the underlying body whose
  bucket counts and gap matrix feed the report.
