---
name: devx:pr-review-all
description: >-
  Fan out every available reviewer on one PR in parallel — gemini ∥ codex
  second opinions ∥ built-in /simplify — then run a reply pass over the
  review comments. Use for /devx:pr-review-all, /devx-pr-review-all,
  "PR 다중 리뷰어 병렬로", "gemini codex simplify 한번에 돌려",
  "PR 99 전체 리뷰". A composition skill — distinct from gh:pr-review
  (single external AI, one comment). Reused by gh:issue-flow as its post-PR
  quality gate. Accepts `<PR#> [remote] [--defer-reply M] [--no-reply]`
  and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "parallel review fan-out orchestration; soft-fail gate + inline/deferred reply"
    claude: prefer
    non_claude: advisory-only
---

# devx:pr-review-all — Multi-reviewer PR gate + reply

## Role

Orchestrate a single PR through all available reviewers at once (gemini ∥
codex ∥ `/simplify`), commit any simplify cleanup, then reply to the review
comments — inline (deterministic) or deferred. No approve / request-changes
decision (that is `gh:pr-approve`) and no per-comment authoring beyond the
delegated `gh:pr-reply`. Every reviewer is soft-fail: a missing CLI or a
transient error skips that one lane and the rest continue.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
it verbatim, then stop. No API calls.

## Step 1: Parse Args

Source and delegate to `devx_pr_review_all_parse`:
`source "${SHELL_COMMON}/functions/devx_pr_review_all.sh"` then
`devx_pr_review_all_parse "$@"`. On `help_requested=1` follow Help; on exit 2
print the stderr line and stop. Capture `pr`, `remote`, `reply_mode`
(inline|defer|none), `reply_delay`. Record `START_TS=$(date +%s)`.

## Step 2: Pre-flight

- PR state must be `OPEN` and not draft → else exit 1 `PR #<pr> is <state>; aborting`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.
- **simplify branch context**: if the current branch is not the PR head
  branch, run `gh pr checkout <pr>`; if already on it (e.g. the issue-flow
  worktree path), skip. `/simplify` ignores PR# and acts on the working tree,
  so this checkout is load-bearing (`references/constraints.md`).

## Step 3: Parallel review gate (dispatch all lanes in ONE turn)

The three lanes are independent, so dispatch **all Agent subagents in a single
turn**. Each lane is soft-fail — a failure marks that lane `[SKIP]`/`[WARN]`
and the others continue. Detail: `references/constraints.md`.

- **gemini** — if `command -v gemini`, an Agent runs
  `Skill(gh:pr-review, "--ai gemini <pr>")`; absent or non-zero exit → SKIP/WARN.
- **codex** — if `command -v codex`, an Agent runs
  `Skill(gh:pr-review, "--ai codex <pr>")`; absent or non-zero exit → SKIP/WARN.
- **/simplify** — an Agent runs the built-in `/simplify` on the working-tree
  diff (PR# is ignored — hence the Step 2 checkout).

## Step 4: Commit + push simplify changes (only if the tree changed)

Await all three Agents, then:

- `git status --porcelain` non-empty → `git commit -m "refactor(<scope>):
  simplify per /simplify"` + `git push`. **Never a bare `git commit`** — it
  hangs on the editor in a non-interactive shell; always pass `-m`.
- Clean tree → skip.

## Step 5: pr-reply (per reply_mode)

- `inline` (default) → run `Skill(gh:pr-reply, "<pr>")` immediately. Step 3
  was awaited, so gemini/codex comments are already posted — reply order is
  deterministic, no delay needed (`references/constraints.md`).
- `defer` → `Skill(devx:schedule, "--time <reply_delay> \"/gh-pr-reply <pr>\"")`.
- `none` → skip.

## Step 6: Report

Print exactly one `[OK]`/`[SKIP]`/`[WARN]` line, e.g.
`[OK] PR #<pr> reviewed (gemini:OK codex:SKIP simplify:committed) — reply: inline`.

## Constraints (full rationale: `references/constraints.md`)

- Every reviewer lane is soft-fail — never hard-fail on a missing/erroring CLI.
- Never a bare `git commit` — always `-m` (non-interactive hang guard).
- Inline reply is the deterministic path; `--defer-reply` is minutes-only and not a guarantee.
- No approve / request-changes here — that is `gh:pr-approve`.
