# gh:pr-post-merge-verify — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<pr-number>` or `-h`/`--help`/`help` | — | The PR that was just merged (required unless help) |
| 2 | remote-name | `origin` | Git remote whose repo owns the PR; binds the repo slug and host |

## Usage

- `/gh-pr-post-merge-verify 51` — dispatch verification for PR #51 on `origin`'s repo
- `/gh-pr-post-merge-verify 51 upstream` — same, against the `upstream` remote
- `/gh-pr-post-merge-verify -h` / `--help` / `help` — print this help

Normally you do not type this: `gh:pr-merge` calls it at the end of its
Step 5. Run it by hand when a merge happened outside `gh:pr-merge`, or when a
dispatch soft-failed and you want to retry it.

## What it does

1. Reads `docs/.ssot/watched-repos.json`. **A repo that is not registered there
   gets nothing at all** — no output, no herdr call, no git call.
2. Checks `command -v herdr`. Missing → silent no-op.
3. `git worktree list --porcelain` → the local worktree of the merged head branch.
4. `herdr agent list` → the tab whose `cwd`/`foreground_cwd` sits on that
   worktree → `herdr tab close <tab_id>`.
5. In the **main checkout** (never a worktree): `git fetch origin main` +
   `git rebase origin/main`.
6. `herdr tab create --cwd <main checkout> --label pr-<N>`.
7. `herdr agent start pmv-<host>-<owner>-<repo>-<N> --kind claude --pane <pane>
   -- --dangerously-skip-permissions`.
8. `herdr agent prompt <agent> "/<verify-skill> <N>" --wait --until idle`,
   where `<verify-skill>` is the registry's `verify_skill` for that repo.
9. Prints the new tab id, the agent name, and a `herdr agent attach` hint.

## What it will NOT do

- Act on a repo missing from `watched-repos.json` — that is the whole opt-in.
- Resolve a rebase conflict, or merge/commit/push anything. A conflict is
  `rebase --abort`-ed so the checkout stays usable, then the run stops.
- Open a verification session on a stale or dirty main checkout. Verifying
  code that is not the merged code proves nothing, so step 5's failure is the
  one hard stop in the skill.
- Open more than one session per PR, batch several PRs into one session, or
  retry a failed dispatch.
- Make any GitHub API call, or touch the PR, the board, or any label.
- Fail its caller. Every other error is one `[WARN]` line and exit 0, so
  `gh:pr-merge`'s report always prints.
- Run from the unattended cron path (`pr_merge_train_cron.sh`) — explicitly
  out of scope in issue #1511.

## Exit behavior

Always 0. `[WARN]` on stdout is the failure channel; there is no failure the
caller is expected to react to.
