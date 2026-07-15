---
name: gh:pr-reply
description: >-
  Fetch code review comments on a GitHub PR, evaluate each one, apply valid fixes, and leave an individual reply on every comment (Accepted with what changed, or Declined with reasoning). Use when the user runs /gh:pr-reply, /gh-pr-reply, or asks "PR 리뷰 코멘트 확인하고 수정", "리뷰 답변 달아", "PR 123 코멘트 처리해". Defaults to the PR for the current branch; accepts an explicit PR number and an optional `[remote]` positional (the remote pins the target repo when several remotes share one GitHub host). Every comment MUST get a reply — bot comments (gemini, sourcery, copilot) included. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "review comment evaluation + classification + targeted edits + per-comment reply; moderate analysis, not deep implementation"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-reply — Address PR Review Comments

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md`, output it
verbatim, then stop. No API calls.

## Role

Process every code-review comment on a PR: judge validity, fix valid ones,
reply to each with the outcome. **Politeness rule** — reviewers (humans and
bots alike) must see an explicit response on every thread. Silent fixes are
not acceptable; silent declines are worse.

## Step 1: Resolve Target PR + Repo

Record `START_TS=$(date +%s)` immediately (elapsed tracking in Step 7).
Positional args: `<pr-number> [remote]` (`remote` defaults to `origin`).

**PR number** precedence: (1) **explicit arg** — `/gh:pr-reply 123` → PR
#123; (2) **current branch** — `gh pr view --json
number,url,headRefName,baseRefName`, stop if no PR; (3) never guess, never
pick "the latest PR".

**TARGET_REPO** — resolve from the `[remote]` positional, not from `gh`'s
default-repo heuristic, so a repo with two remotes on the same host (e.g.
`origin` + `upstream`) replies to the intended one. Bind `remote` to the
positional (default `origin`), source the SSOT helper, and parse the
remote's URL (network-free):

```sh
# DOTFILES_FORCE_INIT=1 is load-bearing: the file's interactive guard
# otherwise returns early in a non-interactive shell and the helper is
# never defined. `remote` is the [remote] positional; ${remote:-origin}
# keeps the block self-contained whether or not it was set.
export DOTFILES_FORCE_INIT=1
. "${SHELL_COMMON}/functions/gh_pr_review.sh"
TARGET_REPO=$(_gh_pr_review_resolve_target_repo "${remote:-origin}") || {
  echo "Cannot resolve remote '${remote:-origin}' to a repo" >&2; exit 1; }
```

Pass `TARGET_REPO` (`--repo "$TARGET_REPO"` / `-R`, or as the
`repos/$TARGET_REPO/...` path) on **every** subsequent `gh` API call.

**Default-remote tradeoff** — `[remote]` defaults to `origin`. This is more
predictable than the old `gh repo view` default-repo heuristic, but note the
fork workflow where `origin` is your fork and `upstream` is the canonical
repo: there, reply explicitly with `/gh:pr-reply <N> upstream`. On the
`devx:pr-review-all` / `gh:issue-flow` path the remote is threaded through, so
the default only applies to a bare manual `/gh:pr-reply <N>`.

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied
threads. Bot service notices (quota / rate-limit / outage) follow that
reference's "Bot service notices" section (service-notice classification,
single-line ack in Step 5, counted separately in Step 7).

**Step 2.5 early exit:** if this yields **zero unaddressed threads** after
dedup, print exactly `No unaddressed review comments — nothing to do.` and
**stop** — do not run Steps 3–7, do not post ai-metrics, do not push.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules; see `references/reply-templates.md` for the full rubric.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Keep each fix minimal and scoped — no drive-by refactors. Group related
fixes into themed commits (one per theme, not per comment), e.g.
`fix(review): address X …`. Never `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment from Step 2 must receive a reply, including
declined ones and bot comments.** Read `references/reply-templates.md` for
POST command shapes, the four body templates, the long-body fallback, and
the consolidated table reply. Reply in the reviewer's language.

## Step 6: Push the Fix Commits + Sync Board

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary. Set
`PUSHED_FIXES` to the count of new SHAs on the remote branch; no fixes /
skipped push → `PUSHED_FIXES=0`. If `PUSHED_FIXES > 0`, push the PR card
back to `In review` per `references/board-sync-in-review.sh.md` (soft-fail;
no-op when `PUSHED_FIXES == 0`).

## Step 7: Report

Print the summary table per `references/final-summary.md` (Accepted /
Declined / Answered counts, commit SHAs, skipped comments, the
`STEP8_OUTCOME`-driven Step 8 row, and the lingering `CHANGES_REQUESTED`
nudge — all rendering rules in that reference; an empty `STEP8_OUTCOME` is an
**incomplete** report, issue #662). Then post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip when `GH_DISABLE_AI_METRICS=1`).

## Step 8: Solo-Repo Auto-Approve (opt-in, soft-fail)

After Step 7, optionally move the PR card from `In review` to `Approved`.
Run the 4-guard gate per `references/auto-approve.md`.

## Constraints

- **Never skip a reply** — even "Declined: out of scope" counts, bot comments included; core contract. Never dismiss a bot comment as "just a bot".
- Never close/resolve threads programmatically — leave that to the user.
- Never fix files outside the PR's diff without flagging scope creep first.
- Never `--force-push`. If history rewrite is needed, stop and ask.
- To mutate PR labels or body, route through `_gh_pr_edit_safe_label` /
  `_gh_pr_edit_safe_body` (`shell-common/functions/gh_pr_edit_safe.sh`) — bare
  `gh pr edit --add-label` / `--body-file` silently exits 1 on classic-Projects repos (issue #326 Bug B).
