# gh:issue-implement — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | mode | `direct` | One of `direct`, `plan`, `brainstorming` |
| 3 | remote-name | `origin` | Git remote whose repo owns the issue |
| flag | `--no-next-hint` | off | Suppress the final `Next:` hint in the Step 6 report |

## Usage

- `/gh-issue-implement 16` — direct mode: read issue, implement, run tests. No human intervention. Uses superpowers:test-driven-development when installed; falls back to the built-in edit-then-test flow when not.
- `/gh-issue-implement 16 plan` — invoke superpowers:writing-plans first, implement per plan.
- `/gh-issue-implement 16 brainstorming` — invoke superpowers:brainstorming for design, then plan, then implement.
- `/gh-issue-implement 16 direct upstream` — direct mode on `upstream` remote's repo.
- `/gh-issue-implement -h` / `--help` / `help` — print this help.

## Precondition (by convention)

The user runs this skill **after** creating a dedicated git worktree
(e.g., via `gwt`) and `cd`-ing into it. The skill does NOT create
worktrees.

## What the skill does

1. Fetches the issue (same JSON fields as gh:issue-read).
2. Verifies precondition: inside a git repo, on a non-base branch, working tree clean.
3. Claims the issue via `gh issue edit <N> --add-assignee @me` so teammates see it's being worked (soft-fail on error; see `references/claim-issue.md`).
4. Depending on mode:
   - **direct** — with superpowers installed, invokes superpowers:test-driven-development and implements the issue as red-green-refactor cycles. Without it, explores the codebase, edits/creates files, runs tests.
   - **plan** — invokes superpowers:writing-plans with the issue body as context. If issue is ambiguous (see `references/implementation-flow.md` → "Ambiguity signals"), auto-promotes to brainstorming.
   - **brainstorming** — invokes superpowers:brainstorming, then writing-plans, then implements.

   `plan` and `brainstorming` also end up in TDD — their plans execute through superpowers:subagent-driven-development, whose subagents follow test-driven-development per task.
5. Auto-detects the test runner from AGENTS.md → `tox.ini` → `pyproject.toml` → `package.json` → `tests/*.bats`, using the first that matches, then records a pre-edit baseline of already-failing tests.
6. Pre-existing failures are reported separately, never fixed — on both paths. The 3-attempt test-failure loop applies to the fallback path only; the TDD path stops on judgment instead (same failure repeating, fix breaking a green test, unexplained failure).
7. Prints a compact report: changed files, which path ran (`tdd`/`fallback`), test result, next-step hint.

## superpowers plugin not installed → fallback

If `~/.claude/plugins/cache/superpowers-dev/` does not exist and the
superpowers skills do not resolve:

- `plan`/`brainstorming` fall back to `direct` with one warning line:

  ```
  [WARN] superpowers plugin not installed — falling back to direct mode.
  ```

- `direct` stays `direct` and runs the built-in implementation flow.
  Nothing is lost — the fallback path is complete on its own. If only
  test-driven-development is missing (partial install):

  ```
  [WARN] superpowers:test-driven-development unavailable — using built-in implementation flow.
  ```

## What the skill will NOT do

- Create commits or PRs. Stops at "tests pass". Use `/gh-commit` and `/gh-pr` (or `/gh-issue-flow` for the chain).
- Create a git worktree. Use `gwt` first.
- Run on the base branch (main/master). Stops with a feature-branch reminder.
- Run with a dirty working tree (stops and asks).
