---
name: devx:pr-review-all
description: >-
  Fan out every available reviewer on one PR in parallel — agy ∥ codex
  second opinions ∥ a sequential /code-review --fix → /simplify auto-fix
  chain (each sub-step commits its own changes) — then run a reply pass over
  the review comments. Use for /devx:pr-review-all, /devx-pr-review-all,
  "PR 다중 리뷰어 병렬로", "agy codex simplify 한번에 돌려",
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

Orchestrate a single PR through all available reviewers at once (agy ∥
codex ∥ `/code-review --fix` → `/simplify`), commit any auto-fix changes per
sub-step, then reply to the review comments — inline (deterministic) or
deferred. No approve / request-changes decision (that is `gh:pr-approve`) and
no per-comment authoring beyond the delegated `gh:pr-reply`. Every reviewer is
soft-fail: a missing CLI or a transient error skips that one lane and the
rest continue.

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

- Resolve `TARGET_REPO` for `<remote>`: `gh repo view "$(git remote get-url
  <remote>)" --json nameWithOwner -q .nameWithOwner`; failure → exit 1 `Cannot
  resolve remote '<remote>' to a repo`. Pass `-R <TARGET_REPO>` on every `gh
  pr`/`gh repo` call below so a non-origin `<remote>` is honored.
- PR state must be `OPEN` and not draft (`gh pr view <pr> -R <TARGET_REPO>`)
  → else exit 1 `PR #<pr> is <state>; aborting`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.
- **auto-fix branch context**: if the current branch is not the PR head
  branch, run `gh pr checkout <pr> -R <TARGET_REPO>`; if already on it (e.g.
  the issue-flow worktree path), skip. `/code-review --fix` and `/simplify`
  both ignore PR# and act on the working tree, so this checkout is
  load-bearing (`references/constraints.md`).

## Step 3: Review + auto-fix gate (dispatch all lanes in ONE turn)

The three lanes dispatch together in a single turn. agy and codex are
comment-only (never touch the working tree), so they run fully in parallel
with everything else. `/code-review --fix` and `/simplify` both mutate the
PR working tree, so **within the third lane they run sequentially, each
followed immediately by its own commit** — never concurrently with each
other, or the two agents could edit the same files at once
(`references/constraints.md`). Each lane is soft-fail — a failure marks that
lane `[SKIP]`/`[WARN]` and the others continue.

- **agy** — if `command -v agy`, an Agent runs
  `Skill(gh:pr-review, "--ai agy <pr> <remote>")`; absent or non-zero exit → SKIP/WARN.
- **codex** — if `command -v codex`, an Agent runs
  `Skill(gh:pr-review, "--ai codex <pr> <remote>")`; absent or non-zero exit → SKIP/WARN.
- **auto-fix chain** (sequential sub-steps, both on the working-tree diff;
  PR# is ignored by both — hence the Step 2 checkout):
  1. An Agent runs `/code-review --fix`. `git status --porcelain` non-empty →
     `git commit -am "fix(<scope>): code-review --fix"`; erroring invocation →
     WARN, continue to sub-step 2 regardless.
  2. Only after sub-step 1's commit (or no-op), an Agent runs the built-in
     `/simplify`. `git status --porcelain` non-empty → `git commit -am
     "refactor(<scope>): simplify per /simplify"`.
  **Never a bare `git commit`** in either sub-step — it hangs on the editor
  in a non-interactive shell; always pass `-m`.

## Step 4: Push any auto-fix commits (only if something changed)

Await all lanes, then:

- Either auto-fix sub-step committed → `git push` once (both commits go up
  together).
- Neither sub-step changed the tree → skip.

## Step 5: pr-reply (per reply_mode)

- `inline` (default) → run `Skill(gh:pr-reply, "<pr> <remote>")` immediately.
  Step 3 was awaited, so agy/codex comments are already posted — reply
  order is deterministic, no delay needed. The `<remote>` is threaded so
  `gh:pr-reply` resolves the same target repo this skill did, not gh's
  default-repo heuristic (`references/constraints.md`).
- `defer` → `Skill(devx:schedule, "--time <reply_delay> \"/gh-pr-reply <pr> <remote>\"")`.
- `none` → skip.

## Step 6: Report

Print exactly one `[OK]`/`[SKIP]`/`[WARN]` line, e.g.
`[OK] PR #<pr> reviewed (agy:OK codex:SKIP code-review:committed simplify:committed) — reply: inline`.

## Constraints (full rationale: `references/constraints.md`)

- Every reviewer lane is soft-fail — never hard-fail on a missing/erroring CLI.
- `/code-review --fix` and `/simplify` both mutate the working tree — run them
  sequentially with a commit between them, never concurrently with each other.
- Never a bare `git commit` — always `-m` (non-interactive hang guard).
- Inline reply is the deterministic path; `--defer-reply` is minutes-only and not a guarantee.
- No approve / request-changes here — that is `gh:pr-approve`.
