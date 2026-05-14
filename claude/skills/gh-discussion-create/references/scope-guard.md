# Routing Guard — Issue vs Discussion

Step 2.1 safety net. Implements requirements F-3 + F-4 from issue #617:
prevent the `Ideas` Discussion bucket from accumulating decided to-do
items that should have been Issues, and surface ambiguity before the
mutation runs.

The SSOT principle is `docs/.ssot/discussions-policy.md` -> "운영 원칙
4 개조" #1: **Issue is default**. Discussion is for items that are too
early (RFC) or too late (announcement / lesson) to be tracked as
Issues.

## Trigger signals (decided-to-do)

If **any** of the following match the conversation, treat the chat as
a decided to-do and refuse with the format below. The user can override
with `--force-discussion`.

1. **Acceptance criteria are concrete and time-bound** — checklist with
   filenames, test names, or "by Friday" / "this week" / "before merge"
   markers.
2. **Implementation plan is finalised** — concrete file paths, function
   names, or commit messages drafted in the chat.
3. **Stakeholder/assignee already named** — "I will do this" / "@user
   takes this" / explicit ownership decided.
4. **PR/branch already exists or is implied next** — "let's open a PR"
   / "I'll push the branch" / "after merge".

## Trigger signals (ambiguous — clarify, do not refuse)

If the chat is RFC-shaped but **scope** is unclear, emit a short
clarification before calling the mutation. Mirrors
`gh-issue-create/references/clarification.md` triggers:

1. **동사 없는 명사 나열** — e.g. "사용자 관리 기능", "결제 시스템".
2. **컴포넌트 ≥ 3 혼재** — backend/frontend/CLI/skill all in one chat.
3. **Open Questions are missing** — every paragraph is a definitive
   statement. Discussions thrive on Open Questions; if the chat has
   none, ask the user to add one before posting.

## Refusal format (decided-to-do match)

```
이 대화는 결정된 to-do 로 보입니다 — Discussion 보다 Issue 가 적합합니다.

근거:
  - <signal that matched, e.g. "Acceptance criteria 5 개가 파일 경로로 명시됨">
  - <second signal if any>

권장:
  /gh-issue-create

그래도 Discussion 으로 등록하려면:
  /gh-discussion-create --force-discussion
```

After printing this, **stop** — do not call the mutation. Skip Steps
3-5 entirely. The user re-runs with the suggested command if they
agree, or with `--force-discussion` if they disagree.

## Clarification format (ambiguous match)

```
Discussion 등록 전에 한 가지만 확인:
- 이 RFC 의 핵심 Open Question 한 줄로 정리하면 무엇인가요?
```

Wait for the user to answer; do not call the mutation until they do.
Once answered, fold the answer into the body's "Open Questions"
section verbatim.

## No match -> no-op

If neither set of signals matches, this guide is silent. Continue to
Step 3.

## Why this guard is load-bearing

Without it, the SSOT routing principle erodes within weeks: every
"I am about to code X" chat would land in `Ideas`, the kanban-board-
free Discussions forum would silently become the de-facto issue
tracker, and `gh:discussion-convert`'s back-link audit chain would lose
its meaning. The guard is the mechanical enforcement of operating
principle #1.

If you are tempted to remove it, update `discussions-policy.md` first.
