# gh:issue-proceed — Step 2.1 Fetch + Claim

Five substeps in order. This mirrors `/gh:issue-implement`'s claim policy
(kept as a self-contained copy per the dotfiles per-skill references
convention). Worktree creation stays the user's job; everything else
lands here.

## Substep order

```
2.1.1 Fetch issue              (gates everything; CLOSED refusal here)
2.1.2 Block-label guard        (HARD abort exit 2; cheapest "no")
2.1.3 Self-assign              (broadcast claim ASAP)
2.1.4 Board Status transition  (idempotent; verify-pair absorbs race)
2.1.5 Depends-on guard         (slowest; soft-warn, do last)
```

The HARD aborts (2.1.1, 2.1.2) come before any mutation (2.1.3, 2.1.4) so
an abort never leaves a stale claim or board state.

## 2.1.1 Fetch issue

See `references/fetch-issue.md`. The `gh issue view` JSON it returns is
reused by 2.1.2 (`labels`), 2.1.3 (`assignees`), 2.1.5 (`body`), and Step
2.2 schema validation (`body`) — call once, parse multiple times.

## 2.1.2 Block-label guard (fail-closed)

Refuse to proceed on an issue tagged `do-not-work`, `on-hold`, `보류`,
`⏸️ Postpone`, or whatever `GH_ISSUE_BLOCK_LABELS` lists. No escape hatch —
label removal is the only release.

```
labels = json.labels[].name
block  = split(GH_ISSUE_BLOCK_LABELS, ",")   # default above
for L in labels:
    if L in block:
        print "Refusing to start #<N> — blocked by label '<L>'."
        exit 2
```

`exit 2` is reserved suite-wide for "policy refusal" (distinct from `1`,
the implicit shell-error code).

## 2.1.3 Self-assign

```
me        = gh api user -q .login
assignees = json.assignees[].login
if GH_ISSUE_SKIP_SELF_ASSIGN set: return 0
if me in assignees:               return 0   # idempotent
if assignees == []:
    gh issue edit <N> --repo <repo> --add-assignee @me   # soft-fail on API error
    return 0
print "[WARN] Issue #<N> is assigned to <other>; not overriding."
return 0
```

`--add-assignee` appends (never `--assignee`, which replaces). Forking a
teammate's claim is worse than a duplicated attempt — warn, don't override.

## 2.1.4 Board Status transition

```
if GH_ISSUE_SKIP_BOARD_TRANSITION set: return 0
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
[ -r "$_HELPER" ] && . "$_HELPER"
command -v _gh_project_status_sync >/dev/null 2>&1 \
  && _gh_project_status_sync issue <N> "In progress" --only-from "Backlog,Ready"
```

No-board repos → silent rc 0. `--only-from Backlog,Ready` never bounces an
`In review` / `Done` card backwards. Soft-fail: any non-policy error → rc 0.

## 2.1.5 Depends-on guard (soft)

```
if GH_ISSUE_SKIP_DEPS_CHECK set: return 0
deps = grep -oEi 'Depends on #[0-9]+' <body> | sed 's/.*#//'
for M in deps:
    state = gh issue view <M> --repo <repo> --json state -q .state
    [ "$state" != CLOSED ] && print "[WARN] #<N> depends on #<M> (still <state>)."
```

Soft (warn + continue): the reference may be stale, or the user may be
scaffolding on an in-flight dependency. A `gh issue view <M>` error itself
→ one warn line + continue.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone` | Block-label list for 2.1.2. |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 2.1.3. |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 2.1.4. |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 2.1.5. |

There is **no** env var to bypass 2.1.2 (block-label guard) — intentional.

## What this does NOT do

- **Does not create a worktree** — the precondition class (mutation-required)
  still requires the user to be on a feature branch in a worktree
  (`references/preconditions.md`).
- **Does not auto-unassign on later abort.** If Step 3 aborts, the assignee
  + board state stay set. Manual cleanup: `gh issue edit <N>
  --remove-assignee @me` and move the card back on the board.
