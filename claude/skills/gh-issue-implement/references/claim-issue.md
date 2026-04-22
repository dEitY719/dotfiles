# gh:issue-implement — Claim Issue (Assignee)

## Purpose

Prevent two teammates from silently implementing the same issue at the
same time. Adding `@me` to the issue's assignee list broadcasts "I've
picked this up" on the GitHub issue page, in `gh issue list
--assignee @me`, and on issue-list badges.

## Command

```bash
gh issue edit <N> --repo "$TARGET_REPO" --add-assignee @me
```

Key properties:
- `--add-assignee` **adds** to the existing list; it does not overwrite
  existing assignees. Safe when a reviewer or collaborator is already
  assigned.
- Already assigned to `@me`? GitHub treats the re-add as a no-op — no
  error, no duplicate entry.

## Soft-fail rule

This step must **never** block the implementation flow. Possible
failure modes and responses:

| Failure | Response |
|---------|----------|
| No write permission on repo (fork, readonly token) | Warn, continue |
| GitHub API transient error / network | Warn, continue |
| Issue locked or archived | Warn, continue |
| `gh` not authenticated | Warn, continue (already caught in Step 3 if truly broken) |

Warning line format (single line, prefixed `⚠️`):

```
⚠️  Could not claim issue #<N> as assignee (<short reason>) — continuing anyway.
```

Do NOT print a multi-line stack trace. The warning is informational;
the implementation proceeds regardless.

## Placement rationale

The claim happens **after** the fetch + CLOSED check for two reasons:

1. A CLOSED issue is never implemented, so claiming it would pollute
   the assignee list for no reason.
2. Fetch already validates the issue number exists and `gh` is
   authenticated — the claim step can assume those hold and only needs
   to handle write-permission / concurrency failures.

It happens **before** Step 4 (mode dispatch) so the signal lands as
early as possible — even if `writing-plans` / `brainstorming` takes
minutes, teammates already see the claim.

## What this does NOT do

- Does not auto-unassign on failure in later steps. If implementation
  fails or the user abandons the branch, the assignee stays set — the
  human can clear it manually via `gh issue edit <N> --remove-assignee
  @me`. Auto-unassign was considered and rejected because:
  - Transient test failures shouldn't release the claim.
  - The user may want to resume the branch later.
  - Manual cleanup is a trivial one-liner.

- Does not block if someone else is already assigned. `--add-assignee`
  supplements rather than replacing, and the warning flow is reserved
  for genuine errors — not "someone else is also looking at this". The
  human can decide whether to coordinate via the issue thread.
