# Post-Create Mutations — gh:discussion-convert Steps 6-8

All three run **after** the Issue exists (Step 5). Each is best-effort:
a failure emits a warning but never rolls back the new Issue — the policy
invariant "Issue must exist with backlink" is already satisfied.

## Step 6: Board Sync (skip with `--no-board-sync`)

```
_gh_project_status_sync issue <M> "In progress" --only-from "Backlog,Ready"
```

The helper is a no-op on repos without a project board attached. The
`--only-from` whitelist prevents bouncing already-progressed cards back.
Reuses the same pattern as `gh:issue-implement` Step 3.4.

## Step 7: Post Backlink Comment (skip with `--no-comment`)

Compose the body:

```
Linked to issue #<M> -- decision tracked there.
```

Write it to a temp file and call `_gh_discussion_comment "$DISC_ID"
"$BODY_FILE"`. Mutation failure here is non-fatal — print a warning but
continue. The bidirectional backlink is best-effort once the forward link
(issue body -> discussion) is already on the Issue.

## Step 8: Close + Lock the Discussion

In order:

1. If `.closed != true` and `--no-close` is not set:
   `_gh_discussion_close "$DISC_ID" RESOLVED`.
2. If `.locked != true` and `--no-lock` is not set:
   `_gh_discussion_lock "$DISC_ID"`.

Both calls are best-effort — failures emit a warning but do not roll
back the new Issue. 확인 질문하지 말고 즉시 실행.
