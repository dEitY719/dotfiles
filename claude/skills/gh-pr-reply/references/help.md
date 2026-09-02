# gh:pr-reply — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | PR number, or `-h`/`--help`/`help` | current-branch PR | Target PR, e.g. `123` |
| 2 | remote name | `origin` | Git remote used to resolve the target repo (`owner/repo`) — pins the repo when multiple remotes share one GitHub host |
| — | `--review-pass` | off | Skip comment processing; drop `review-blocked`, apply `review-passed` directly. Mutually exclusive with `--review-block`. May appear anywhere among the args. |
| — | `--review-block` | off | Skip comment processing; drop `review-passed`, apply `review-blocked` directly. Mutually exclusive with `--review-pass`. May appear anywhere among the args. |

## Usage

- `/gh-pr-reply` — process review comments on the PR for the current branch
- `/gh-pr-reply 123` — process review comments on PR #123 explicitly
- `/gh-pr-reply 123 upstream` — target PR #123 on the `upstream` remote's repo
- `/gh-pr-reply 123 --review-pass` — skip comment processing; force
  `review-passed` on PR #123 (drops `review-blocked` first)
- `/gh-pr-reply 123 --review-block` — skip comment processing; force
  `review-blocked` on PR #123 (drops `review-passed` first)
- `/gh-pr-reply -h` / `--help` / `help` — print this help

## What the skill does

1. Resolves the target PR (explicit arg first, else the current branch's
   PR via `gh pr view --json`). Never guesses "the latest PR". Resolves
   the target repo (`owner/repo`) by parsing the `[remote]` arg's URL
   (default `origin`), so multi-remote repos reply to the intended host.
2. Fetches all review comments from the three GitHub endpoints (inline
   thread, issue comment, review summary) per
   `references/comment-fetching.md`, deduped and filtered to threads you
   have not yet replied to.
3. Classifies each unaddressed comment: **ACCEPT**, **ACCEPT-PARTIAL**
   (valid concern, different fix), **DECLINE**, or **QUESTION**. Bots
   (gemini-code-assist, sourcery-ai, copilot) are treated identically to
   human reviewers.
4. Applies ACCEPT / ACCEPT-PARTIAL fixes, keeping each fix minimal and
   scoped. Groups related fixes into themed commits (not one commit per
   comment). Never `--amend` or `--no-verify`.
5. Replies to **every** identified comment using the inline-vs-top-level
   endpoint and body template from `references/reply-templates.md`. This
   is the politeness contract — declines and bot nits get replies too.
6. Pushes fix commits (`git push`, never force) if any landed.
7. Prints a compact summary: Accepted / Declined / Answered counts plus
   commit SHAs, and lists any comments skipped as "already replied".

## Manual verdict override

`--review-pass` / `--review-block` bypass everything above — no comment
fetch, no evaluation, no fixes, no reply, no push. They swap the verdict
label directly and stop. This is an explicit, user-invoked override: the
BLOCKER gate that the normal flow uses to decide `review-passed`
(`references/review-passed-gate.md`) is not consulted. Use it when you have
verified the PR through channels the skill cannot see and need the label to
reflect that now. See `references/manual-override.md`.

## What the skill will NOT do

- Skip a reply for a comment — silent fixes and silent declines are both
  prohibited. Even "Declined: out of scope" one-liners count.
- Dismiss bot comments as "just a bot".
- Close or resolve threads programmatically — the user does that.
- Fix comments touching files outside the PR's diff without flagging
  scope creep to the user first.
- Force-push. If history rewrite is required, it stops and asks.
- Guess the PR when the current branch has none — it stops and asks.

## Good vs. bad invocation

- **Good**: after pushing commits, `/gh-pr-reply` — processes every new
  review comment on your branch's PR.
- **Good**: `/gh-pr-reply 99` — force target PR #99 even from a different branch.
- **Good**: `/gh-pr-reply 99 upstream` — target PR #99 on the `upstream`
  remote's repo when `origin` and `upstream` both point at GitHub.
- **Bad**: running from a branch with no PR — skill stops and asks you to
  open one first.
- **Bad**: expecting the skill to fix unrelated files — it refuses scope creep.
