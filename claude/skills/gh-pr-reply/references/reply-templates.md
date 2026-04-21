# Reply Templates — for gh:pr-reply skill

Reply in the language the reviewer used. Korean reviewer → Korean reply.
Japanese reviewer → Japanese reply. English reviewer → English reply. Match
their register and tone (formal/informal) as well.

## POST command shapes

### Inline review comment (from `/pulls/<N>/comments`)

Reply in-thread using the replies sub-resource:

```bash
gh api "repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies" \
  -X POST \
  -f body="<reply text>"
```

### Top-level issue comment (from `/issues/<N>/comments`)

No thread reply endpoint exists; post a new issue comment that blockquotes
the original so the context is clear. **Every line of the original must be
prefixed with `> ` individually** — a single `> ` only quotes the first
line in GitHub-flavored Markdown.

```bash
# Build a properly quoted blockquote from the original body
QUOTED=$(printf '%s\n' "$ORIGINAL_BODY" | sed 's/^/> /')

gh api "repos/<owner>/<repo>/issues/<N>/comments" \
  -X POST \
  -f body="$QUOTED

<reply text>"
```

The same pattern applies when replying to a review summary from
`/pulls/<N>/reviews`: there is no per-review reply endpoint, so post a
top-level issue comment that blockquotes the review body and addresses it.

## Reply body templates

### Accepted

```
Accepted. Fixed in <short-sha> — <one-line what changed>.
```

### Accepted with modification

```
Accepted with modification. Rather than <their suggestion>, I went with
<actual fix> in <short-sha> because <reason>.
```

### Declined

```
Declined. <specific reason tied to the code/context>. <optional: pointer to
docs, other PR, or file that justifies the current design>.
```

### Question answered

```
<direct answer>. <optional: link to file:line for reference>.
```

## Notes

- Always include the commit short-sha for Accepted / Accepted-with-modification
  replies — reviewers need a pointer to verify the fix.
- Declined replies must state a concrete reason, never a dismissive one-liner.
- Bot comments get the exact same templates — no shortcuts.

## Classification rubric

Use these four classes in Step 3 of the SKILL.md workflow. Every
unaddressed comment falls into exactly one.

- **ACCEPT** — reviewer is correct; the code should change.
- **ACCEPT-PARTIAL** — valid concern, but a different fix is better; note
  the deviation in the reply (use the "Accepted with modification" body).
- **DECLINE** — reviewer is wrong, misunderstanding the context, or the
  suggestion would regress something; must explain why in the reply.
- **QUESTION** — reviewer asked for clarification rather than a change;
  answer the question directly.

Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules — a bot nit is still a legitimate comment that deserves a reply.
