# devx:pr-review-all — Help

Fan out **every available reviewer** on one PR in parallel — `gemini` ∥
`codex` second opinions ∥ the built-in `/simplify` cleanup — then run a
reply pass over the resulting review comments. A composition skill: it
orchestrates several reviewers plus a reply, unlike `gh:pr-review` (a single
external AI, one aggregate comment). It submits **no decision** (approve /
request-changes) — that is `gh:pr-approve`.

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | PR number, or `-h`/`--help`/`help` | — (required) | Target PR, e.g. `99` |
| 2 | remote name | `origin` | Git remote for the target repo |

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--defer-reply M` / `--defer-reply=M` | off (inline) | Schedule `/gh-pr-reply` M **minutes** later via `devx:schedule` instead of replying inline. |
| `--no-reply` | off | Skip the reply step entirely. |
| `-h` / `--help` / `help` | — | Print this help and stop. |

`--defer-reply` and `--no-reply` together → `--no-reply` wins (reply skipped).

## Usage

- `/devx-pr-review-all 99` — review PR #99 with all available reviewers, reply inline
- `/devx-pr-review-all 99 upstream` — same, targeting the `upstream` repo
- `/devx-pr-review-all 99 --defer-reply 8` — review now, schedule the reply 8 min later
- `/devx-pr-review-all 99 --no-reply` — review only; skip the reply pass
- `/devx-pr-review-all -h` / `--help` / `help` — print this help

## What the skill does

1. Parse args via `devx_pr_review_all_parse`; record `START_TS`.
2. Pre-flight: PR must be `OPEN` and non-draft, `gh auth` must be live, and
   check out the PR head branch if not already on it (so `/simplify` acts on
   the right tree).
3. Parallel review gate — dispatch gemini, codex, and `/simplify` as Agent
   subagents **in one turn**. gemini/codex delegate to
   `gh:pr-review --ai <name>` (streams findings + posts a PR comment).
   Each lane is soft-fail.
4. Commit + push any `/simplify` changes (only if the working tree changed),
   always with an explicit `-m` message.
5. Reply — inline `gh:pr-reply <pr> <remote>` (default), or deferred via
   `devx:schedule` (`--defer-reply M`), or skipped (`--no-reply`). The
   `<remote>` is threaded so the reply pass resolves the same target repo.
6. Print one `[OK]`/`[SKIP]`/`[WARN]` report line.

## What the skill will NOT do

- Submit `gh pr review --approve` / `--request-changes` — that is `gh:pr-approve`.
- Hard-fail because a reviewer CLI is missing or errors — each lane is soft-fail.
- Run a bare `git commit` — an editor prompt would hang the non-interactive shell.
- Schedule sub-minute delays — `devx:schedule` is minutes-only; for tight
  ordering use the deterministic inline reply.

## Exit codes

| Code | Cause |
|------|-------|
| 0 | Review gate ran and the reply step completed / was scheduled / was skipped. |
| 1 | PR not `OPEN`/non-draft, or `gh` not authenticated. |
| 2 | Argument error: missing `<PR#>`, non-integer `<PR#>`, unknown flag, or bad `--defer-reply` value. |

## Good vs. bad invocation

- **Good**: `/devx-pr-review-all 99` — all reviewers + inline reply on PR #99.
- **Good**: `/devx-pr-review-all 99 --defer-reply 8` — issue-flow-style deferred reply.
- **Bad**: `/devx-pr-review-all` — exits 2 (missing `<PR#>`).
- **Bad**: `/devx-pr-review-all abc` — exits 2 (PR# must be a positive integer).
