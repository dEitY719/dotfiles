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
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` per
  `references/repo-resolution.md`. Missing remote → list `git remote -v`
  and stop (no silent fallback).
- `--no-next-hint` — when present, omit the final `Next:` line in Step 6.

Check preconditions in parallel per `references/implementation-flow.md`
→ "Preconditions" (in a git repo, not on default branch, clean tree).
Fail-fast with the reasons from that file.

## Step 2: superpowers Plugin Detection

Per `references/superpowers-detection.md`: plugin missing → force mode
= `direct` + one warning line; else honor the requested mode.

## Step 3: Fetch + Claim Issue

Read `references/fetch-issue.md` for the `gh issue view` command,
error handling, and the CLOSED-issue refusal message.

After a successful fetch, claim the issue so teammates see it's being
worked. Read `references/claim-issue.md` for the command and soft-fail
rules (warning on failure, never blocks the flow).

## Step 4: Mode Dispatch

- **`direct`** → go to Step 5.
- **`plan`** → check ambiguity signals in
  `references/superpowers-detection.md`. If any → switch to
  `brainstorming`. Else invoke `Skill(superpowers:writing-plans)`.
  After plan is approved, proceed to Step 5 guided by the plan.
- **`brainstorming`** → invoke `Skill(superpowers:brainstorming)`.
  Its terminal state invokes writing-plans. After plan is approved,
  proceed to Step 5 guided by the plan.

## Step 5: Implement + Test

Follow the direct-mode flow in `references/implementation-flow.md` →
"Direct-mode flow" (detect `$TEST_CMD`, scan repo context, edit files,
run tests, on failure run the test-failure loop with max 3 iterations
per the same file).

## Step 6: Report

Print the success or failure report per
`references/implementation-flow.md` → "Final report format". Always
include the `Next:` hint pointing to `gh:commit` / `gh:pr` /
`gh:issue-flow`, unless `--no-next-hint` is set.

## Constraints

Read `references/constraints.md` before relaxing any of these: never
commit/PR, never create a worktree, never run on the default branch,
never fix pre-existing test failures, never retry the test loop more
than 3 times, never hard-require superpowers.
