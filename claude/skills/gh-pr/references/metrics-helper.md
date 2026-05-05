# Metrics Helper — token compute for the gh:pr footer

Used in Step 4 of `gh:pr/SKILL.md` when building the `<!-- ai-metrics:gh-pr -->`
footer block. The token estimate must reflect the AI input load that produced
the PR — that's **(linked-issue body) + (commit log over `<base>..HEAD`)** —
not the drafted PR body itself.

## Why a code-ified helper

Issue #326 traced PR #325's `📊 ~1000 tokens` footer to a Step 4 execution
that counted `wc -m < "$BODY"` (the PR-body temp file) instead of the
issue-body + commit-log pair. The natural-language spec ("character count
of (issue body + commit log) ÷ 4") didn't bind tightly to a variable name
at execution time, so the executor fell back to the closest in-scope file
(`$BODY`) and the footer under-reported by ~7×.

This file pins the exact bash so the inputs cannot drift again.

## Snippet — paste into Step 4 verbatim

```bash
compute_pr_tokens() {
    local _issue_body="$1" _commit_log="$2"
    local _total _t
    _total=$((
        $(printf '%s' "$_issue_body" | wc -m) +
        $(printf '%s' "$_commit_log" | wc -m)
    ))
    _t=$(( (_total / 4 + 250) / 500 * 500 ))
    [ "$_t" -lt 1000 ] && _t=1000
    printf '%s\n' "$_t"
}

ISSUE_BODY=""
if [ -n "${ISSUE_NUMBER-}" ]; then
    # gh resolves the repo from the current dir if --repo is omitted;
    # callers that already have $TARGET_REPO bound can pass it explicitly.
    if [ -n "${TARGET_REPO-}" ]; then
        ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --repo "$TARGET_REPO" \
            --json body --jq .body 2>/dev/null) || ISSUE_BODY=""
    else
        ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" \
            --json body --jq .body 2>/dev/null) || ISSUE_BODY=""
    fi
fi
COMMIT_LOG=$( { git log "$BASE_BRANCH..HEAD" --format=%B; \
                git diff "$BASE_BRANCH...HEAD"; } 2>/dev/null )

TOKENS=$(compute_pr_tokens "$ISSUE_BODY" "$COMMIT_LOG")
```

The two inputs are computed explicitly. `$BODY` (the PR body temp file) is
deliberately not referenced — it's the wrong input.

## Regression case — PR #325

| Input | Char count |
|---|---|
| Issue #324 body                                   | ~13 800 |
| `git log main..HEAD --format=%B` + `git diff`     | ~13 200 |
| **Total**                                         | ~27 000 |
| `total / 4`                                       | ~6 750  |
| Rounded to nearest 500                            | **7 000** |

A re-run of the helper on PR #325's range must yield 7 000 (±500 for diff
drift on the same commit set), never 1 000.

## Boundary fixtures

- Both inputs empty → `compute_pr_tokens "" ""` returns `1000` (floor).
- Tiny PR (total ≈ 50)        → `1000` (floor).
- Mid PR  (total ≈ 12 000)    → `3000`.
- Large PR (total ≈ 80 000)   → `20000`.

Numbers match `(total / 4 + 250) / 500 * 500` exactly. Any drift in the
formula must update both this table and the snippet above.

## What `compute_pr_tokens` does NOT do

- Does not fall back to the PR body when the issue body is unavailable.
  Empty issue body is fine — the commit log alone usually pushes the
  estimate past the 1000 floor on any non-trivial PR.
- Does not include review comment bodies, CI logs, or AI scratchpads.
  The footer is a coarse "AI input weight" signal, not a full
  reconstruction of the conversation.
