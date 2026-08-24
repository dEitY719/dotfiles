# gh:issue-implement — Fetch Issue

## Command

```bash
GH_HOST="$TARGET_HOST" gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,state,comments,url
```

`GH_HOST` and `--repo` are both mandatory and both come from Step 1's
remote URL (`references/repo-resolution.md`). Never drop either — a bare
`gh issue view <N>` follows gh CLI's own default repo and, on a dual-host
login, reports "issue not found" for an issue that is OPEN on the other
host (#1403).

## Error handling

- On non-zero exit (issue not found, auth failure, network) → print
  the captured stderr verbatim and stop. Do not retry, do not fall
  back to a different repo.
- "not found" 를 만나면 재시도 전에 `GH_HOST` 와 `--repo` 가 실제로 붙어
  나갔는지부터 확인한다 — 그 조합이 빠졌을 때의 대표 증상이 바로 이
  메시지다 (#1403).

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
