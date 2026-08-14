# gh:issue-relay-flow — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | Issue already filed on the destination remote |
| flag | `--remote <name>` | `upstream` | Destination remote — same remote `gh:relay-merge` targets at the end |
| flag | `--base <branch>` | auto-detect | Override the destination default branch (skips `git ls-remote --symref`) |

## Usage

```
/gh-issue-relay-flow 1346                          # branch off upstream's default branch, implement, verify, relay
/gh-issue-relay-flow 1346 --remote fork            # same, but destination remote is 'fork'
/gh-issue-relay-flow 1346 --base develop           # skip default-branch detection, base off 'develop'
/gh-issue-relay-flow -h                            # this help
```

## When to use this skill

- The issue is already filed on a remote you cannot `git push` to directly
  from this machine (corporate-proxy-blocked path to that remote), and you
  want the full "branch → implement → verify → relay" loop in one call
  instead of doing each step by hand.
- You expect to repeat this loop often for the same push-blocked
  destination (this is exactly the workflow issue #1346 was filed to
  standardize).

## When NOT to use

- The issue is not filed yet — run `gh:issue-create <remote>` first.
- `git push <remote>` actually works from this machine — just use
  `gh:issue-implement` + `gh:commit` + `gh:pr` (or `gh:issue-flow`)
  directly; this skill's value is specifically the relay handoff at the end.
- You already have a commit range ready and just want to relay it — call
  `gh:relay-merge --commits <base>..<head>` directly instead of this whole
  chain.

## What this skill does

1. **Resolve destination + branch** (`references/branch-setup.md`) —
   resolves `--remote` (hard error, no silent `origin` fallback), detects
   the destination's default branch via `git ls-remote --symref`, fetches
   it, and creates (or reuses) a local branch named `issue-<N>-<title-slug>`.
2. **Delegate implementation** (`references/worker-brief-checklist.md`) —
   fetches the issue body/comments, resolves any unresolved Open Questions
   with the user first, and hands a self-contained brief to an opus Worker
   subagent (Advisor/Worker split from the root `CLAUDE.md`).
3. **Advisor verification** (`references/verification.md`) — reads the
   actual diff, discovers and runs the target repo's lint/test commands,
   and does not proceed on failure.
4. **Relay** — calls `gh:relay-merge --commits <base>..<head> --target-issue
   <N> --remote <remote>` verbatim; all patch/gist/apply-guide logic lives
   there, not here.
5. **Report** — relays `gh:relay-merge`'s Step 8 output plus a final
   `[OK]`/`[FAIL]` line for the whole chain.

## What this skill will NOT do

- Register the issue — that is `gh:issue-create`'s job, run beforehand.
- Fall back to `origin` when the requested `--remote` is missing.
- Delegate implementation while the issue has unresolved Open Questions.
- Auto-reset a reused branch that has commits not on the destination's
  default branch — it asks first.
- Reimplement any part of `gh:relay-merge` (patch generation, the 40KB
  cutoff, gist upload, apply-guide posting) — it delegates, never
  duplicates.

## Related skills

- `gh:relay-merge` — the atomic relay step this skill delegates to at the
  end; call it directly when you already have a ready commit range.
- `gh:issue-flow` — the sibling composition skill for the *non*-relay case
  (destination remote is normally pushable): implement → commit → PR →
  quality gate, no patch/gist relay involved.
- `gh:issue-implement` — the atomic implementation step this skill's Worker
  delegation is modeled after (same "already on a feature branch" contract).
- `gh:issue-create` — files the issue this skill assumes already exists.
