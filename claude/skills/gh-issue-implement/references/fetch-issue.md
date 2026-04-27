# gh:issue-implement — Fetch Issue

## Command

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,state,comments,url
```

## Error handling

- On non-zero exit (issue not found, auth failure, network) → print
  the captured stderr verbatim and stop. Do not retry, do not fall
  back to a different repo.

## Closed-issue refusal

If the parsed `state` is `CLOSED`, stop with this exact message:

```
Issue #<N> is CLOSED. Refuse to implement a closed issue — reopen it
or pass a different number.
```

Rationale: a closed issue has either been resolved or rejected.
Re-implementing it silently risks duplicating work or reviving a
deliberately discarded design. Forcing the human to reopen makes the
intent explicit and creates an audit trail.

## After successful fetch

Continue to the claim step (`references/claim-issue.md`). The fetched
JSON (title, body, comments) becomes the input for change-intent
extraction in Step 5.
