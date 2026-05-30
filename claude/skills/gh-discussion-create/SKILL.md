---
name: gh:discussion-create
description: >-
  Save the current conversation as a GitHub Discussion (default category
  `Ideas`, RFC-shaped body). Use when the user runs /gh:discussion-create,
  /gh-discussion-create, asks "이 대화 RFC 로 등록", "Ideas Discussion 으로
  남겨", "이 토론 깃허브 디스커션으로", or wants the chat preserved as a
  pre-decision RFC instead of a to-do issue. Drafts an Open-Questions-forward
  body and posts it via the `createDiscussion` GraphQL mutation. Sister skill
  of [[gh-issue-create]] — same conversation capture, different lifecycle.
  Refuses when the conversation is already a decided to-do unless
  `--force-discussion` is set; suggests `/gh-issue-create` instead. Accepts an
  optional remote name and a `[category]` (`Ideas` / `Q&A` / `Announcements` /
  `Lessons`); `-h`/`--help`/`help` prints usage.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "discussion creation wrap; bounded GraphQL mutation with RFC body skeleton"
    claude: prefer
    non_claude: advisory-only
---

# gh:discussion-create — Conversation -> Ideas Discussion

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Convert the chat into a GitHub Discussion (default `Ideas`/RFC), executing
once the routing guard passes and printing only the URL. Sister of
`gh:issue-create` (same "preserve detail" contract), emphasising **Open Questions** over AC.

## Options

Arguments (positional `[remote]`/`[category]`, `--force-discussion`,
`GH_DISABLE_AI_METRICS`, `-h`/`--help`/`help`) →
[`references/options.md`](references/options.md).

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` for Step 4. Parse args, confirm a git repo,
resolve `TARGET_REPO=<owner>/<repo>` via the remote — substeps in
[`references/repo-resolution.md`](references/repo-resolution.md). No silent `origin` fallback on a missing remote.

## Step 2: Classify the Conversation

Pick exactly one category (default `Ideas`) per
[`references/category-table.md`](references/category-table.md) (mirrors the
discussions-policy SSOT). An explicit `[category]` still runs the Step 2.1
guard — body shape changes, not the check.

## Step 2.1: Routing Guard (Issue-vs-Discussion)

Per the SSOT routing tree (principle #1 "Issue is default"), apply the
trigger signals in [`references/scope-guard.md`](references/scope-guard.md):
a **decided to-do** -> stop with that file's "Refusal format" (destination
`/gh-issue-create`; override with `--force-discussion`); ambiguous-noun-list
/ ≥3-component-mix -> emit the same 1~2 line clarification as
`gh:issue-create` and wait. Load-bearing requirement F-3 + F-4 (issue #617)
— never disable without a SSOT update.

## Step 3: Draft the Discussion Body

Use the body skeleton in
[`references/rfc-template.md`](references/rfc-template.md), in the
conversation language. **Do NOT over-compress** — preserve file paths,
outputs, decisions, trade-offs, and the discussion log (a 200-line RFC is
fine). For non-`Ideas` categories, swap per that file's "Category variants".

## Step 3.5: Compute AI Metrics

Read `gh-issue-create`'s
[`references/metrics-baseline.md`](../gh-issue-create/references/metrics-baseline.md)
and bind `TOKENS`, `HUMAN_H`, `ELAPSED` for Step 4 (inputs: `START_TS`,
category, title + body; for `Ideas`, size like `feat`).

## Step 4: Create the Discussion

Source `shell-common/functions/gh_discussion.sh` and paste the full bash
block in [`references/create-cmd.md`](references/create-cmd.md) verbatim — it
handles the `mktemp` body file, the `GH_DISABLE_AI_METRICS=1` short-circuit
(#399 parity), the ai-metrics footer printf, and the three GraphQL calls.
확인 질문하지 말고 즉시 실행.

## Step 5: Report

Print the `[OK]` / `[FAIL]` block + `Next:` hint per
[`references/report-template.md`](references/report-template.md). A
routing-guard refusal (Step 2.1) prints its own message and skips Steps 3-5.

## Constraints

Operating invariants (always `--repo`, fail on missing remote, guard active
for all categories, no log over-compression, `--force-discussion`
bypass-only, no confirmation prompt, no category-ID cache) live in
[`references/constraints.md`](references/constraints.md).
