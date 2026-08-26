# gh:pr-merge-train — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `[owner/repo]` or `-h`/`--help`/`help` | the `[remote]`'s repo | Target repository, e.g. `acme/dotfiles`. The cron dispatcher always passes one. |
| 2 | `[remote]` | `origin` | Git remote whose URL pins the **host** (never the slug — a slug carries no host). |

## Usage

```
/gh-pr-merge-train                      # this checkout's origin repo
/gh-pr-merge-train acme/dotfiles        # explicit repo, host from origin
/gh-pr-merge-train acme/dotfiles upstream   # explicit repo, host from upstream
/gh-pr-merge-train -h                   # this help
```

## When to use this skill

- `gh:issue-flow` ran in parallel and left **several open PRs** behind. Merging
  the first one pushes every other one `BEHIND`, and a conflict or a red CI on
  top of that means picking a different remediation skill per PR, repeatedly.
- You want the queue drained unattended — the cron dispatcher
  (`shell-common/tools/custom/pr_merge_train_cron.sh`) exists for exactly that.

## When NOT to use

- **One PR.** Use `gh:pr-merge` (and `gh:pr-resolve-outdated` / `-conflict` /
  `-ci-fail` if it needs cleanup first). A train over one PR is pure overhead.
- **A colleague's PR.** The train is `--author @me` only (D-7) and will not see
  it.
- **You need an admin bypass.** The train never calls
  `gh:pr-merge-emergency` (NF-2). Run that skill yourself, deliberately.
- **The PRs still need review.** The train does not review; `gh:issue-flow`
  Step 2.4 already ran `devx:pr-review-all`.

## What the skill does

1. Binds `TARGET_REPO` / `TARGET_HOST` from one remote URL (`references/github-target.md`).
2. Lists your own open PRs, drops drafts and anything updated in the last
   **11 minutes** (D-6), and sorts `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`,
   ties by ascending number (D-2).
3. Reads the repo ruleset's `required_approving_review_count` once per
   *distinct base branch* in the queue (rulesets are branch-scoped; a
   single-base queue is one call) — `0` means the platform does not require
   approval, so the approval check is skipped (D-5). Lookup failure is
   **fail-closed**: approval is treated as required.
4. Processes **one PR at a time**. Immediately before each one it re-queries
   state (F-3), because the previous merge changed it.
5. Routes on `mergeStateStatus` / `mergeable` through the D-1 table — the one
   copy lives in `references/routing-table.md`. Which atom each row reaches is
   summarised under "Atom skills it calls" below.
6. Caps remediation at **3 attempts per PR** (F-5). Over that, the PR is
   `[FAILED]` and the train moves on (F-6).
7. Prints a per-PR `[MERGED]` / `[SKIPPED]` / `[FAILED]` report with reasons (F-9).

## What the skill will NOT do

- Merge without knowing state — a failed `gh pr list` ends the run.
- Merge an unapproved PR where the ruleset requires approval, or where the
  ruleset could not be read at all.
- Call `gh:pr-merge-emergency`, or file an incident issue.
- Pass a merge strategy — `gh:pr-merge`'s default rebase is what
  `required_linear_history` allows (D-4).
- Abort the whole train because one PR failed.
- Process two PRs at once.

## Atom skills it calls (all unchanged)

| Skill | Called when |
|---|---|
| `gh:pr-resolve-outdated` | `BEHIND` + `MERGEABLE` — clean rebase onto the moved base |
| `gh:pr-resolve-conflict` | `DIRTY` + `CONFLICTING` — the LLM-judgement row |
| `gh:pr-resolve-ci-fail` | `UNSTABLE` with a failing check — the other LLM-judgement row |
| `gh:pr-merge` | every row that reaches a mergeable state |
| none | `BLOCKED` / `DRAFT` skip; `UNSTABLE` still running and `UNKNOWN` poll first |

## Related skills

- `gh:issue-flow` — produces the parallel PRs this train drains; its Step 2.4
  `--defer-reply 4` is the reason for the 11-minute quiet period.
- `gh:pr-merge` — the single-PR case, and the atom this train ends every PR with.
- `gh:pr-merge-emergency` — deliberately never called (NF-2).
