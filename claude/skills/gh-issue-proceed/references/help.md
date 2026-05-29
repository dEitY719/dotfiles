# gh:issue-proceed — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub directive issue number |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh-issue-proceed 81` — read directive issue #81, validate the embedded
  protocol, execute it end-to-end, apply authorized write actions.
- `/gh-issue-proceed 81 upstream` — same, against `upstream` remote's repo.
- `/gh-issue-proceed -h` / `--help` / `help` — print this help.

There is no `mode` argument: a directive issue is already designed, so
execution is always direct. For code-change issues ("edit files to satisfy
the issue") use the sibling `/gh-issue-implement`.

## What a directive issue is

A work-order issue whose body embeds an **execution protocol** — numbered
steps or a workflow matrix, plus decision rules, deliverables, and done
criteria. Verify / triage / analysis / docs-ship tasks are typical. The
skill executes the protocol; it does not author or edit it.

## The 8 required sections (strict schema)

`goal`, `preconditions`, `execution_protocol`, `decision_rules`,
`deliverables`, `done_criteria`, `out_of_scope`, `safety`. Each is matched
by H2/H3 heading with case-insensitive KO/EN aliases. Any missing, empty,
or unparseable required section → schema-validation refusal (no work
done, no comment posted). Full schema: `references/protocol-schema.md`.

## What the skill does

1. Resolves the repo, fetches the issue, claims it (assign + board move).
2. Validates the body against the strict 8-section schema.
3. Classifies the precondition (read-only / mutation-required / mixed /
   verify-only) and enforces branch + clean-tree accordingly.
4. Runs pre-flight safety checks, parses the protocol into steps.
5. Executes each step under safety gates, classifies the result against
   the body's decision rules, and applies the mapped action verb
   (commit / PR / comment / close / file follow-up).
6. Reconciles the done-criteria checklist, closes the issue when fully
   met, and prints a structured audit report.

## Safety posture

Four layers (`references/safety-gates.md`):

1. **Absolute prohibitions** — force-push to default, secret leakage,
   cross-worktree mutation, `gh pr merge`, etc. Abort regardless of the
   issue body.
2. **Conditional permissions** — bulk ops, force-with-lease, cross-repo,
   outbound net. Default-deny; allowed only with the matching §safety
   `allow:` token.
3. **Pre-flight** — branch / secret-shaped files / `gh auth status` /
   §preconditions dry-run.
4. **Runtime monitors** — per-step + global timeout, output secret
   scanner, write-action quota (per-type 5, total 20).

## What the skill will NOT do

- Merge a PR. That belongs to `/gh-pr-merge` / `/gh-pr-merge-emergency`.
- Author or edit the directive itself — humans (or `/devx:trd-to-issues`)
  do that.
- Run a `mutation-required` directive on the default branch or with a
  dirty tree.
- Post a comment when schema validation fails (caller-side problem).

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone` | Block-label list (claim guard). |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip self-assign. |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip board transition. |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip depends-on guard. |
| `GH_DISABLE_AI_METRICS` | unset | When `1`, omit the ai-metrics line. |
