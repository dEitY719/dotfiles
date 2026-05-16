# Create — Step 5 implementation

Substep procedure for Step 5 ("Confirm + Create") of `SKILL.md`. The
mutation surface is intentionally small: one `gh issue create`, one
optional comment on the parent issue, and nothing else.

## 5.1 — Preview

Write the rendered body (per `references/issue-body-template.md`) to:

```
.claude/.pr-to-ssot.<PR#>.draft.md
```

Print the first ~40 lines of the draft so the audit block (Section 6)
and the bucket table (Section 2) are visible inline. The audit reason
is the highest-value preview content — keep it inside the first 40
lines.

## 5.2 — `--dry-run` exit

If `--dry-run` is set:

- Stop here.
- Print `[DRY-RUN] devx:pr-to-ssot-issue pr=#<N> draft=<path> ...` per
  `references/report-format.md`.
- Exit 0.

No GitHub mutation, no `Next:` hint (the issue doesn't exist yet —
`/gh-issue-flow <N>` would be wrong).

## 5.3 — Label pre-validation

```
gh label list --repo "$TARGET_REPO" --json name --jq '.[].name'
```

Compare against the labels passed via `--label` (default
`documentation`, `priority:medium`). Any miss → stop with:

```
[FAIL] devx:pr-to-ssot-issue reason=missing-label pr=#<N>
  Detail: label "<name>" not present on $TARGET_REPO.
  Fix: create the label manually (`gh label create ...`), then re-run.
```

**Never POST `/labels`.** Memory: `feedback_gh_label_no_autocreate.md`.

## 5.4 — Milestone pre-validation (optional)

If `--milestone <name>` is set:

```
gh api repos/$TARGET_REPO/milestones --jq '.[].title'
```

Missing → stop with `reason=missing-milestone`. Inherited milestone
from parent / PR is OK to skip the validation step entirely (the
inherited value is already known to exist).

## 5.5 — Issue create

```
gh issue create \
    --repo "$TARGET_REPO" \
    --title "<rendered title>" \
    --body-file "<draft path>" \
    --label "<label-1>" [--label "<label-2>" ...] \
    [--milestone "<name>"]
```

Capture the issue URL from stdout (`gh issue create` prints the URL on
success). Extract the number for the report:

```
NEW_ISSUE_URL=$(...)
NEW_ISSUE_NUM=$(printf '%s\n' "$NEW_ISSUE_URL" | sed 's|.*/issues/||')
```

`gh issue create` failure → stop with `reason=gh-create-failed` and
the stderr passed through to the report's `Detail:` line.

## 5.6 — Parent backlink comment (optional)

When `--parent <issue#>` is set **and** `GH_DISABLE_AI_METRICS != 1`:

```
gh issue comment <parent-issue#> --repo "$TARGET_REPO" --body \
    "> 역공학 SSOT 이슈가 등록됐습니다 — #${NEW_ISSUE_NUM}. 원본 PR: #<PR#>."
```

This is the only secondary mutation. Failure here is **soft-fail** —
warn but do not roll back the new issue:

```
[WARN] parent backlink failed (<reason>) — new issue #<N> still
created. Manually link or re-run with `gh issue comment <parent> ...`.
```

`GH_DISABLE_AI_METRICS=1` suppresses the entire backlink — parity
with `gh-issue-flow` Step 2.6 (issue #399).

## 5.7 — Source PR is read-only

Reminders for the implementer:

- Never `gh pr edit <PR#>` — no label / body / milestone change.
- Never `gh pr comment <PR#>` — the new issue is the canonical
  pointer; the PR thread stays clean.
- Never `gh pr review <PR#>` — reviewing the PR is out of scope.

If a future variant needs to touch the PR (e.g. add a `tracked-by-#<N>`
label), route it through a sister skill (`/devx:exception-merge-checklist`)
rather than relaxing this read-only rule.

## Pairs with

- `SKILL.md` Step 5 — invocation site.
- `references/issue-body-template.md` — what gets written to the draft
  file.
- `references/metrics-footer.md` — the `GH_DISABLE_AI_METRICS` parity.
- `references/report-format.md` — the failure templates referenced
  here.
