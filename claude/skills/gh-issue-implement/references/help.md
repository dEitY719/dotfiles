# gh:issue-implement — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | mode | `direct` | One of `direct`, `plan`, `brainstorming` |
| 3 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh-issue-implement 16` — direct mode: read issue, implement, run tests. No human intervention.
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
   - **direct** — explores the codebase, edits/creates files, runs tests.
   - **plan** — invokes superpowers:writing-plans with the issue body as context. If issue is ambiguous (see `references/implementation-flow.md` → "Ambiguity signals"), auto-promotes to brainstorming.
   - **brainstorming** — invokes superpowers:brainstorming, then writing-plans, then implements.
5. Auto-detects the test runner from AGENTS.md → `tox.ini` → `pyproject.toml` → `package.json` → `tests/*.bats`, using the first that matches.
6. Test-failure loop: up to 3 attempts to fix failures caused by its own edits; pre-existing failures are reported separately, not fixed.
7. Prints a compact report: changed files, test result, next-step hint.

## superpowers plugin not installed → fallback

If `~/.claude/plugins/cache/superpowers-dev/` does not exist, any
`plan`/`brainstorming` mode falls back to `direct` with one warning line:

```
⚠️  superpowers plugin not installed — falling back to direct mode.
```

## What the skill will NOT do

- Create commits or PRs. Stops at "tests pass". Use `/gh-commit` and `/gh-pr` (or `/gh-issue-flow` for the chain).
- Create a git worktree. Use `gwt` first.
- Run on the base branch (main/master). Stops with a feature-branch reminder.
- Run with a dirty working tree (stops and asks).
