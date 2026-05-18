# gh:pr-resolve-ci-fail — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<pr-number>` or `-h`/`--help`/`help` | current-branch PR | Target PR, e.g. `803` |
| 2 | remote-name | `origin` | Git remote whose repo owns the PR |
| flag | `--wait <seconds>` | off | Opt-in: poll CI green before label removal |
| flag | `--label-variant <input>` | `CI fail` | Override canonical label (normalized via `references/label-normalization.md`) |

## Usage

```
/gh-pr-resolve-ci-fail              # PR attached to current branch, origin
/gh-pr-resolve-ci-fail 803          # explicit PR, origin
/gh-pr-resolve-ci-fail 803 upstream # explicit PR, upstream remote
/gh-pr-resolve-ci-fail 803 --wait 300       # wait up to 5 min for CI green before label removal
/gh-pr-resolve-ci-fail --label-variant "CI fial"  # accept user's typo, normalize internally
/gh-pr-resolve-ci-fail -h           # this help
```

## When to use this skill

- A PR has a `CI fail` label (or variant) blocking re-Approve.
- Required CI checks are red and you've identified the cause is a fixable
  code defect (not flake).
- You want to stay on the no-force-push policy track — this skill refuses
  `--force` and `--force-with-lease`.

## When NOT to use

- CI red because of flake / infra outage. Re-run the workflow, don't
  open a code fix.
- Merge conflict on the PR (use `/gh-pr-resolve-conflict` instead).
- Review comments need replies (use `/gh-pr-reply` after CI green).
- You want to admin-bypass and merge without fixing CI
  (use `/gh-pr-merge-emergency` with audit trail).
- You're on the repo's default branch — refuses, check out the PR's
  head branch first.

## What the skill does

1. Parses args. Auto-detects the PR from the current branch if omitted.
2. Prints a **backup SHA** so `git reset --hard <sha>` can undo edits.
3. Refuses if working tree is dirty (unrelated edits may be in flight).
4. Fetches failing required checks via `gh pr checks --required`.
5. For each failure: dumps `gh run view --log-failed`, identifies cause.
6. Edits failing files, runs the same lint/test command CI ran.
7. Local lint/test still red → stops (CI infinite-loop guard).
8. Commits `fix(ci): <summary> (#<PR_NUMBER>)` and `git push` (no force).
9. Optionally polls CI green if `--wait <seconds>` was passed.
10. Removes the `CI fail` label via REST DELETE (last step, soft-fail).

## Safety

- **No force-push** — `--force` and `--force-with-lease` both refused.
  Fast-forward only. Rebased history would require `gh:pr-resolve-conflict`.
- **Local validation gate** — push only runs after the same lint/test
  command CI ran exits 0 locally. Stops the "push → CI red → fix → push
  → CI red" infinite loop.
- **Label is the LAST mutation** — push must succeed before the label
  comes off. Premature removal misleads reviewers into re-approving red.
- **No auto-stash** — working tree must be clean. The user's local
  edits may be unrelated context the skill shouldn't touch.
- **No blind retry** — if log analysis can't identify a concrete fix,
  the skill surfaces the log and stops.

## What this skill will NOT do

- Force-push (`--force` or `--force-with-lease`). Non-negotiable.
- Run on the repo's default branch.
- Auto-create the `CI fail` label if missing — soft-fail with a warning.
- Auto-stash a dirty working tree.
- Push when local lint/test fails.
- Delegate the commit step to `gh:commit` — inline commit only, to
  avoid re-prompts inside a composition.
- Resolve merge conflicts (that's `/gh-pr-resolve-conflict`).
- Reply to review comments (that's `/gh-pr-reply` after CI green).

## Related skills

- `gh:pr-resolve-conflict` — sister skill, rebase-resolves a base-moved
  PR conflict warning. Different verb (rebase vs read-logs-and-edit).
- `gh:pr-reply` — reply to PR review comments after CI is green.
- `gh:pr-approve` — review and approve a PR (after CI green).
- `gh:pr-merge` — merge an already-clean PR (rebase/squash/merge).
- `gh:pr-merge-emergency` — admin-bypass merge with audit trail.
