# Comment Fetching — for gh:pr-reply skill

PRs expose review feedback through three distinct API endpoints — all must be
queried. Missing any one of them means missing comments (bots especially tend
to scatter content across these endpoints).

## The three endpoints

```bash
# Inline code review comments (line-anchored)
gh api "repos/<owner>/<repo>/pulls/<N>/comments" --paginate

# Top-level issue-style comments on the PR conversation
gh api "repos/<owner>/<repo>/issues/<N>/comments" --paginate

# Review summaries (bots often put content here)
gh api "repos/<owner>/<repo>/pulls/<N>/reviews" --paginate
```

## Fields to extract per comment

- `id` — comment identifier (needed for replying)
- `user.login` — author (including bots: gemini-code-assist, sourcery-ai, copilot)
- `path` — file the comment is anchored to (inline comments only)
- `line` — line number in the file (inline comments only)
- `body` — comment text
- `in_reply_to_id` — parent comment id, for threading
- `html_url` — link back to the comment on GitHub

## Deduplication rule

Skip threads where a human or Claude has already posted a reply. Check the
`in_reply_to_id` chains: if any descendant in the thread is authored by the
current user or by Claude, treat the thread as already addressed.

Exception: if the user explicitly asks to re-process, ignore this filter and
reply to everything fresh.
