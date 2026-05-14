# gh:discussion-convert — Error Cases

Detailed error-handling matrix. SKILL.md keeps the happy-path
workflow scannable; the failure modes belong here.

## Step 1 — Repo resolution

| Trigger | User-facing output | Exit |
|---------|--------------------|------|
| Not inside a git repo | `Error: not inside a git repository` | 1 |
| Specified remote does not exist | List of available remotes via `git remote -v` + `Error: remote '<name>' not found.` | 1 |
| Remote URL is not GitHub | `Error: remote '<name>' is not a GitHub repository: <url>` | 1 |

Never fall back to `origin` silently — that masks typos and posts
into the wrong repo (mirrors `gh-discussion-create` failure rule).

## Step 2 — Fetch

| Trigger | Output | Exit |
|---------|--------|------|
| Discussion number not an integer | `[gh-discussion] discussion number must be a positive integer` | 2 |
| Discussion #N does not exist on repo | `[gh-discussion] discussion #N not found on owner/repo` + stderr trace | 1 |
| Auth failure | First stderr line from `gh api graphql` quoted verbatim | 1 |

## Step 3 — Category guard

| Trigger | Output | Exit |
|---------|--------|------|
| Discussion category is not `Ideas` and `--force-category` not set | `Discussion #N 카테고리가 '<X>' 입니다 — 정책상 Ideas 만 변환합니다. ...` (multiline refusal per SKILL.md Step 3) | 1 |

The refusal text intentionally cites
`docs/.ssot/discussions-policy.md` operating principle #2 so the
audit trail explains the policy decision, not just the mechanical
rejection.

## Step 4 — Idempotency

| Trigger | Output | Exit |
|---------|--------|------|
| Existing Issue with backlink found | `[OK] Discussion #N already converted to <url>` | 0 |
| `gh issue list --search` fails (rate limit / auth) | Warn `[WARN] idempotency search failed -- proceeding may create a duplicate Issue` + continue | — |

The skill prefers a possible duplicate over blocking the user when
search itself fails — humans can dedupe; a silent abort would leave
no Issue at all.

## Step 5 — Issue creation

| Trigger | Output | Exit |
|---------|--------|------|
| `gh issue create` fails | First stderr line quoted + `[FAIL] Step 5: gh issue create -- aborting before mutating the Discussion.` | 1 |
| Title exceeds GitHub's 256-char limit | Caller-side check: truncate to 250 chars + `...` and emit `[WARN] title truncated to fit GitHub limit` | — |

Crucially, Steps 6 / 7 / 8 are NOT run when Step 5 fails. Mutating
the Discussion (close / lock / comment) without a new Issue would
violate the policy invariant. Abort cleanly instead.

## Step 6 — Board sync

| Trigger | Output | Exit |
|---------|--------|------|
| Repo has no project board attached | Helper is a no-op, no output | — |
| Status field has no `In progress` option | Helper warns once and exits 0 | — |
| Mutation fails (rate limit, etc.) | Helper warns; skill continues to Step 7 | — |

Board sync is the most flake-prone step in this skill; it is
deliberately best-effort.

## Step 7 — Backlink comment

| Trigger | Output | Exit |
|---------|--------|------|
| `addDiscussionComment` fails | `[WARN] discussion comment failed -- continuing` + stderr trace | — |

The Issue already carries the forward backlink (Step 5), so the
reverse comment is best-effort. The user can paste it manually if
the mutation keeps failing.

## Step 8 — Close + Lock

| Trigger | Output | Exit |
|---------|--------|------|
| `closeDiscussion` fails | `[WARN] discussion close failed -- continuing` + stderr trace | — |
| `lockLockable` fails | `[WARN] discussion lock failed -- continuing` + stderr trace | — |
| Discussion is already closed (`.closed == true`) | Skip the close mutation; report `close=skip` in Step 9 | — |
| Discussion is already locked (`.locked == true`) | Skip the lock mutation; report `lock=skip` in Step 9 | — |

The pre-state checks prevent a "no-op mutation" stderr noise when
the user re-runs the skill against a Discussion that was previously
closed and locked by hand.

## Auth failures (any step)

If `gh api graphql` returns `HTTP 401` or the body contains
`Bad credentials`, suggest:

```
[FAIL] GitHub auth failed -- run `gh auth refresh` and retry.
```

Map this consistently across all steps so the user sees one
recovery hint regardless of where the auth failure surfaced.
