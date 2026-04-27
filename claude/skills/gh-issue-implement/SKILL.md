---
name: gh:issue-implement
description: >-
  Read a GitHub issue by number and implement it — editing files and
  running tests, but NOT committing or opening a PR. Use when the user
  runs /gh:issue-implement, /gh-issue-implement, or asks "issue #16
  구현해", "PR 없이 이 이슈 코드만 짜줘", "implement #42". Default mode
  is direct (no human intervention); optional `plan` or `brainstorming`
  modes invoke the matching superpowers skills when the plugin is
  installed (falls back to direct with a warning if not). Precondition:
  user is already inside a dedicated git worktree on a feature branch.
  Accepts `<issue-number> [direct|plan|brainstorming] [remote]`,
  optional `--no-next-hint` (suppress final `Next:` hint), and
  `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# gh:issue-implement — Issue → Code

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo + Preconditions

Positional args: `<issue-number> [mode] [remote]`. Optional flag: `--no-next-hint`.

- `issue-number` — required, positive integer.
- `mode` — default `direct`. Must be `direct`, `plan`, or `brainstorming`.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` via
  `git remote get-url <remote>`. Missing remote → list `git remote -v`
  and stop (no silent fallback to `origin`). Substeps in
  `references/repo-resolution.md`.
- `--no-next-hint` — optional flag. When present, omit the final
  `Next:` guidance line in Step 6 output.

Check preconditions in parallel (exact rules in
`references/implementation-flow.md` → "Preconditions"):
- in a git repo
- current branch ≠ default branch
- working tree clean

Fail-fast on any precondition with the reasons from that file.

## Step 2: superpowers Plugin Detection

Per `references/superpowers-detection.md`:
- If plugin missing → force mode = `direct` + print one warning line.
- Else → honor the requested mode.

## Step 3: Fetch + Claim Issue

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,state,comments,url
```

On error (not found, auth) → print stderr + stop.

If `state == CLOSED`, stop with:
```
Issue #<N> is CLOSED. Refuse to implement a closed issue — reopen it
or pass a different number.
```

Then claim the issue so teammates see it's being worked:

```bash
gh issue edit <N> --repo "$TARGET_REPO" --add-assignee @me
```

Soft-fail: on error print one stderr warning and continue. Rules in
`references/claim-issue.md`.

## Step 4: Mode Dispatch

- **`direct`** → go to Step 5.
- **`plan`** → check ambiguity signals (list in
  `references/superpowers-detection.md`). If any → switch to
  `brainstorming`. Else invoke `Skill(superpowers:writing-plans)`.
  After plan is approved, proceed to Step 5 guided by the plan.
- **`brainstorming`** → invoke `Skill(superpowers:brainstorming)`.
  That skill's terminal state invokes writing-plans. After plan is
  approved, proceed to Step 5 guided by the plan.

## Step 5: Implement + Test

Use the direct-mode flow in `references/implementation-flow.md`:

1. Detect test runner → `$TEST_CMD`.
2. Scan repo context (AGENTS.md, CLAUDE.md, README).
3. Identify files to touch; use Edit/Write.
4. Run `$TEST_CMD`.
5. On failure → test-failure loop (max 3 iterations).

## Step 6: Report

Print the success or failure report per
`references/implementation-flow.md` → "Final report format". Always
include the `Next:` hint pointing to `gh:commit` / `gh:pr` /
`gh:issue-flow`, unless `--no-next-hint` is set.

## Constraints

- Never create commits or PRs. That's a deliberate boundary.
- Never create a git worktree. User runs `gwt` first by convention.
- Never run on the default branch. Always require a feature branch.
- Never dismiss pre-existing test failures by fixing them — report
  them as pre-existing.
- Never retry the test-failure loop more than 3 times. Human handoff
  is safer than infinite loops.
- Never require superpowers to work. Direct mode is always available.
