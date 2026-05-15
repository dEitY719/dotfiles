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

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 7.

Positional args (in this order): `<pr-number>` (optional — auto-detect
from current branch when omitted) and `<remote>` (default `origin`).
Flags may appear anywhere:

- `--ai <codex|gemini|claude>` — **required**. Unknown value → exit 2
  with `Unknown --ai value: '<x>' (allowed: codex, gemini, claude)`.
- `--review <preset>` — optional. Default `default`. Normalize KR
  aliases per `references/review-presets.md` § "Normalization rules";
  unknown values → exit 2 with the allowed-enum stderr message.
- `--user <name>` — optional, `--ai claude` only. Combined with any
  other `--ai` value → exit 2 with `--user is only valid with --ai
  claude (codex/gemini have no multi-account routing)`. The account
  name flows through `_claude_resolve_account` (see
  `references/ai-cli-invocation.md` § `--ai claude --user <name>`);
  unknown name → exit 1.
- `--no-post-comment` — optional. Skips the PR comment in Step 6.

Resolve:

- `TARGET_REPO` from `git remote get-url <remote>` (or
  `gh repo view --json nameWithOwner -q .nameWithOwner`). Missing
  remote → list `git remote -v` and stop (exit 1).
- `PR_NUMBER`: explicit arg, else `gh pr view --json number -q
  .number` on the current branch. Neither available → exit 1 with
  `No PR found for current branch; pass PR number explicitly`.

Reject unknown flags eagerly so typos exit fast. Each value-taking
flag (`--ai`, `--review`, `--user`) must check `[ $# -lt 2 ]` before
the `shift 2`, exiting 2 with `missing value for <flag>` so a trailing
flag without its value never reads past the end of argv.

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

Run one of the three commands from `references/ai-cli-invocation.md`,
selected by the resolved `--ai` value. For `--ai claude --user
<name>`, source the helper and inject `CLAUDE_CONFIG_DIR` exactly as
documented there. Stream stdout to the user's terminal verbatim — no
reformatting, no summarization, no truncation.

Non-zero exit from the external CLI → quote the first stderr line and
exit 1. Do not post a PR comment in that case; partial output is
discarded.

## Step 6: Post PR Comment (default ON)

Skip when `--no-post-comment` is set OR when
`GH_DISABLE_AI_METRICS=1` (issue #399). The opt-out skips the entire
PR comment — not just the ai-metrics footer — because the AI-review
body and the metrics footer ship together. The stdout output is
unaffected by either skip path.

Build the comment body per `references/post-comment.md` (collapsed
`<details>` wrapper + verbatim CLI stdout + ai-metrics footer). The
inline guard pattern, identical to `gh-pr-reply` Step 7:

```sh
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
RAW_BYTES=$(wc -c < "$PROMPT_FILE")
TOKENS_RAW=$(( RAW_BYTES / 4 ))
TOKENS=$(( (TOKENS_RAW + 250) / 500 * 500 ))
[ "$TOKENS" -lt 1000 ] && TOKENS=1000
# HUMAN_H baseline per preset — see references/post-comment.md § "Human time baseline".

if [ "$NO_POST_COMMENT" = "1" ]; then
    : # PR comment skipped via --no-post-comment.
elif [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # PR comment skipped via GH_DISABLE_AI_METRICS — stdout still shown.
else
    gh pr comment "$PR_NUMBER" --repo "$TARGET_REPO" --body-file "$BODY_FILE" \
        || echo "[WARN] PR comment post failed — output retained on stdout"
fi
```

Soft-fail: a non-zero exit from `gh pr comment` prints the `[WARN]`
line and continues to Step 7 with exit 0. The user already has the AI
output in their terminal.

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
