# gh:issue-create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | remote-name, or `-h`/`--help`/`help` | `origin` | Git remote whose repo will own the new issue (e.g. `upstream`) |

## Usage

- `/gh:issue-create` — create issue on `origin`'s repo (the most common case)
- `/gh:issue-create upstream` — create issue on the `upstream` remote's repo
- `/gh-issue-create -h` / `--help` / `help` — print this help

## What the skill does

1. Confirms a git repo context and resolves `owner/repo` from the target
   remote's URL. If the remote does not exist, lists `git remote -v` and
   stops — no silent fallback to `origin`.
2. Classifies the conversation into one of **feature** / **bug** / **misc**,
   which determines the title prefix and body layout.
3. Drafts a structured issue body matching the category, pulling template
   from `references/issue-body-templates.md`. Writes the body in the
   language the user was speaking (Korean chat → Korean issue).
4. Creates the issue via `gh issue create --repo "$TARGET_REPO"` using a
   temp file written by `mktemp` (avoids shell escaping bugs).
5. Prints only `Issue #N created: <url>` — no preamble, no summary.

## Detail preservation

Do NOT over-compress. The issue is reused later for PR descriptions and
blog posts, so preserve:
- concrete file paths and line references
- command outputs and error logs
- decisions and the reasoning behind them
- discussion log — never collapse to 2–3 bullets

A 200-line issue is fine if the conversation warranted it.

## What the skill will NOT do

- Add `--assignee`, `--label`, or `--milestone` unless the user asked.
- Fall back to `origin` when the user-specified remote is missing.
- Ask "should I create it?" — running the skill is the confirmation.
- Rely on implicit repo detection — always passes `--repo "$TARGET_REPO"`.
- Truncate or summarize the conversation log.
