# gh:issue-implement — Step 3 Fetch + Claim

This file is the SSOT for Step 3 of `gh:issue-implement`. The skill
absorbs four session-start tasks that AgentToolbox handles in
`claude-enter-issue` (worktree creation stays the user's job; everything
else lands here):

1. Block-label guard (fail-closed abort).
2. Self-assign (`@me`).
3. Project board Status transition (`In progress`).
4. `Depends on #M` cross-issue check.

On top of those it adds one dotfiles-native guard AgentToolbox has no
equivalent for — the duplicate-attempt detector of 3.3b (issue #1507).

## Substep order — why this sequence

```
3.1  Fetch issue              (gates everything; CLOSED refusal here)
3.2  Block-label guard        (HARD abort; cheapest "no" — never write to
                              an issue we won't work on)
3.3  Self-assign              (broadcast claim ASAP, before mode dispatch)
3.3b Duplicate open-PR guard  (soft warn; runs once the claim is out there
                              but before the board is touched)
3.4  Board Status transition  (idempotent; verify-pair absorbs race)
3.5  Depends-on guard         (slowest — N+1 issue lookups; do last and
                              soft-warn so blockers learned mid-loop
                              don't undo the claim)
```

The HARD aborts (3.1, 3.2) come before any mutation (3.3, 3.4) so an
abort never leaves a stale claim or board state.

**Why 3.3b sits between 3.3 and 3.4**: not earlier than 3.3, because it
costs a search API call and there is no point paying for it on an issue
3.2 is about to refuse; not later than 3.4, so the warning reads against
the board's pre-run state rather than mixed in with this run's own
`In progress` write.

## Substep detail

> **Host targeting (#1403)** — every `gh` call in this file runs as
> `GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`, using the pair Step 1
> bound from one and the same remote URL (`references/repo-resolution.md`).
> Step 1 also `export`s `GH_HOST`, which is what carries the host into
> `gh_project_status.sh` in 3.4 — that helper calls `gh` itself and has no
> other way to learn the host. Dropping either half sends the write to the
> wrong GitHub server without an error.

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

**Goal**: broadcast on the issue page, in `gh issue list --repo "$TARGET_REPO"
--assignee @me`, and on issue-list badges that this issue is being worked.

**Algorithm**:

```
me        = `GH_HOST="$TARGET_HOST" gh api user -q .login`
assignees = json.assignees[].login

if "GH_ISSUE_SKIP_SELF_ASSIGN" set:
    return 0

if me in assignees:
    return 0    # idempotent no-op

if assignees == []:
    GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO" --add-assignee @me
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

### 3.3b Duplicate open-PR guard (soft)

**Goal**: catch the case 3.3 structurally cannot — *I* am already the
assignee because *another one of my own sessions* claimed this issue
minutes ago from a sibling worktree. To 3.3 that is indistinguishable
from a plain restart, so it returns `noop-self` and says nothing. Issue
#1482 was implemented twice, 13 minutes apart, producing PRs #1488 and
#1489 that later collided in a merge train.

The reliable fingerprint of "someone already did this" is an **open PR
that closes this issue**. Read-only, one search call, one warning line.
It never blocks: a second session is sometimes exactly what the user
wants (a rewrite, an abandoned first attempt), so the decision stays
with the human. The search matches both footer keywords this repo's
`gh:commit` accepts — `Closes` and `Fixes` — since a `Fixes #<N>` PR is
just as valid a duplicate signal as a `Closes #<N>` one (codex review,
PR #1509).

**Algorithm**:

```
if "GH_ISSUE_SKIP_DUPLICATE_CHECK" set:
    return 0

prs = `GH_HOST="$TARGET_HOST" gh pr list --repo "$TARGET_REPO" \
         --state open --search "\"Closes #<N>\" OR \"Fixes #<N>\" in:body" --json number -q '.[].number'`

if prs == []:
    return 0    # silent — no output on the common path

print "[WARN] Issue #<N> 을 이미 닫는 open PR #<M> 이 있습니다 — 중복 구현 가능성. 계속 진행하기 전에 확인하세요."
return 0
```

`<M>` is the first PR the search returns — one line however many come
back; the point is to send the human to the PR list, not to enumerate it.

**Why silence on the empty result matters**: this guard fires on every
implement run, so a line that also prints on the common "no duplicate"
case would train users to scroll past it — costing exactly the signal
#1507 exists to add.

**Soft-fail rule** (NF-1): any failure of the search itself → **no
output, continue**:
- Transient API / network error.
- Search unavailable or rate-limited on this host.
- `gh` too old to support `--search` on `pr list`.

Unlike 3.3, a failure here is not even worth a warn line: the check is
an advisory read, and a "could not check for duplicates" line on an
otherwise-fine run is noise of the same kind the previous paragraph
rejects. Never abort — a duplicate warning that blocks would break every
legitimate restart.

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
        # --repo "$TARGET_REPO" (Step 1) is explicit (#1405): the helper's
        # `gh repo view` fallback answers `gh repo set-default`, not the
        # remote this run resolved.
        _gh_project_status_sync issue <N> "In progress" --only-from "Backlog,Ready" --repo "$TARGET_REPO"
    fi
fi
```

The helper (`shell-common/functions/gh_project_status.sh`) handles:

- **Explicit `--repo`**: `$TARGET_REPO` from Step 1 (#1405). Without it
  the helper resolves via `gh repo view`, i.e. whatever
  `gh repo set-default` picked — which need not be the remote this run
  resolved.
- **No-board repos**: returns 0 silently when the issue belongs to no
  projectV2.
- **`--only-from` whitelist**: `Backlog,Ready` — never bounces an
  already-`In review` / `Done` card backwards. Other custom columns
  (`In design`, `Spec`, etc.) are left untouched; teams that want
  those moved should override the helper or skip with
  `GH_ISSUE_SKIP_BOARD_TRANSITION=1` and run the transition manually.

**Warn when `--only-from` absorbs the write (#1507, F-2)**: before
handing off to `_gh_project_status_sync`, read the card's current
Status with the same SSOT query helper `gh-pr-merge` used for its
now-retired board-approval gate (`_gh_project_status_query_current`,
also from `gh_project_status.sh` — see
`../gh-pr-merge/references/board-policy.md`, "Retired: Step 2-B
(removed in #1513)"), and when it is neither `Backlog` nor `Ready`,
print one line before the (no-op) mutation:

```
status = `_gh_project_status_query_current issue <N> "$TARGET_REPO"`

if status not in ("Backlog", "Ready"):
    print "[WARN] Issue #<N> Status 가 이미 \"<status>\" 입니다 — 다른 세션의 중복 착수이거나, 이슈가 이미 다른 단계로 넘어갔을 수 있습니다."
```

This changes nothing about the mutation — the helper's whitelist still
absorbs it, exactly as before. It only stops the absorption from being
*silent*. A card already sitting in `In progress` is the board-side
fingerprint of the same duplicate-session failure 3.3b watches for on
the PR side, and the two signals are independent: the other session may
have moved the board without opening a PR yet, or opened a PR in a repo
with no board at all. A restart of your own abandoned run also lands
here, which is fine — the line is advisory, not a refusal.

The wording is deliberately non-committal about *why* the Status isn't
`Backlog`/`Ready`: the same non-empty complement also includes terminal
columns like `Done` or custom ones like `Spec`, where "another session
already started this" would be the wrong read (codex review, PR #1509)
— the message names the fact (current Status) and offers duplicate-start
as one possible explanation, not the only one.

Reading the Status is itself best-effort: a non-zero return from
`_gh_project_status_query_current` (missing scope, network error, no
board) skips the warning and lets `_gh_project_status_sync` run as
usual (NF-1) — the same soft-fail posture 3.3b uses.
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
    state = `GH_HOST="$TARGET_HOST" gh issue view <M> --repo "$TARGET_REPO" --json state -q .state`
    if state == "CLOSED":
        continue
    print "[WARN] Issue #<N> depends on #<M> which is still <state>."
    print "    The implement may be premature — review or close #<M> first."
```

Pattern is case-insensitive ("Depends on", "depends on", "DEPENDS
ON" all match). Only matches whole `#<digits>` — not `#dep-3` or
`#1.2.3`.

**Failure mode**: if the `gh issue view <M>` above itself errors (deleted issue,
cross-repo reference, network), print one warn line and continue. Do
not abort — the dependency check is informational.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `GH_ISSUE_BLOCK_LABELS` | `do-not-work,on-hold,보류,⏸️ Postpone,reference` | Comma-separated block-label list for 3.2. Spaces inside a label are part of the label (don't pad commas). `reference` marks 참고용/구현 불필요 issues (issue #1226). |
| `GH_ISSUE_SKIP_SELF_ASSIGN` | unset | When `1`, skip 3.3 entirely. |
| `GH_ISSUE_SKIP_DUPLICATE_CHECK` | unset | When `1`, skip 3.3b entirely — no search call, no warning. For a deliberate second implementation of the same issue (issue #1507). |
| `GH_ISSUE_SKIP_BOARD_TRANSITION` | unset | When `1`, skip 3.4 entirely (its F-2 Status warning included). |
| `GH_ISSUE_SKIP_DEPS_CHECK` | unset | When `1`, skip 3.5 entirely. |

There is **no** env var to bypass 3.2 (block-label guard). That is
intentional — see "Block-label guard (fail-closed)" above.

## Behavior matrix

| Case | 3.2 block | 3.3 self-assign | 3.3b dup PR | 3.4 board | 3.5 deps | Net |
|---|---|---|---|---|---|---|
| Normal (board, unassigned, deps OK) | pass | add `@me` | silent | `In progress` (verified) | OK | proceed |
| Block-label attached | **abort exit 2** | n/a | n/a | n/a | n/a | refuse |
| Already self-assigned | pass | no-op | silent | `In progress` | OK | proceed |
| Assigned to another user | pass | warn + skip | silent | `In progress` | OK | proceed |
| Dependency `#M` OPEN | pass | add `@me` | silent | `In progress` | warn | proceed |
| No board attached | pass | add `@me` | silent | silent skip | OK | proceed |
| Open PR already closes `#N` | pass | no-op | **warn** | `In progress` | OK | proceed |
| Board Status already `In progress` | pass | no-op | silent | **warn** + no-op | OK | proceed |
| Duplicate search API error | pass | add `@me` | silent | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_SELF_ASSIGN=1` | pass | skip | silent | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_DUPLICATE_CHECK=1` | pass | add `@me` | skip | `In progress` | OK | proceed |
| `GH_ISSUE_SKIP_BOARD_TRANSITION=1` | pass | add `@me` | silent | skip | OK | proceed |
| `GH_ISSUE_SKIP_DEPS_CHECK=1` | pass | add `@me` | silent | `In progress` | skip | proceed |

The two duplicate-attempt rows are the #1507 additions; "silent" in the
3.3b column means the guard ran and found nothing, which is the normal
outcome. Both warn rows still end in `proceed` — neither signal blocks.

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
  - `GH_HOST="$TARGET_HOST" gh issue edit <N> --repo "$TARGET_REPO" --remove-assignee @me`
  - move the card back to `Backlog` on the project board.
- **Does not enforce stacked-PR `Depends on #parent-pr`.** Only issue
  references are scanned. PR-to-PR stacking is `gh:pr`'s territory.

## Test fixture

`tests/bats/skills/_fixtures/gh_issue_implement_claim.sh` mirrors
the five substep functions verbatim. The bats suite at
`tests/bats/skills/gh_issue_implement_claim.bats` exercises the
eight-case behavior matrix above. Any change to substep logic must
land in both files (and this doc).
