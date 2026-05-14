---
name: gh:discussion-create
description: >-
  Save the current conversation as a GitHub Discussion (default category
  `Ideas`, RFC-shaped body). Use when the user runs /gh:discussion-create,
  /gh-discussion-create, asks "이 대화 RFC 로 등록", "Ideas Discussion 으로
  남겨", "이 토론 깃허브 디스커션으로", or wants the chat preserved as a
  pre-decision RFC instead of a to-do issue. Drafts an Open-Questions-
  forward body (TL;DR + Why + Options + Alternatives + Open Questions),
  posts it via the `createDiscussion` GraphQL mutation, and prints the
  Discussion URL. Sister skill of [[gh-issue-create]] — same conversation
  capture quality, different lifecycle target. Refuses when the
  conversation already represents a decided to-do unless
  `--force-discussion` is set; suggests `/gh-issue-create` instead.
  Accepts an optional remote name (e.g. `/gh-discussion-create upstream`)
  to target a different remote's repo, an optional `[category]` flag to
  pick `Ideas` (default) / `Q&A` / `Announcements` / `Lessons`, and
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:discussion-create — Conversation -> Ideas Discussion

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Convert the current chat into a well-structured GitHub Discussion on the
target repo, defaulting to the `Ideas` (RFC) category. Execute
immediately without confirmation once the routing guard passes. Print
only the Discussion URL at the end.

This is the sister skill of `gh:issue-create`: same "preserve detail,
do not over-compress" contract, but the body emphasises **Open
Questions** instead of Acceptance Criteria, and the lifecycle target is
the Discussions forum — not the Issues to-do tracker.

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[remote]` (positional) | Git remote whose repo will own the Discussion. | `origin` |
| `[category]` (positional) | Discussion category. Case-insensitive match against the repo's category list. Allowed: `Ideas`, `Q&A`, `Announcements`, `Lessons`. | `Ideas` |
| `--force-discussion` | Bypass the routing guard (Step 2.1) when you know the chat is RFC-shaped despite a decided tone. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

The two positional args are order-insensitive when one is clearly a
category (e.g. `Q&A`, `Ideas`); otherwise the first non-flag positional
is treated as the remote.

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` for the ai-metrics footer in Step 4.
Parse the positional args and flags above. Confirm we are in a git repo
(`git rev-parse --show-toplevel`) and resolve `TARGET_REPO=<owner>/<repo>`
via the chosen remote — substeps in
[`references/repo-resolution.md`](references/repo-resolution.md).
Never silently fall back to `origin` when the user-supplied remote is
missing.

## Step 2: Classify the Conversation

Pick exactly one category. Default to `Ideas`. The four categories and
when to pick each are listed in
[`references/category-table.md`](references/category-table.md), which
mirrors the SSOT in `docs/.ssot/discussions-policy.md`.

If the user passed `[category]` explicitly, honour it — but still run
the routing guard in Step 2.1; user intent does not bypass the
"decided to-do" warning, only the body shape changes.

## Step 2.1: Routing Guard (Issue-vs-Discussion)

Per the SSOT routing decision tree (operating principle #1: "Issue is
default"), reject the chat when it represents a **decided to-do** —
the right destination is `/gh-issue-create`, not a Discussion. Apply
the trigger signals in
[`references/scope-guard.md`](references/scope-guard.md):

- "decided to-do" signals matched -> stop with the suggestion in
  `scope-guard.md` -> "Refusal format". The user can re-run with
  `--force-discussion` to override.
- ambiguous-noun-list / ≥3-component-mix signals matched -> emit the
  same 1~2 line clarification as `gh:issue-create`'s clarification
  guide; do not call the mutation until the user answers.
- Otherwise -> no-op, continue to Step 3.

This is the load-bearing requirement F-3 + F-4 from issue #617 — never
disable it without a SSOT update.

## Step 3: Draft the Discussion Body

Use the body skeleton in
[`references/rfc-template.md`](references/rfc-template.md). Write in
the conversation language (Korean chat -> Korean body). **Do NOT
over-compress** — preserve file paths, command outputs, decisions,
trade-offs, and the discussion log. A 200-line RFC is fine, just like
a 200-line `feat` issue is fine.

For non-`Ideas` categories, swap the template per
`references/rfc-template.md` -> "Category variants".

## Step 3.5: Compute AI Metrics

Read `gh-issue-create`'s
[`references/metrics-baseline.md`](../gh-issue-create/references/metrics-baseline.md)
and bind `TOKENS`, `HUMAN_H`, `ELAPSED` for Step 4. Inputs: `START_TS`
from Step 1, the chosen category, the drafted title + body. For
`Ideas` (RFC), treat the size heuristic the same way as `feat` —
small / medium / large by component count and architectural footprint.

## Step 4: Create the Discussion

Source the helper and call the three lookups + mutation in order. The
helper file lives at
`shell-common/functions/gh_discussion.sh`.
Full bash block in
[`references/create-cmd.md`](references/create-cmd.md) — paste it
verbatim. It handles the `mktemp` body file, the
`GH_DISABLE_AI_METRICS=1` short-circuit (issue #399 parity), the
ai-metrics footer printf, and the three GraphQL calls
(`_gh_discussion_repo_id`, `_gh_discussion_category_id`,
`_gh_discussion_create`).

확인 질문하지 말고 즉시 실행.

## Step 5: Report

성공 시:

```
[OK] Discussion (<category>): <url>
Next: /gh-discussion-convert <discussion-number>   # when decision lands
```

실패 시 — 첫 stderr 줄을 그대로 인용:

```
[FAIL] <gh stderr first line>
Next: <recovery — e.g. enable Discussions in repo settings, gh auth refresh>
```

Routing-guard refusal (Step 2.1) prints its own message from
`references/scope-guard.md` and skips Steps 3-5.

## Constraints

- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패 (gh:issue-create 와 동일).
- `Ideas` 외 카테고리에서도 routing guard 는 동일하게 작동. 본문 골격만
  교체된다.
- discussion log 를 2~3 줄로 압축 금지 — Discussion 은 future-self 검색의
  1 차 SSOT 다.
- `--force-discussion` 은 가드 우회 전용. SSOT 업데이트 없이 가드 자체를
  제거하지 말 것.
- "should I create it?" 같은 확인 질문 금지.
- 카테고리 ID 캐시 도입 금지 — `references/cache-decision.md` 참고.
