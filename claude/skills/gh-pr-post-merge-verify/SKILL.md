---
name: gh:pr-post-merge-verify
description: >-
  Closes the impl tab, rebases main, opens a herdr session for the repo's
  verify skill. Use for /gh:pr-post-merge-verify, /gh-pr-post-merge-verify,
  "머지 후 검증 세션", "post-merge verify". Dispatch only: gh:pr-merge calls it,
  devx:pr-verify-merged verifies.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "bounded shell/herdr orchestration off a JSON registry; every branch is soft-fail, no judgement calls"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-post-merge-verify — Dispatch a post-merge verification session

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop (no herdr calls, no git calls). That file tables the positionals
`<pr-number> [remote]`.

## Role

Automates the manual post-merge routine for **registered repos only**: close
the tab that implemented the PR, bring the main checkout up to date, and hand
the verification to a fresh session. It never verifies anything itself and it
never touches GitHub — `gh:pr-merge` has already merged and reported by the
time this runs.

**Every failure is soft.** This skill always exits 0 with a one-line `[WARN]`,
because its caller's report must print either way (F-6). The one exception is
a stale main checkout: that stops the run before a session is opened, since
verifying stale code proves nothing.

## Step 1: Gate on `docs/.ssot/watched-repos.json` (F-1)

```bash
WATCHED_FILE="${DOTFILES_ROOT:-$HOME/dotfiles}/docs/.ssot/watched-repos.json"
VERIFY_SKILL=$(jq -r --arg r "$TARGET_REPO" '.[$r].verify_skill // empty' "$WATCHED_FILE" 2>/dev/null)
```

- Empty `VERIFY_SKILL`, or an unreadable file → **do nothing at all**, no
  output. An unwatched repo must behave exactly as it did before #1511.
- `jq` non-zero (the file exists but is not JSON) → one `[WARN]`, then skip.
- `command -v herdr` missing → silent no-op.

Schema and registration procedure: `references/watched-repos-schema.md`.

## Step 2: Resolve the target repo + host

Same binding as `gh:pr-merge` — repo **and** host from one remote URL
(#1403/#1407); see `../gh-pr-merge/references/github-target.md`. No API call
is made: the slug is only the registry key and part of the agent name.

Also bind `HEAD_BRANCH`, the merged PR's head branch. `gh:pr-merge` already
read it in its own Step 2 (`headRefName`) and passes it down; standalone, read
it from the PR the same way, host-pinned and repo-scoped.

## Step 3: Run the dispatch

Paste `references/dispatch.sh.md` verbatim. It performs, in order:

1. `git worktree list --porcelain` → the local path of the merged head branch.
2. `herdr agent list` → the `tab_id` whose `cwd`/`foreground_cwd` sits on that
   path → `herdr tab close <tab_id>`. Not found → note it and continue (F-2).
3. `git -C "$MAIN_ROOT" fetch origin main && git -C "$MAIN_ROOT" rebase origin/main`.
   Dirty tree or conflict → `[WARN]`, `rebase --abort`, **stop** (F-3).
4. `herdr tab create --workspace <ws> --cwd "$MAIN_ROOT" --label "pr-<N>"` (F-4).
5. `herdr agent start pmv-<host>-<owner>-<repo>-<N> --kind claude --pane <pane>
   -- --dangerously-skip-permissions` (F-4).
6. `herdr agent prompt <agent> "/<verify-skill> <N>" --wait --until idle` (F-5).
7. Report the new `tab_id`, the agent name, and the `herdr agent attach` hint.

The executable form of every decision above is mirrored in
`tests/bats/skills/_fixtures/gh_pr_post_merge_verify.sh` — change one, change
both.

## Constraints

- Never resolve a rebase conflict, and never `--force` anything.
- Never open more than one session per PR — no batching, no retries.
- Never write to GitHub. Never touch the unattended
  `pr_merge_train_cron.sh` path (out of scope by #1511's non-goals).
- Never act on a repo missing from `watched-repos.json`.

## Related Skills

`gh:pr-merge` invokes this at the end of its Step 5 · `devx:pr-verify-merged`
/ `devx:pr-verify-live` are what the dispatched session actually runs (the
registry picks which) · `gh:pr-merge-train` shares the herdr
workspace→tab→agent→prompt sequence via `pr_merge_train_cron.sh`.
