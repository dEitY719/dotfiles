# gh:issue-proceed — Fetch Issue

## Command

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,state,labels,assignees,comments,url
```

## Error handling

- On non-zero exit (issue not found, auth failure, network) → print the
  captured stderr verbatim and stop. Do not retry, do not fall back to a
  different repo.

## Closed-issue refusal (precedes schema check)

If the parsed `state` is `CLOSED`, stop with this exact message:

```
Issue #<N> is CLOSED. Refuse to proceed on a closed directive — reopen it
or pass a different number.
```

Rationale: a closed directive has either been executed or retired.
Re-executing it silently risks duplicating side-effects (re-filing issues,
re-opening PRs) or reviving a deliberately retired protocol. Forcing the
human to reopen makes intent explicit and creates an audit trail. This
refusal runs **before** schema validation — there is no point validating a
protocol we will not execute.

## After successful fetch

Continue to the claim substeps (`references/claim.md`). The fetched JSON
(`body`, `labels`, `assignees`, `comments`) is reused by claim (labels /
assignees), schema validation (body), and the execution loop (body).
Call `gh issue view` once, parse the JSON multiple times.
