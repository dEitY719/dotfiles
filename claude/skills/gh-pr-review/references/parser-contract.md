# Parser Contract — for gh:pr-review

Step 1 delegates to `gh_pr_review_parse` in
`shell-common/functions/gh_pr_review.sh` (issue #664). That function is
the **single source of truth** for the argument surface — the flat
state machine, the closed `--review` enum, the KR-alias normalization,
the `--user` cross-AI rejection, and the exit-code mapping (0 / 1 / 2)
all live there. The bats fixture
`tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh` is now a thin
wrapper around the same function, so any drift between this contract
and the production parser is caught by
`tests/bats/skills/gh_pr_review_arg_parse.bats`.

## Argument shape

Contract this skill depends on (do not duplicate the parser here; read
`shell-common/functions/gh_pr_review.sh` for the authoritative shape):

- `--ai <codex|agy|claude>` — required.
- `--review <preset>` — closed enum; KR aliases normalize before
  dispatch.
- `--user <name>` — `--ai claude` only.
- `--no-post-comment` — skips Step 6.
- Positional `<pr-number>` (optional; auto-detect from current branch)
  and `<remote>` (default `origin`).

## KR aliases

The `--review` value is a closed enum normalized to one of `default`,
`quick`, `thorough`, `security`, `performance`. Korean aliases are
mapped to those canonical enum values inside `gh_pr_review_parse`
before dispatch — by the time Step 3 reads the preset, normalization
has already happened. Free-text values are rejected (see exit codes).

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Parse succeeded. |
| 1 | Resolution failure (e.g. unknown claude account, target/PR resolution failed). |
| 2 | Argument-surface error (missing/unknown `--ai`, `--user` with codex/agy, free-text `--review` typo). |

## Post-parse setup

- Record `START_TS=$(date +%s)` immediately so Step 6 can compute
  `ELAPSED`.
- Resolve `TARGET_REPO` via
  `gh repo view --json nameWithOwner -q .nameWithOwner` and `PR_NUMBER`
  via the explicit arg or `gh pr view --json number -q .number`.
  Failing either → exit 1.
