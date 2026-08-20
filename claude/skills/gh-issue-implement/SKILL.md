---
name: gh:issue-implement
description: >-
  Read a GitHub issue by number and implement it — editing files and running tests,
  but NOT committing or opening a PR. Use when the user runs /gh:issue-implement,
  /gh-issue-implement, or asks "issue #16 구현해", "PR 없이 이 이슈 코드만 짜줘",
  "implement #42". Default mode is direct (no human intervention), driven by
  `superpowers:test-driven-development` when installed, else by the built-in
  edit-then-test flow; optional `plan` or `brainstorming` modes invoke the matching
  superpowers skills when the plugin is installed (falls back to direct with a
  warning if not). Precondition: user is already inside a dedicated git worktree on
  a feature branch. Sibling of [[gh:issue-proceed]] — this skill edits files to
  satisfy a code-change issue; that one executes the protocol a directive issue
  embeds. Accepts `<issue-number> [direct|plan|brainstorming] [remote]`, optional
  `--no-next-hint` (suppress final `Next:` hint), and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Skill
metadata:
  model_recommendation:
    tier: opus
    reason: "deep implementation — repo-context reasoning, multi-file edits, test-failure loop, high-risk writes"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-implement — Issue → Code

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

**Stop-on-error policy** — HARD-abort: Step 1 preconditions, 3.1 fetch,
3.2 block-label guard. Everything else (3.3–3.5 claim writes, Step 5 test
loop) soft-fails or bounded-retries — a transient blip never blocks.

## Step 1: Parse Args + Resolve Repo + Preconditions

Record `START_TS=$(date +%s)` immediately for Step 6 elapsed tracking.
Positional args: `<issue-number> [mode] [remote]`; flag `--no-next-hint`.

- `issue-number` — required, positive integer.
- `mode` — default `direct`; one of `direct` / `plan` / `brainstorming`.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` per
  `references/repo-resolution.md`; missing → `git remote -v` + stop.
- `--no-next-hint` — omit the final `Next:` line in Step 6.

Check preconditions in parallel per `references/implementation-flow.md`
→ "Preconditions" (git repo, not default branch, clean tree); fail-fast.

## Step 2: superpowers Plugin Detection

Per `references/superpowers-detection.md`: plugin missing → force mode
= `direct` + one warning line; else honor the requested mode. The resolve
check includes `test-driven-development` (gates Step 5's TDD path) and
`subagent-driven-development` (gates the plan/brainstorming TDD guarantee
in Step 4).

## Step 3: Fetch + Claim Issue

Five substeps in order — full policy, env vars, and behavior matrix in
`references/claim.md`. After 3.1/3.3/3.4 emit `printf '[step:gh-issue-implement/<marker>] OK\n'`
(markers `fetch-issue`, `self-assign`, `board-transition`) so the harness step-skip
guard (`skill_completion_guard.py`, #753) can verify the run.

3.1 **Fetch** — `references/fetch-issue.md` (CLOSED refusal there).
3.2 **Block-label guard** — fail-closed abort (exit 2) if any label matches `GH_ISSUE_BLOCK_LABELS`.
3.3 **Self-assign** — `--add-assignee @me` unless already assigned (warn, no override, if held by another).
3.4 **Board transition** — `_gh_project_status_sync issue <N> "In progress" --only-from "Backlog,Ready"`; no-op without a board.
3.5 **Depends-on guard** — soft-warn per OPEN `Depends on #M` line.

Skip 3.3 / 3.4 / 3.5 via their `GH_ISSUE_SKIP_*` env vars.

## Step 4: Mode Dispatch

- **`direct`** → Step 5.
- **`plan`** → if ambiguity signals (`references/superpowers-detection.md`)
  appear, switch to `brainstorming`; else `Skill(superpowers:writing-plans)`.
- **`brainstorming`** → `Skill(superpowers:brainstorming)` (terminal state
  invokes `writing-plans`). After plan approval, proceed to Step 5.
- Both plan modes reach TDD per task via `subagent-driven-development` when
  that skill also resolves (verified alongside the rest of Step 2).

## Step 5: Implement + Test

Follow `references/implementation-flow.md` → "Direct-mode flow": common steps
(fetch, intent, scan, `$TEST_CMD`, pre-edit baseline), then branch on
superpowers detection **and** test-runner presence — detected + runner →
**TDD path** (`Skill(superpowers:test-driven-development)` drives red-green-refactor,
no attempt cap, stops on judgment); anything else (not detected, or no runner
regardless of detection) → **fallback path** (edit, run tests if a runner
exists, failure loop max 3×). Neither fixes pre-existing failures. After tests
pass (or skip — no runner), emit `printf '[step:gh-issue-implement/implement] OK\n'`.

## Step 6: Report

Print the success/failure report per `references/implementation-flow.md`
→ "Final report format" + its "ai-metrics line" (ELAPSED). Include the
`Next:` hint (`gh:commit` / `gh:pr` / `gh:issue-flow`) unless
`--no-next-hint`; then `printf '[step:gh-issue-implement/report] OK\n'`.

## Constraints

Read `references/constraints.md` first: never commit/PR, create a worktree, run on
the default branch, fix pre-existing test failures (TDD path included — it does not
override this), exceed 3 test-loop retries (fallback path), or require superpowers.
