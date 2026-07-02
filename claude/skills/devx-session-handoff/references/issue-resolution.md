# devx:session-handoff — Tracking-issue Resolution (Step 2)

## Priority chain

Evaluate in order; the first hit wins. `--new-issue` skips straight to
"Create a new tracking issue" below.

1. **Explicit argument** — `[issue-number]` passed by the user. Validate it
   exists and is OPEN via `gh issue view <N> --repo "$TARGET_REPO" --json
   state,title` (the gh:issue-read fetch shape). CLOSED → warn and continue
   down the chain (a closed issue is a finished thread, not a live handoff
   target) unless the user insists.
2. **Conversation mentions** — scan this session for `#N` / `Issue #N` /
   issue URLs. Count references per issue number; the most-referenced OPEN
   issue is the candidate.
3. **Branch name** — `git branch --show-current` matching `wt/issue-N-*`,
   `wt/issue-N/*`, or `issue-N` extracts `N`.
4. **Recent gh activity** — `gh issue list --repo "$TARGET_REPO" --assignee
   @me --state open --limit 5`; if exactly one is plausibly this session's
   work (title matches the task), use it.

## Multiple candidates

When steps 2–4 surface more than one plausible issue, pick the one with the
most conversation references. On a tie — or when none clearly matches the
session's actual work — ask the user one short line listing the candidates
instead of guessing. A handoff on the wrong issue misleads the next session.

## No candidate — judge

No issue found anywhere. Decide by the nature of the session's work:

- **Substantive multi-session work** (an implementation mid-way, a design
  with open decisions, anything the next session must continue): create a
  new tracking issue via `Skill(gh:issue-create)` and use its number. The
  handoff comment then becomes that issue's first status record.
- **Trivial or nearly-done work** (small fix awaiting review, exploration
  with no follow-up): degrade to `--memory-only` and say so in the report.
  Creating an issue nobody will reopen is noise.

`--memory-only` given explicitly always wins over issue creation.

## Duplicate-handoff guard

Before posting, inspect the most recent comments:

```bash
gh issue view <N> --repo "$TARGET_REPO" --json comments \
  -q '.comments[-3:][] | {author: .author.login, body: .body[0:120], url: .url}'
```

If a comment authored by `@me` in THIS session already carries the handoff
marker (`<!-- session-handoff -->`, embedded by the template), update that
comment (`gh api --method PATCH` on the comment id with the new body)
instead of appending a second one. Two handoffs from one session force the
next reader to diff them.

## Failure modes

- GitHub unreachable AND no `--memory-only`: HARD-stop and ask — posting is
  the skill's core outward action; silently degrading it hides the failure.
- GitHub unreachable WITH `--memory-only`: proceed; nothing needed the API.
- `gh:issue-create` sub-skill fails: warn, degrade to memory-only, report
  `posted=none (fallback)`.
