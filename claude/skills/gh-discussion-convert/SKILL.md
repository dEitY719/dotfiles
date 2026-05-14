---
name: gh:discussion-convert
description: >-
  Promote a decided `Ideas` Discussion into a tracked Issue by emulating
  GitHub's UI `Convert to issue` flow — creates the Issue with an
  `Originated from discussion #<N>` backlink, posts a `Linked to issue
  #<M>` comment back on the Discussion, locks the Discussion (reason
  Resolved), closes it, and moves the new Issue card to `In progress`
  on the project board. Use when the user runs /gh:discussion-convert,
  /gh-discussion-convert, asks "Discussion #N 결정났으니 issue 로
  승격", "RFC 결정 — convert 해줘", or wants the 4-step variant from
  `discussions-policy.md` (#612) automated end-to-end. Sister skill of
  [[gh-discussion-create]]; reuses the same `gh_discussion.sh` helpers.
  Idempotent — re-running on a Discussion that was already converted
  prints the existing issue URL and exits 0. Refuses non-`Ideas`
  categories unless `--force-category` is set. Accepts `<N>` plus
  optional `[remote]`, and `--no-comment` / `--no-lock` /
  `--no-board-sync` / `--no-close` to skip the optional steps.
  `-h`/`--help`/`help` prints usage.
allowed-tools: Bash, Read, Grep
---

# gh:discussion-convert — Decided Ideas Discussion -> Issue

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Automate the 4-step `Discussion -> Issue` 변환 규약 from
`docs/.ssot/discussions-policy.md` (#612). The native UI button is the
only first-party path GitHub exposes — there is no public REST or
GraphQL `convertDiscussion` mutation as of 2026-05. This skill emulates
the UI path via four primitive mutations (`createIssue` +
`addDiscussionComment` + `closeDiscussion` + `lockLockable`) plus a
board-status sync, all wired together so the policy's bidirectional
backlink invariant (operating principle #4) never gets dropped.

Print the new Issue URL at the end. Idempotent — see Step 4.

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `<discussion-number>` (positional, required) | Positive integer. | — |
| `[remote]` (positional) | Git remote whose repo owns the Discussion + new Issue. | `origin` |
| `--no-comment` | Skip the `Linked to issue #<M>` backlink comment on the Discussion. | off |
| `--no-lock` | Skip the `Lock conversation` step. | off |
| `--no-close` | Skip the close step (Discussion stays open). | off |
| `--no-board-sync` | Skip the `In progress` Status transition on the project board. | off |
| `--force-category` | Bypass the Step 3 `Ideas`-only guard. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Suppress ai-metrics handling (parity with [[gh-discussion-create]]). | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` for elapsed-time reporting. Parse the
positional args and flags above. Confirm we are in a git repo
(`git rev-parse --show-toplevel`) and resolve
`TARGET_REPO=<owner>/<repo>` via the chosen remote — substeps in
[`references/repo-resolution.md`](references/repo-resolution.md).
Never silently fall back to `origin` when the user-supplied remote
is missing.

## Step 2: Fetch the Discussion

Source `shell-common/functions/gh_discussion.sh` and call
`_gh_discussion_fetch "$_owner" "$_repo" "$N"`. Capture the JSON to
a temp file and read these fields with `jq`:

- `.id` (node ID — needed for comment / close / lock mutations)
- `.number`, `.title`, `.body`, `.url`
- `.category`, `.closed`, `.locked`

Fetch failure -> abort with the helper's stderr trace.

## Step 3: Category Guard

If `.category != "Ideas"` and `--force-category` is not set, refuse:

```
Discussion #<N> 카테고리가 '<X>' 입니다 — 정책상 Ideas 만 변환합니다.
근거: docs/.ssot/discussions-policy.md -> "운영 원칙 4 개조" #2.
강제 변환하려면: /gh-discussion-convert <N> --force-category
```

Exit 1. Skip Steps 4-8 entirely. Operating principle #2 ("결정되면
즉시 Issue convert") refers specifically to the Ideas bucket; other
categories have different lifecycles (Announcements = transient,
Lessons = Discussion-first, Q&A = answered-not-converted) and must
not be silently coerced into the Issue tracker.

## Step 4: Idempotency Check

Search for an Issue whose body already contains the backlink marker:

```bash
EXISTING=$(gh issue list --repo "$TARGET_REPO" --state all --search \
    "in:body \"Originated from discussion #${N}\"" \
    --json number,url --limit 1 --jq '.[0]')
```

If `$EXISTING` is non-empty, print the existing issue URL and exit 0
with `[OK] Discussion #<N> already converted to <issue-url>`. This
preserves NF-1 (idempotency) even when the previous run posted a
comment / locked / closed and the user re-invokes the skill.

Step 4 happens BEFORE any mutation; a re-run never creates a second
issue.

## Step 5: Create the Issue

Build the Issue body as backlink + a newline + the original Discussion
body (verbatim, including the source's ai-metrics footer — we are not
the author of that footer, so we preserve it as-is):

```
Originated from discussion #<N>

<original discussion body>
```

Title: the Discussion title verbatim (preserve the conventional-commit
prefix). Create via `gh issue create --repo "$TARGET_REPO" --title ...
--body-file ...`. Capture the printed URL and extract `<M>`.

`gh issue create` is preferred over a raw `createIssue` GraphQL call
because it handles the owner -> repository node ID lookup, default
assignee + label policy, and prints a stable URL. Fits the existing
gh-* skill family.

## Step 6: Board Sync (skip with `--no-board-sync`)

```
_gh_project_status_sync issue <M> "In progress" --only-from "Backlog,Ready"
```

The helper is a no-op on repos without a project board attached. The
`--only-from` whitelist prevents bouncing already-progressed cards
back. Reuses the same pattern as `gh:issue-implement` Step 3.4.

## Step 7: Post Backlink Comment (skip with `--no-comment`)

Compose the body:

```
Linked to issue #<M> -- decision tracked there.
```

Write it to a temp file and call `_gh_discussion_comment "$DISC_ID"
"$BODY_FILE"`. Mutation failure here is non-fatal — print a warning
but continue. The bidirectional backlink is best-effort once the
forward link (issue body -> discussion) is already on the Issue.

## Step 8: Close + Lock the Discussion

In order:

1. If `.closed != true` and `--no-close` is not set:
   `_gh_discussion_close "$DISC_ID" RESOLVED`.
2. If `.locked != true` and `--no-lock` is not set:
   `_gh_discussion_lock "$DISC_ID"`.

Both calls are best-effort — failures emit a warning but do not roll
back the new Issue (the policy invariant "Issue must exist with
backlink" is already satisfied by Steps 5 + 7).

확인 질문하지 말고 즉시 실행.

## Step 9: Report

Print exactly one line on success:

```
[OK] Discussion #<N> -> Issue #<M>: <issue-url>
```

Append a single-line summary of optional steps applied / skipped so
the user can tell at a glance which side-effects ran:

```
  steps: comment=<on|off|skip>, lock=<on|off|skip>, close=<on|off|skip>, board=<synced|skipped>
```

On failure -- show the failing step name and quote the first stderr
line from the helper, mirroring the format used by
[[gh-discussion-create]] Step 5.

## Constraints

- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패. Silent `origin` fallback 금지.
- Non-Ideas 카테고리는 정책상 변환 대상이 아니다. `--force-category`
  는 SSOT 갱신 없이 가드 자체를 제거하는 것이 아니라 1 회용 우회 전용.
- Steps 5 (createIssue) 이후 mutation 들 (6/7/8) 은 best-effort.
  하나 실패해도 새 Issue 는 이미 backlink 를 가진 채 존재하므로
  롤백 시도 금지 — 사람이 보강하도록 경고만 출력한다.
- 두 번 호출해도 새 Issue 가 두 개 생기지 않는다 (Step 4 idempotency
  check). 단, Discussion 본문이 backlink 마커 인덱싱 전에 호출되면
  중복이 가능 — 그래도 인간 검토가 마지막 방어선.
- "should I convert?" 같은 확인 질문 금지. Skill 실행이 컨펌이다.
