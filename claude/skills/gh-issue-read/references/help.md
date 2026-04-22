# gh:issue-read — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number (required unless help) |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh-issue-read 42` — fetch issue #42 from `origin`'s repo, print structured summary
- `/gh-issue-read 42 upstream` — fetch from `upstream` remote's repo
- `/gh-issue-read -h` / `--help` / `help` — print this help

## What the skill does

1. Resolves the target repo from the given remote (default `origin`). Missing remote → lists `git remote -v` and stops, no silent fallback.
2. Fetches the issue via `gh issue view <N> --repo $TARGET_REPO --json ...` including body, author, labels, state, comments, assignees, timestamps.
3. Prints a structured summary:
   - Header: `#N <title> by @author (state, labels)`
   - Summary: 2-4 line extraction of what the issue asks for
   - Body: original markdown, preserved verbatim
   - Discussion: comments in chronological order with author + timestamp
   - Meta: created/updated timestamps, assignees, linked PRs
   - Checklist (if the issue contains explicit acceptance criteria)
4. Output is in the user's conversation language (Korean chat → Korean summary section headings, but body/comments stay in their original language).

## What the skill will NOT do

- Modify the issue (no close/label/assign).
- Follow through to linked PRs or other issues (only the one at hand).
- Silently fall back to `origin` when a non-existent remote is given.
- Truncate body or comments — the skill's whole point is preserving detail for humans.
