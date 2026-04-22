# gh:pr-merge — Strategy Selection

## Default: `rebase`

Matches the "Rebase and merge" button the user clicks on GitHub web.
Produces linear history, no merge commits, preserves individual commit
messages.

## When the repo disables a strategy

GitHub repo settings can disable strategies. If `gh pr merge` fails with
`Pull request merge method is not allowed`, stop and report:

```
PR #<N> merge failed: <strategy> is disabled on this repo.
Allowed strategies (check repo settings > General > Pull Requests):
  - Allow merge commits
  - Allow squash merging
  - Allow rebase merging
```

Do NOT silently switch strategies.

## Strategy → flag mapping

| Strategy | gh flag |
|---|---|
| rebase | `--rebase` |
| squash | `--squash` |
| merge | `--merge` |

## Pre-flight JSON fields

```bash
gh pr view <N> --repo "$TARGET_REPO" --json \
  number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,\
  baseRefName,headRefName,author
```

## Hard-stop decisions

| Field | Value → Stop reason |
|---|---|
| `state` | `!= OPEN` → "PR already <closed\|merged>" |
| `isDraft` | `true` → "draft PR — mark ready first" |
| `mergeable` | `CONFLICTING` → "resolve conflicts first" |
| `reviewDecision` | `!= APPROVED` → "not approved — use /gh-pr-emergency-merge for admin bypass" |

## Required checks

```bash
gh pr checks <N> --repo "$TARGET_REPO" --required
```

Any row with conclusion `FAILURE` or status `IN_PROGRESS`/`QUEUED` → stop.
Only proceed when all required checks are `SUCCESS`.

## Post-merge SHA fetch

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

## Final report format

```
PR #<N> merged (<strategy>)
  Merge SHA:  <sha>
  Branch:     <headRefName> → <baseRefName> (deleted)
  URL:        <pr-url>
```
