# gh:discussion-create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | remote-name **or** category, or `-h`/`--help`/`help` | `origin` / `Ideas` | First non-flag positional. If it is one of `Ideas`, `Q&A`, `Announcements`, `Lessons`, treated as the category. Otherwise treated as the remote name. |
| 2 | the other one (remote or category) | (see above) | Second positional resolves whichever slot is still empty. |

Examples:

- `/gh-discussion-create` — `Ideas` Discussion on `origin`'s repo
- `/gh-discussion-create upstream` — `Ideas` Discussion on `upstream`'s repo
- `/gh-discussion-create Q&A` — `Q&A` Discussion on `origin`'s repo
- `/gh-discussion-create upstream Lessons` — `Lessons` Discussion on `upstream`
- `/gh-discussion-create -h` / `--help` / `help` — print this help

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--force-discussion` | off | Bypass the routing guard (Step 2.1) when the chat looks like a decided to-do but is actually RFC-shaped. The guard's reasoning is still printed once for the audit trail. |

## Env Vars

| Variable | Default | Description |
|----------|---------|-------------|
| `GH_DISABLE_AI_METRICS=1` | off | Skip the ai-metrics footer in the Discussion body. Mirrors the same env var honoured by `gh:issue-create` and the rest of the gh-* skill family (issue #399). |

## What the skill does

1. Confirms a git repo context and resolves `owner/repo` from the
   target remote's URL. Fails fast (no silent `origin` fallback) if
   the remote does not exist.
2. Picks a Discussion **category** — defaults to `Ideas` (RFC).
3. Runs the **routing guard**: refuses when the chat looks like a
   decided to-do (suggests `/gh-issue-create` instead). Override with
   `--force-discussion`.
4. Drafts an RFC-shaped body (TL;DR + Why + Goals/Non-Goals + Options
   + Alternatives + Open Questions). Q&A / Announcements / Lessons
   categories swap the body skeleton.
5. Looks up the repository node ID and category ID via GraphQL
   (`gh_discussion.sh`).
6. POSTs `createDiscussion` and prints the Discussion URL.

## Title format

Conventional commit-ish: `<type>[(<scope>)]: <한 줄 요약>`. For RFC
Discussions the type is usually `feat` or `refactor`. `Q&A` titles are
phrased as the question itself. `Announcements` titles start with
`announce: ...`. `Lessons` titles start with `lesson: ...`.

## Detail preservation

Same contract as `gh:issue-create`: do NOT over-compress. The
Discussion is reused later by `gh:discussion-convert` to seed an
issue body, by future-self search, and by `docs/guide/learnings/` promotion
(Lessons category). Preserve:

- concrete file paths and line references
- command outputs and error logs
- decisions and the reasoning behind them
- discussion log — never collapse to 2~3 bullets

A 200-line Discussion body is fine if the conversation warranted it.

## What the skill will NOT do

- Auto-create Discussion categories (the API does not allow it; the
  user must create categories in repo settings first).
- Apply the routing guard to user requests that already include
  `--force-discussion` (the override is the contract).
- Cache category IDs to disk — the lookup is one cheap GraphQL call;
  staleness risk > savings. See `references/cache-decision.md`.
- Fall back to `origin` when the user-specified remote is missing.
- Ask "should I create it?" — running the skill is the confirmation.
- Truncate or summarise the conversation log.

## Related skills

- [[gh-issue-create]] — sister skill for to-do Issues.
- [[gh-discussion-convert]] — Discussion -> Issue conversion + back-link.
- [[gh-issue-create-as-discussion]] — `--as-discussion` routing flag on
  the issue-create entry point (separate issue).
- SSOT: `docs/.ssot/discussions-policy.md` (issue #612).
