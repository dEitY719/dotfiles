# gh:discussion-convert — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<discussion-number>` **or** `-h`/`--help`/`help` | (required) | Positive integer — the Ideas Discussion to convert. |
| 2 | `[remote]` | `origin` | Git remote whose repo owns the Discussion and the new Issue. |

Examples:

- `/gh-discussion-convert 42` — convert Discussion #42 on `origin`.
- `/gh-discussion-convert 42 upstream` — convert on `upstream`.
- `/gh-discussion-convert 42 --no-comment --no-lock` — create the
  Issue with the backlink only; leave the Discussion open and silent.
- `/gh-discussion-convert -h` / `--help` / `help` — print this help.

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--no-comment` | off | Skip Step 7 (`Linked to issue #<M>` comment back on the Discussion). The reverse backlink is then human-maintained. |
| `--no-lock` | off | Skip Step 8.2 (`Lock conversation` with reason Resolved). |
| `--no-close` | off | Skip Step 8.1 (`closeDiscussion` mutation). Use when the Discussion should stay open for follow-up. |
| `--no-board-sync` | off | Skip Step 6 (`In progress` Status transition on the project board). |
| `--force-category` | off | Bypass the Step 3 `Ideas`-only guard. Required to convert Q&A / Announcements / Lessons Discussions — policy normally forbids it. |

## Env Vars

| Variable | Default | Description |
|----------|---------|-------------|
| `GH_DISABLE_AI_METRICS=1` | off | Suppress ai-metrics handling (parity with `gh:discussion-create`). |
| `GH_PROJECT_STATUS_SYNC=0` | on | Skip board sync globally (honored by the underlying `_gh_project_status_sync` helper). |

## What the skill does

1. Confirms a git repo context and resolves `owner/repo` from the
   target remote.
2. Fetches the Discussion via `_gh_discussion_fetch` (single GraphQL
   call) and extracts node ID + body + category + locked/closed state.
3. **Category guard** — refuses non-`Ideas` Discussions unless
   `--force-category` is set. Override is one-shot, not a policy
   change.
4. **Idempotency check** — searches existing Issues for a body match
   on `Originated from discussion #<N>`. If found, prints the existing
   Issue URL and exits 0 without mutating anything.
5. Creates the new Issue with the backlink prepended to the original
   Discussion body, preserving the conventional-commit title.
6. Moves the new Issue card to `In progress` on the project board
   (best-effort; no-op on repos without a board).
7. Posts a `Linked to issue #<M> -- decision tracked there.` comment
   back on the Discussion.
8. Closes the Discussion (`closeDiscussion` reason RESOLVED) and locks
   it (`lockLockable` reason RESOLVED).

Steps 6 / 7 / 8 are best-effort — Step 5 alone satisfies the policy
invariant that the new Issue must carry the backlink.

## Bidirectional-backlink contract

`docs/.ssot/discussions-policy.md` operating principle #4 mandates
two-way links between the converted Discussion and the new Issue.
This skill enforces that contract mechanically:

- **Issue -> Discussion**: Step 5 prepends `Originated from
  discussion #<N>` to the Issue body. This direction is **not
  optional** — there is no flag to disable it.
- **Discussion -> Issue**: Step 7 adds `Linked to issue #<M>` as a
  comment. This direction can be disabled with `--no-comment` when
  the user prefers to maintain it manually (e.g. consolidating
  multiple converted Discussions into one tracking comment).

## What the skill will NOT do

- Convert non-`Ideas` Discussions without `--force-category` — by
  policy, Announcements / Q&A / Lessons have different lifecycles.
- Try to use a hypothetical `convertDiscussion` REST or GraphQL
  endpoint — none exists as of 2026-05. The skill emulates the UI
  flow via four primitive mutations.
- Roll back the new Issue if a later step fails. Once the Issue
  carries the backlink (Step 5), the SSOT chain is intact; lock /
  close / comment failures are warnings, not aborts.
- Create a duplicate Issue when run twice (Step 4 idempotency check).
- Re-categorise the Discussion or move it to another repo.
- Fall back to `origin` when the user-specified remote is missing.
- Ask "should I convert?" — running the skill is the confirmation.

## Related skills

- [[gh-discussion-create]] — sister skill that creates the Discussion
  in the first place. Same helper module (`gh_discussion.sh`).
- [[gh-issue-create]] — default destination for to-do items; preferred
  over Discussion when the chat is already a decided to-do.
- SSOT: `docs/.ssot/discussions-policy.md` (#612).
