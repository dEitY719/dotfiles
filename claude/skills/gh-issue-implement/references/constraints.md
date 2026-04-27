# gh:issue-implement — Hard Constraints

These are deliberate boundaries. Do not violate them even when the user
asks "just this once" — composition skills (`gh:issue-flow`) exist for
the cases where these limits are inconvenient.

## Never create commits or PRs

This skill stops at "files edited, tests run". Commits and PRs are
separate skills (`gh:commit`, `gh:pr`) so the user can:

- Inspect the diff before committing.
- Squash multiple implementation attempts into one commit.
- Choose commit message style per repo.

If you find yourself running `git commit` here, stop. Print the final
report and exit.

## Never create a git worktree

The `gwt` helper / `ai-worktree:spawn` skill is the entry point for
worktree creation. By the time this skill runs, the user is already in
the right directory. Creating a worktree from inside this skill would
nest worktrees and confuse the cleanup flow.

## Never run on the default branch

Implementing directly on `main` / `master` corrupts the base for every
other in-flight feature branch. Step 1 enforces this — if the check
ever fires, do not bypass it.

## Never dismiss pre-existing test failures

The test-failure loop in `implementation-flow.md` distinguishes
PRE-EXISTING (failing before this skill ran) from CAUSED (introduced
by this skill's edits). Fixing pre-existing failures expands scope
silently and pollutes the diff. Report them in the final output and
let the human decide whether to fix them in a separate change.

## Never retry the test-failure loop more than 3 times

Three attempts is enough for the model to either converge or admit
defeat. Beyond that, the failure pattern is usually not a
mechanical-fix problem — handing back to the human is faster than
burning more tokens on a wrong hypothesis.

## Never require superpowers to work

Direct mode is always available. The plugin gates `plan` and
`brainstorming` modes only. Hard-requiring the plugin would make the
skill fail on machines without it — defeating the purpose of a
graceful fallback.
