# gh:pr-merge — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<pr-number>` or `-h`/`--help`/`help` | — | GitHub PR number (required unless help) |
| 2 | strategy | `rebase` | One of `rebase`, `squash`, `merge` |
| 3 | remote-name | `origin` | Git remote whose repo owns the PR |

## Usage

- `/gh-pr-merge 51` — rebase-merge PR #51 on `origin`'s repo (immediate, no confirmation)
- `/gh-pr-merge 51 squash` — squash-merge
- `/gh-pr-merge 51 merge` — create a merge commit (preserve history)
- `/gh-pr-merge 51 rebase upstream` — rebase-merge against `upstream` remote
- `/gh-pr-merge -h` / `--help` / `help` — print this help

## Strategy guide

- **`rebase`** (default) — linear history. GitHub web "Rebase and merge" button. Best for feature branches with clean commits.
- **`squash`** — collapse all PR commits into one. GitHub web "Squash and merge" button. Best for PRs with noisy WIP commits.
- **`merge`** — preserve all commits + add a merge commit. GitHub web "Create a merge commit" button. Best when commit history carries meaning (releases, multi-author collaboration).

_Availability depends on repo settings → General → Pull Requests. If a strategy is disabled the skill stops with a guidance message — it does NOT fall back to another strategy._

## What the skill does

1. Parses args. Validates strategy ∈ {rebase, squash, merge}.
2. Resolves target repo from remote.
3. Pre-flight (in parallel):
   - PR state, draft status, mergeable, mergeStateStatus, reviewDecision
   - `gh pr checks` — required checks must pass
4. Hard-stops on any of:
   - PR not OPEN / is draft / has merge conflicts
   - Review decision ≠ APPROVED → suggests `gh:pr-merge-emergency` instead
   - Required check failing or pending
5. Runs `gh pr merge <N> --repo $TARGET_REPO --<strategy> --delete-branch` **without confirmation**.
6. Fetches the merge SHA and prints a compact report.

## What the skill will NOT do

- Ask "proceed?" — running the skill IS the confirmation.
- Fall back to another strategy on failure.
- Merge an un-approved PR — use `gh:pr-merge-emergency` for admin bypass with audit trail.
- Keep the head branch — always `--delete-branch`.

## Solo / personal repo behavior

GitHub disallows PR authors from self-approving, and Branch Protection
Rules are locked on Free-plan private repos. The combination leaves
`reviewDecision` permanently empty (`""`) on solo repos — so a strict
`APPROVED` check would make this skill unusable without routing every
merge through `gh:pr-merge-emergency`.

To avoid that, the skill detects whether the base branch has protection:

- `gh api "repos/<owner>/<repo>/branches/<baseRefName>/protection"` returning
  HTTP 200 → protection **present** → strict `APPROVED` required.
- HTTP 403 (Free plan locks the feature) or 404 (not configured) →
  protection **absent** → empty `reviewDecision` is accepted and the
  skill prints `INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`

Non-empty non-APPROVED values (`CHANGES_REQUESTED`, `REVIEW_REQUIRED`)
still hard-stop regardless of protection — someone explicitly blocked
the PR, and protection absence does not override that signal.

### When to use which skill

| Situation | Skill |
|---|---|
| Protected base, reviewer approved | `gh:pr-merge` |
| No branch protection (solo repo), no blocking review | `gh:pr-merge` (auto-accepts empty `reviewDecision`) |
| Protected base, needs bypass for incident/hotfix | `gh:pr-merge-emergency` (forces audit comment + incident issue) |
| Protected base, explicit `CHANGES_REQUESTED` | neither — address the review or use emergency-merge with a written reason |
