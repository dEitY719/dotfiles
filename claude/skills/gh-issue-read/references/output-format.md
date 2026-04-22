# gh:issue-read — Output Format

## Structure

The skill prints sections in this exact order. Empty sections are omitted except Header and Body.

### 1. Header

```
#<N> <title> by @<author> (<state>, labels: <csv> | none)
```

`state` is one of `OPEN`, `CLOSED`. If the issue is closed as `not_planned` or `completed`, include that in parens:
`(CLOSED — completed)`.

### 2. Summary (2-4 lines)

Extract what the issue asks for. Start with a verb when possible.
Example:
```
Summary:
- 기존 gh:issue 스킬을 gh:issue-create 로 rename.
- 추가로 gh:issue-read, gh:issue-implement, gh:pr-merge, gh:issue-flow 스킬 신설.
- 얇은 합성 스킬 패턴 도입.
```

### 3. Body (verbatim)

Reproduce the issue body **as written**. Preserve:
- Markdown formatting (headings, code blocks, lists)
- File paths and line references
- Command outputs
- Discussion links

Do NOT summarize or compress.

### 4. Discussion (if comments > 0)

Chronological, one comment per block:
```
--- Comment by @<author> at <ISO-8601 timestamp> ---

<comment body, verbatim>
```

### 5. Meta

```
Created:  <ISO-8601>
Updated:  <ISO-8601>
Assignees: @<user1>, @<user2>  (or "none")
Linked PRs: #<pr1>, #<pr2>      (only if GitHub auto-detected; skip otherwise)
```

### 6. Checklist (if issue contains `- [ ]` items)

Extract all `- [ ]` and `- [x]` items from body and comments, keeping their original text:
```
Checklist:
- [x] Decide skill names
- [ ] Implement gh:issue-read
- [ ] Implement gh:issue-implement
```

## JSON fields to fetch

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,author,labels,state,stateReason,\
  comments,assignees,createdAt,updatedAt,url
```

`comments` items: `{author, body, createdAt}`.
`labels` items: `{name}`.
`author`, `assignees` items: `{login}`.
