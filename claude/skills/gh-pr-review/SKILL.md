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
---

# gh:pr-review — Delegate PR Review to an External AI CLI

## Role

Gather a second-opinion code review on a GitHub PR from one of three
external AI CLIs (`codex` / `gemini` / `claude`). Stream the output to
the user, post it as a PR comment by default, and **stop there** — no
decision (approve / request-changes) and no per-comment replies. Those
belong to the sister skills `gh:pr-approve` and `gh:pr-reply`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Flags + Resolve Target

Delegates to `gh_pr_review_parse` in
`shell-common/functions/gh_pr_review.sh` (issue #664). That function is
the **single source of truth** for the argument surface — the flat
state machine, the closed `--review` enum, the KR-alias normalization,
the `--user` cross-AI rejection, and the exit-code mapping (0 / 1 / 2)
all live there. The bats fixture
`tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh` is now a thin
wrapper around the same function, so any drift between this section
and the production parser is caught by
`tests/bats/skills/gh_pr_review_arg_parse.bats`.

Contract this skill depends on (do not duplicate the parser here; read
`shell-common/functions/gh_pr_review.sh` for the authoritative shape):

- `--ai <codex|gemini|claude>` — required.
- `--review <preset>` — closed enum; KR aliases normalize before
  dispatch.
- `--user <name>` — `--ai claude` only.
- `--no-post-comment` — skips Step 6.
- Positional `<pr-number>` (optional; auto-detect from current branch)
  and `<remote>` (default `origin`).

Record `START_TS=$(date +%s)` immediately so Step 6 can compute
`ELAPSED`.

Resolve `TARGET_REPO` via
`gh repo view --json nameWithOwner -q .nameWithOwner` and `PR_NUMBER`
via the explicit arg or `gh pr view --json number -q .number`. Failing
either → exit 1.

## Step 2: Pre-flight

Run these checks in parallel before doing any expensive work:

- PR state must be `OPEN` AND not draft. Closed / merged / draft →
  exit 1 with `PR #<N> is <state>; aborting`.
- `command -v <ai-bin>` for the chosen `--ai` value. Missing →
  exit 1 with `Required CLI '<name>' not found in PATH`.
- `gh auth status` returns 0. Failing → exit 1 with the gh error line.

**CI status is intentionally NOT a gate.** Opinion collection works
regardless of failing CI — sometimes that is the reason the user
wants a second opinion in the first place.

Self-authored PRs are also allowed: no decision is submitted, so the
GitHub server-side self-approve block is irrelevant.

## Step 3: Load Review Preset

Read `references/review-presets.md`. Build the prompt as:

```text
<common-prompt-prefix>

<preset-body for the resolved enum>
```

The normalized enum is one of `default`, `quick`, `thorough`,
`security`, `performance`. If a KR alias was passed, the normalization
has already happened in Step 1.

## Step 4: Fetch Review Material

Decide path by diff size:

```sh
gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json additions,deletions
```

When `additions + deletions ≥ 800`, follow the subagent delegation
pattern documented in
`claude/skills/gh-pr-approve/references/large-diff-delegation.md`.
Inline path otherwise:

```sh
gh pr diff "$PR_NUMBER" --repo "$TARGET_REPO"
```

Append the diff to the prompt under a clearly delimited section per
`references/ai-cli-invocation.md` § "stdin payload shape". Write the
combined `(prompt + diff)` to a temp file `PROMPT_FILE` — the external
CLI receives it on stdin so argv length and quoting are not concerns.

## Step 5: Dispatch to External CLI

Delegates to `_gh_pr_review_run_ai` in
`shell-common/functions/gh_pr_review.sh`. The function pipes
`PROMPT_FILE` into the chosen CLI with the exact invocation shape
documented in `references/ai-cli-invocation.md` (`codex exec
--color=never`, `gemini -p`, `claude -p`, plus the `CLAUDE_CONFIG_DIR`
injection for `--user`). Stdout streams to the user verbatim — no
reformatting, no summarization, no truncation.

On non-zero exit from the external CLI the helper writes
`External AI CLI '<name>' failed: <first stderr line>` to stderr and
returns the CLI's exit code. The skill propagates that as exit 1 and
skips Step 6; partial output is discarded.

## Step 6: Post PR Comment (default ON)

Delegates body construction and posting to two helpers in
`shell-common/functions/gh_pr_review.sh`:

- `_gh_pr_review_build_comment_body` — emits the SSOT body per
  `references/post-comment.md` (collapsed `<details>` AI-review block
  + `<!-- ai-review:<ai> -->` markers + ai-metrics footer with
  `<!-- ai-metrics:gh-pr-review -->` markers).
- `_gh_pr_review_post_comment` — wraps `gh pr comment --body-file`
  and enforces three behaviors with a single decision tree:
  1. `--no-post-comment` → print `skipped (--no-post-comment)` and
     return 0.
  2. `GH_DISABLE_AI_METRICS=1` → print
     `skipped (GH_DISABLE_AI_METRICS=1)` and return 0. The opt-out
     skips the **entire** PR comment (not just the metrics footer),
     because the AI-review body and the metrics footer ship together
     (issue #399).
  3. `gh pr comment` non-zero exit → print `[WARN] PR comment post
     failed — output retained on stdout` to stderr, emit
     `[WARN] post failed` to stdout, and still return 0 — the user
     already has the AI output on their terminal.

Token, human-h, and elapsed-minute inputs are computed by
`_gh_pr_review_estimate_tokens` and `_gh_pr_review_human_h`
(per-preset baseline from `references/post-comment.md`). The skill
does not duplicate those formulas — read the shell function for the
authoritative arithmetic.

## Step 7: Report

Print exactly one line on success:

```text
[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>
```

`<URL or skipped>` is the comment URL on success, `skipped (--no-post-comment)`
when the flag was set, `skipped (GH_DISABLE_AI_METRICS=1)` when the env
var was set, or `[WARN] post failed` when the soft-fail branch ran.

## Constraints

- **Never submit a decision.** `gh pr review --approve` and
  `--request-changes` are out of scope. This skill collects opinions
  only; the human (or `gh:pr-approve`) decides.
- **Never reply to individual review comments.** That is `gh:pr-reply`'s
  job. This skill writes one aggregate comment per invocation.
- **Never run multiple AI CLIs in one invocation.** Single `--ai`
  value; rerun the command N times for an N-way comparison.
- **Never accept free-text `--review`.** Closed enum + KR aliases only.
  Typos exit 2 cleanly.
- **Never reformat the external AI's stdout.** The user wants raw
  output to judge for themselves.
- **Never block self-authored PRs.** No decision is submitted; the
  self-approve restriction does not apply.
- **Never edit the PR body.** Use `gh pr comment` (append) — `gh pr
  edit --body` silently exits 1 on repos with classic Projects
  attached (issue #326 Bug B). If a future iteration needs body
  mutation, route through `_gh_pr_edit_safe_body` per CLAUDE.md.
- **Never log the external CLI's stderr to a PR comment.** Stderr is
  only used to derive the error-message first line on non-zero exit.
- Honor `GH_DISABLE_AI_METRICS=1` consistently with sister skills:
  skip the entire PR comment (not just the footer).
