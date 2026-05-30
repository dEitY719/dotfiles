---
name: gh:pr-merge-emergency
description: >-
  Emergency-merge a GitHub PR by bypassing branch-protection approval
  requirements via admin override, while forcing an audit trail: a reason
  comment on the PR and a follow-up incident issue for later retro. Use
  when the user runs /gh-pr-merge-emergency, /gh:pr-merge-emergency, or
  asks "긴급 머지", "주말 핫픽스 머지", "approval 없이 머지", "admin bypass
  merge". NOT a replacement for normal review — the skill actively blocks
  overuse by requiring a written reason and creating a post-merge issue.
  Required CI must still pass; conflicts still stop the merge. Accepts
  `-h`/`--help`/`help` to print usage. Project-agnostic; works in any repo
  where the caller has admin/merge permission.
allowed-tools: Bash, Read, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "admin bypass + audit trail (PR comment + incident issue); requires user confirmation & substantive reason validation"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-merge-emergency — Admin-Bypass Merge with Audit Trail

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output it verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Target

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Positional args: `<PR> <reason> [remote]`.

- `PR` — number (required). Omitted → `gh pr view --json number` on current
  branch; else stop with a usage pointer.
- `reason` — **required**, ≥10 chars, referencing an incident/ticket ID or
  concrete user impact. Vague reasons (`"urgent"`, `"fix"`) → refuse. Examples
  in `references/help.md`.
- `remote` — default `origin`. Resolve `TARGET_REPO` via `git remote get-url`;
  missing → `git remote -v` and stop.

Capture `ME=$(gh api user -q .login)`, `NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.

## Step 2: Pre-flight Safety Gate (parallel)

Fetch in parallel, evaluate stops **before** touching merge: PR JSON
(`number,title,author,state,isDraft,mergeable,mergeStateStatus,baseRefName,headRefName`)
and `gh pr checks <N> --repo $TARGET_REPO --required`.

**Hard stops**: `state != OPEN`, draft, conflicts, or failing/pending required
checks — emergency bypasses **approval**, not **CI**. **Soft warnings**: base
`BEHIND`; no approving review.

## Step 3: Confirm with the User

Print the planned action (repo, PR, author, base/head, CI summary, reason) then
`Proceed? (yes/ok/진행/머지)`. Exact prompt: `references/audit-templates.md`.
Never auto-proceed.

## Step 4: Audit Comment + Admin Merge

Order matters — comment first so the audit survives branch deletion. (1) Post
the "PR audit comment" from `references/audit-templates.md`, capturing its URL
for Step 7. (2) `gh pr merge <N> --admin --squash --delete-branch` (flag
rationale in the same file); "Must have admin rights" → **stop**, never fall
back to `--merge`/`--rebase`. (3) Capture the merge SHA via
`gh pr view <N> --json mergeCommit -q .mergeCommit.oid`.

## Step 5: Create Post-Merge Incident Issue

Non-negotiable audit tail. File `incident: emergency merge of PR #<N> — <reason
first line>` with the body + retro checklist from `references/audit-templates.md`.
Attach an `incident` label **only if** `gh label list --repo "$TARGET_REPO"`
confirms it exists.

Append the ai-metrics footer to the incident issue body before creating it
(required artifact — no soft-fail; honors `GH_DISABLE_AI_METRICS=1` per issue
#399). Exact block: `references/audit-templates.md` -> "ai-metrics footer".

## Step 6: Sync Project Board Status

Read `references/project-board-sync.md` and push the merged PR card to `Done`.
Sync failure never blocks the audit report.

## Step 7: Report

```
Emergency-merged PR #<N>
  Merge SHA:       <sha>
  Audit comment:   <url>
  Incident issue:  #<M> (<url>)
  Reason:          <reason>
  [WARN] Add retro notes to incident issue within 72h.
```

## Constraints

Never: bypass CI (approval bypass only); skip the incident issue (the audit tail
is the whole point); run without affirmative confirmation; use `--merge`/`--rebase`
to dodge a failing admin merge. Reason must be substantive — refuse
`"urgent"`/`"fix"`/`"merge now"`.
