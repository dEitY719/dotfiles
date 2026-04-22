# gh:issue-read — Output Format

## Structure

The skill prints sections in this exact order. Empty sections are omitted except Header and Body.

### 1. Header

```
#<N> <title> by @<author> (<state>, labels: <csv> | none)
<url>
```

`state` is one of `OPEN`, `CLOSED`. If the issue is closed as `not_planned` or `completed`, include that in parens:
`(CLOSED — completed)`.

### 2. Summary (2-4 lines)

Extract what the issue asks for. Start with a verb when possible.
Example:
```
Summary:
- Upload API 에 retry + exponential backoff 추가.
- 실패 시 최대 5회까지 재시도, 간격 1s → 16s 지수 증가.
- 테스트: unit + integration (flaky network mock).
```

### 3. Body (verbatim)

Reproduce the issue body **as written**. Preserve:
- Markdown formatting (headings, code blocks, lists)
- File paths and line references
- Command outputs
- Discussion links

Do NOT summarize or compress.

If the issue body is empty, render `(empty)` as a placeholder — do not
omit the Body section header.

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
