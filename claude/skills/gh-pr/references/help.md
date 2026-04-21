# gh:pr — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | issue-number, or `-h`/`--help`/`help` | auto-detected | Link PR to this GitHub issue via `Closes #N` / `Refs #N` in the body |

## Usage

- `/gh-pr` — push the current branch if needed, then open a PR against
  the repo's default branch covering every commit in the range
- `/gh-pr 123` — same, but force-link to issue `#123` regardless of chat/commits
- `/gh-pr -h` / `--help` / `help` — print this help

## What the skill does

1. Resolves the base branch (`gh repo view --json defaultBranchRef`) and
   checks the current branch is not the base. Fetches `origin` to make
   sure the range is computed against up-to-date refs.
2. Reads **all** commits in `<base>..HEAD` — the PR body must cover every
   commit, not only HEAD. Groups them by theme for the Summary.
3. Resolves the linked issue using the same precedence as `gh:commit`:
   explicit arg → recent chat → commit footers → none.
4. Drafts title + body per `references/pr-body-template.md`, matching the
   language dominant in existing commits (Korean commits → Korean PR).
5. Pushes the branch (`git push -u origin HEAD` if no upstream, `git push`
   if ahead). Diverged upstream → stops and asks; never force-pushes on
   its own.
6. Creates the PR via `gh pr create --assignee @me` using a `mktemp` body
   file. Always self-assigns.
7. Applies labels derived from conventional-commit types (feat, fix, docs,
   etc.) plus scope labels — but only labels that **already exist** in the
   repo. Never creates new labels.
8. Prints only `PR created: <url>`.

## What the skill will NOT do

- Force-push without explicit user approval.
- Target a base branch other than the repo's default branch unless told.
- Include the `🤖 Generated with Claude Code` footer unless the repo
  already uses that convention in existing PRs.
- Skip "minor" commits in the Summary — the range is the contract.
- Create new labels — only applies labels that exist.
- Open a PR when the branch has no commits ahead of base, or when you're
  currently on the base branch (stops with guidance instead).

## Good vs. bad invocation

- **Good**: Feature branch with 3 commits, `/gh-pr` — body covers all 3,
  links any `#N` in chat, returns the URL.
- **Good**: `/gh-pr 42` after a hotfix — body includes `Closes #42`.
- **Bad**: running on `main` — skill stops with "create a feature branch first".
- **Bad**: running with an empty `<base>..HEAD` — skill stops with "nothing to PR".
