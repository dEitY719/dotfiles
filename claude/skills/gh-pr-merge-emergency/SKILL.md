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
---

# gh:pr-merge-emergency — Admin-Bypass Merge with Audit Trail

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output it verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Target

Positional args: `<PR> <reason> [remote]`.

- `PR` — number (required). If omitted, try `gh pr view --json number` on
  current branch; else stop with a usage pointer.
- `reason` — **required**, ≥10 chars, must reference an incident/ticket
  ID or concrete user impact. Vague reasons (`"urgent"`, `"fix"`) → refuse.
  Examples in `references/help.md`.
- `remote` — default `origin`. Resolve `TARGET_REPO` via
  `git remote get-url`; missing → `git remote -v` and stop.

Capture `ME=$(gh api user -q .login)`, `NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.

## Step 2: Pre-flight Safety Gate (parallel)

Fetch in parallel; evaluate stops **before** touching merge:

- PR JSON: `number,title,author,state,isDraft,mergeable,mergeStateStatus,baseRefName,headRefName`
- `gh pr checks <N> --repo $TARGET_REPO --required`

**Hard stops** (emergency ≠ reckless): `state != OPEN` · `isDraft == true` ·
`mergeable == CONFLICTING` · any required check failing/pending. Emergency
bypasses **approval**, not **CI** — fix or rerun CI instead of bypassing.

**Soft warnings** (print, continue): base `BEHIND` → note in audit. No
approving review → expected here, but surface it in the confirmation prompt.

## Step 3: Confirm with the User

Print the planned action (repo, PR, author, base/head, CI summary, reason)
followed by `Proceed? (yes/ok/진행/머지)`. Never auto-proceed; ambiguous
reply → ask again. Exact prompt template in `references/audit-templates.md`.

## Step 4: Audit Comment + Admin Merge

Order matters — comment first so the audit survives branch deletion.

1. `gh pr comment <N> --repo "$TARGET_REPO"` with the "PR audit comment"
   body from `references/audit-templates.md`; capture the comment URL for
   Step 6.
2. `gh pr merge <N> --repo "$TARGET_REPO" --admin --squash --delete-branch`
   (flag rationale in the same reference file). If it fails with "Must
   have admin rights", **stop** and report — do NOT fall back to
   `--merge`/`--rebase`.
3. Capture the merge SHA:
   `gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid`.

## Step 5: Create Post-Merge Incident Issue

Non-negotiable audit tail. File `incident: emergency merge of PR #<N> —
<reason first line>` with the body + retro checklist from
`references/audit-templates.md`. Attach an `incident` label **only if**
`gh label list --repo "$TARGET_REPO"` confirms it exists.

## Step 6: Report

```
Emergency-merged PR #<N>
  Merge SHA:       <sha>
  Audit comment:   <url>
  Incident issue:  #<M> (<url>)
  Reason:          <reason>
  ⚠️  Add retro notes to incident issue within 72h.
```

## Constraints

- Never bypass CI. Approval bypass only.
- Never skip the incident issue — the audit tail is the whole point.
- Never run without an affirmative user confirmation.
- Never use `--merge`/`--rebase` to dodge a failing admin merge.
- Reason must be substantive; refuse `"urgent"`/`"fix"`/`"merge now"`.
