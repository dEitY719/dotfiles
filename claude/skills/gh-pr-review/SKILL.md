---
name: gh:pr-review
description: >-
  Delegate a GitHub PR's review to an external AI CLI (codex, gemini,
  or claude) for a second opinion. Streams the external CLI's findings
  to stdout and posts them as a PR comment by default. Does NOT submit
  a decision (no approve / request-changes) — that is gh:pr-approve's
  job, and replying to individual review comments is gh:pr-reply's. Use
  for /gh-pr-review, /gh:pr-review, "PR 99 코덱스에 리뷰 시켜",
  "gemini 한테 2차 의견 받아", "second-opinion review on PR 42".
  Accepts `--ai <codex|gemini|claude>` (required), `--review <preset>`,
  `--user <name>` (claude only), `--no-post-comment`, and `<PR#>
  [remote]` positional args. `-h`/`--help`/`help` prints usage.
allowed-tools: Bash, Read, Grep, Glob, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "dispatches to external AI CLI; prompt assembly + diff routing + comment posting; moderate orchestration, code judgment delegated"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-review — Delegate PR Review to an External AI CLI

## Role

Gather a second-opinion review on a GitHub PR from one external AI CLI
(`codex`/`gemini`/`claude`), stream its output, and post it as a PR
comment by default — then stop. No decision (approve/request-changes —
`gh:pr-approve`'s job) and no per-comment replies (`gh:pr-reply`'s
job). Every preset's prompt demands a critical stance
(`references/review-presets.md` § "Why critical review is always on")
with no flag to disable it.

## Help

If arg #1 is `-h` / `--help` / `help`, read `references/help.md` and
output it verbatim, then stop. No API calls.

## Step 1: Parse Flags + Resolve Target

Delegate to `gh_pr_review_parse` (`shell-common/functions/gh_pr_review.sh`).
Argument shape + KR aliases + exit codes: `references/parser-contract.md`
(also covers `START_TS` and resolving `TARGET_REPO` / `PR_NUMBER`).

## Step 2: Pre-flight

Run these checks in parallel before any expensive work:

- PR state must be `OPEN` AND not draft → else exit 1 `PR #<N> is <state>; aborting`.
- `command -v <ai-bin>` for the chosen `--ai` → else exit 1 `Required CLI '<name>' not found in PATH`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.

CI status is intentionally not a gate (a failing CI is often the reason
a second opinion is wanted); self-authored PRs are allowed (no
decision is submitted, so the self-approve block doesn't apply).

## Step 3: Load Review Preset

Read `references/review-presets.md`. Build the prompt as
`<common-prompt-prefix>` + `<preset-body for the resolved enum>`.
Normalized enum: `default` / `quick` / `thorough` / `security` /
`performance` (KR-alias normalized in Step 1).

## Step 4: Fetch Review Material

Decide path by diff size (`gh pr view ... --json additions,deletions`):
`≥ 800` lines → follow
`claude/skills/gh-pr-approve/references/large-diff-delegation.md`; else
inline `gh pr diff`. Append the diff per `references/ai-cli-invocation.md`
§ "stdin payload shape"; write `(prompt + diff)` to `PROMPT_FILE` (stdin).

## Step 5: Dispatch to External CLI

Delegate to `_gh_pr_review_run_ai` (`shell-common/functions/gh_pr_review.sh`).
Invocation shapes, stdout streaming, non-zero-exit handling:
`references/ai-cli-invocation.md` § "Step 5 dispatch procedure".

## Step 6: Post PR Comment (default ON)

Delegate to `_gh_pr_review_build_comment_body` +
`_gh_pr_review_post_comment` (`shell-common/functions/gh_pr_review.sh`).
SSOT body template, 3-branch decision tree (`--no-post-comment` /
`GH_DISABLE_AI_METRICS=1` / soft-fail), and token/human-h arithmetic:
`references/post-comment.md` § "Step 6 delegation + 3-branch decision tree".

## Step 7: Report

Print exactly one line on success:
`[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>`,
where `<URL or skipped>` is the comment URL, else
`skipped (--no-post-comment)` / `skipped (GH_DISABLE_AI_METRICS=1)` / `[WARN] post failed`.

## Constraints (full rationale: `references/constraints.md`)

- Never submit a decision (`gh:pr-approve`'s job) or reply to individual comments (`gh:pr-reply`'s job) — write one aggregate comment.
- Never run multiple AI CLIs per invocation (single `--ai`; rerun N times) or accept free-text `--review` (closed enum + KR aliases; typos exit 2).
- Never reformat the external AI's stdout (raw only) or block self-authored PRs (no decision submitted).
- Never edit the PR body — `gh pr comment` (append); `gh pr edit --body` fails on classic-Projects repos (#326 Bug B). Never log the CLI's stderr to a PR comment.
- Honor `GH_DISABLE_AI_METRICS=1` like sister skills: skip the entire PR comment, not just the footer.
