# Create the Issue — gh:discussion-convert Step 5

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
