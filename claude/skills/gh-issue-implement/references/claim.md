# gh:issue-implement — Step 3 Fetch + Claim

This file is the SSOT for Step 3 of `gh:issue-implement`. The skill
absorbs four session-start tasks that AgentToolbox handles in
`claude-enter-issue` (worktree creation stays the user's job; everything
else lands here):

1. Block-label guard (fail-closed abort).
2. Self-assign (`@me`).
3. Project board Status transition (`In progress`).
4. `Depends on #M` cross-issue check.

## Substep order — why this sequence

```
3.1 Fetch issue              (gates everything; CLOSED refusal here)
3.2 Block-label guard        (HARD abort; cheapest "no" — never write to
                              an issue we won't work on)
3.3 Self-assign              (broadcast claim ASAP, before mode dispatch)
3.4 Board Status transition  (idempotent; verify-pair absorbs race)
3.5 Depends-on guard         (slowest — N+1 issue lookups; do last and
                              soft-warn so blockers learned mid-loop
                              don't undo the claim)
```

The HARD aborts (3.1, 3.2) come before any mutation (3.3, 3.4) so an
abort never leaves a stale claim or board state.

## Substep detail

### 3.1 Fetch issue

See `references/fetch-issue.md`. The `gh issue view` JSON it returns is
reused by 3.2 (`labels`), 3.3 (`assignees`), 3.5 (`body`) — call once,
parse multiple times.

### 3.2 Block-label guard (fail-closed)

**Goal**: refuse to start work on an issue tagged `do-not-work`,
`on-hold`, `보류`, `⏸️ Postpone`, or whatever the team's parking-lot
label happens to be. AgentToolbox `#233` policy: no escape hatch
(`GH_ISSUE_FORCE_BLOCKED=1` was rejected) — label removal is the only
way to release. dotfiles inherits that posture.

**Algorithm** (operates on the JSON from 3.1):

```
labels = json.labels[].name
block  = split(GH_ISSUE_BLOCK_LABELS, ",")
        default: "do-not-work,on-hold,보류,⏸️ Postpone,reference"

for L in labels:
    for B in block:
        if L == B:
            print "Refusing to start #<N> — blocked by label '<L>'."
            print "  Remove the label and re-run, or check whether"
            print "  the issue should stay parked."
            exit 2
```

**Why exit 2 and not 1**: `1` is the implicit failure code for many
shell errors. `2` is reserved across this skills suite for "policy
refusal" (mirrors `_gh_project_status_sync`'s Approved guard return
code). A wrapper script can distinguish "the skill broke" from "the
skill correctly refused".

### 3.3 Self-assign

**Goal**: broadcast on the issue page, in `gh issue list --assignee
@me`, and on issue-list badges that this issue is being worked.

**Algorithm**:

```
me        = `gh api user -q .login`
assignees = json.assignees[].login

if "GH_ISSUE_SKIP_SELF_ASSIGN" set:
    return 0

if me in assignees:
    return 0    # idempotent no-op

if assignees == []:
    gh issue edit <N> --repo <repo> --add-assignee @me
    return 0    # soft-fail on API error: warn + continue

# Someone else already holds it.
print "[WARN] Issue #<N> is assigned to <other>; not overriding."
print "    Coordinate via the issue thread, or rerun with"
print "    GH_ISSUE_SKIP_SELF_ASSIGN=1 to suppress this warning."
return 0
```

**Why `--add-assignee` not `--assignee`**:
- `--add-assignee` *appends* to the existing list. Safe when a reviewer
  is already assigned.
- `--assignee` *replaces* the list — would silently boot the prior
  assignee. Never use it here.

**Why warn-no-override on conflict**: forking a teammate's claim is
worse than a duplicated implement attempt. The warning gives the human
a chance to coordinate; AgentToolbox `claude-enter-issue` takes the
same posture.

**Soft-fail rule**: any of these failures → single-line `[WARN]` warning
+ continue:
- No write permission on repo (fork, readonly token).
- Transient API / network error.
- Issue locked or archived.

The implement flow proceeds — the claim is informational, not load-
bearing.

### 3.4 Board Status transition

**Goal**: move the issue card from `Backlog`/`Ready` to `In progress`
on every projectV2 it belongs to.

**Algorithm**:

```
if "GH_ISSUE_SKIP_BOARD_TRANSITION" set:
    return 0

_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        # Defense-in-depth (#724): sourceable but undefined → silent no-op
        # without this guard. One-line stderr warning, never blocks.
        printf '[gh-issue-implement] %s sourced but _gh_project_status_sync undefined — board transition skipped (#724).\n' \
            "$_HELPER" >&2
    else
        _gh_project_status_sync issue <N> "In progress" --only-from "Backlog,Ready"
    fi
fi
```

The helper (`shell-common/functions/gh_project_status.sh`) handles:

- **No-board repos**: returns 0 silently when the issue belongs to no
  projectV2.
- **`--only-from` whitelist**: `Backlog,Ready` — never bounces an
  already-`In review` / `Done` card backwards. Other custom columns
  (`In design`, `Spec`, etc.) are left untouched; teams that want
  those moved should override the helper or skip with
  `GH_ISSUE_SKIP_BOARD_TRANSITION=1` and run the transition manually.
- **Verify pair (race absorption, #393)**: after the mutation the
  helper sleeps `_GH_PROJECT_STATUS_VERIFY_SLEEP` (default 1 s) and
  re-queries. Re-issues the mutation once if a builtin workflow
  reverted the value. Second mismatch → loud stderr, still rc 0.

**Soft-fail rule**: helper always returns 0 for non-policy errors —
the implement flow proceeds regardless of board state.

### 3.5 Depends-on guard

**Goal**: warn the user when the issue body mentions `Depends on #M`
and `M` is still OPEN. AgentToolbox `claude-check-deps` is fail-closed
(refuses to start). dotfiles is **soft** because:

- The reference may already be stale (M was closed but the body wasn't
  updated).
- The user may legitimately want to start scaffolding on top of an
  in-flight dependency (stacked work).
- A hard refusal here would frustrate users in repos that don't enforce
  the pattern.

A loud warning is enough — the user can abort with Ctrl-C if relevant.

**Algorithm**:

```
if "GH_ISSUE_SKIP_DEPS_CHECK" set:
    return 0

deps = grep -oE '(?i)Depends on #[0-9]+' <issue-body> | sed 's/.*#//'

for M in deps:
    state = `gh issue view <M> --repo <repo> --json state -q .state`
    if state == "CLOSED":
        continue
    print "[WARN] Issue #<N> depends on #<M> which is still <state>."
    print "    The implement may be premature — review or close #<M> first."
```

Pattern is case-insensitive ("Depends on", "depends on", "DEPENDS
ON" all match). Only matches whole `#<digits>` — not `#dep-3` or
`#1.2.3`.

**Failure mode**: if `gh issue view <M>` itself errors (deleted issue,
cross-repo reference, network), print one warn line and continue. Do
not abort — the dependency check is informational.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone,reference` | Comma-separated block-label list for 3.2. Spaces inside a label are part of the label (don't pad commas). `reference` marks 참고용/구현 불필요 issues (issue #1226). |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 3.3 entirely. |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 3.4 entirely. |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 3.5 entirely. |

There is **no** env var to bypass 3.2 (block-label guard). That is
intentional — see "Block-label guard (fail-closed)" above.

## Behavior matrix

| Case | 3.2 block | 3.3 self-assign | 3.4 board | 3.5 deps | Net |
|---|---|---|---|---|---|
| Normal (board, unassigned, deps OK) | pass | add `@me` | `In progress` (verified) | OK | proceed |
| Block-label attached | **abort exit 2** | n/a | n/a | n/a | refuse |
| Already self-assigned | pass | no-op | `In progress` | OK | proceed |
| Assigned to another user | pass | warn + skip | `In progress` | OK | proceed |
| Dependency `#M` OPEN | pass | add `@me` | `In progress` | warn | proceed |
| No board attached | pass | add `@me` | silent skip | OK | proceed |
| `GH_ISSUE_SKIP_SELF_ASSIGN=1` | pass | skip | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_BOARD_TRANSITION=1` | pass | add `@me` | skip | OK | proceed |
| `GH_ISSUE_SKIP_DEPS_CHECK=1` | pass | add `@me` | `In progress` | skip | proceed |

## Placement rationale (why Step 3, not earlier or later)

- **After Step 1 preconditions**: claiming an issue while the working
  tree is dirty would force a rollback if Step 5 can't proceed.
- **After Step 2 superpowers detection**: mode dispatch happens in
  Step 4 — the claim must already exist so a long brainstorming
  session doesn't leave teammates wondering whether the issue is being
  worked.
- **Before Step 4 mode dispatch**: `writing-plans` / `brainstorming`
  can take many minutes; the assignee badge needs to be live before
  that.
- **Before Step 5 implement**: a board card stuck in `Backlog` while
  edits are landing is exactly the inconsistency this absorption fixes.

## What this does NOT do

- **Does not create a worktree.** `gh:issue-implement`'s precondition
  still requires the user to be in a feature branch + worktree.
- **Does not auto-unassign on later failure.** If Step 5's test loop
  exhausts, the assignee + board state stay set. Manual cleanup is
  one line each:
  - `gh issue edit <N> --remove-assignee @me`
  - move the card back to `Backlog` on the project board.
- **Does not enforce stacked-PR `Depends on #parent-pr`.** Only issue
  references are scanned. PR-to-PR stacking is `gh:pr`'s territory.

## Test fixture

`tests/bats/skills/_fixtures/gh_issue_implement_claim.sh` mirrors
the four substep functions verbatim. The bats suite at
`tests/bats/skills/gh_issue_implement_claim.bats` exercises the
seven-case behavior matrix above. Any change to substep logic must
land in both files (and this doc).
