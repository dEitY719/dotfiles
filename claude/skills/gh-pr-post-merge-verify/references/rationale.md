# Design notes (issue #1511)

## Why an opt-in registry rather than "every repo"

The dispatch opens a real terminal tab and burns a model session. Doing that
for every merge in every checkout on the machine is not a default anyone
would keep. `watched-repos.json` makes the blast radius a list you can read,
and makes "turn it off" a one-line delete rather than an env var nobody
remembers. An unregistered repo must therefore be **byte-identical** to the
pre-#1511 behavior — no `[INFO]`, no herdr call, nothing.

## Why this closes the implementation tab, when #1508 only suggests it

Issue #1508 covers the same `herdr agent list` cwd-matching detection but
stops at *suggesting* that a stale tab be closed. That is not in tension with
closing it here, and the difference is what the two know:

- #1508 detects a tab whose work status is **unknown** — the session may be
  mid-turn, may be waiting on the human, may be finished. Closing on that
  signal would kill live work, so it can only suggest.
- This skill runs on a **specific event**: the PR that tab was opened to
  implement has just been merged and its branch deleted. The tab's reason to
  exist is provably gone. That is a strictly stronger precondition than
  #1508's, so a stronger action follows from it.

Neither supersedes the other, and neither is a prerequisite for the other.

## Why the agent name carries the host

`pmv-<host>-<owner>-<repo>-<N>` mirrors `_PMT_AGENT_PREFIX` in
`shell-common/tools/custom/pr_merge_train_cron.sh` for the same reason:
`owner/repo` alone is not unique across GitHub servers. #1403/#1407 pin the
host on every `gh` call; leaving it out of the session identity would undo
that pinning one layer down, and a github.com checkout and a GHES checkout
sharing a slug would collide on one herdr agent name.

## Why a rebase failure is the only hard stop

Every other failure costs a missing convenience. This one costs a **wrong
answer**: a session started on a stale checkout would verify the previous
commit and report success. For `devx:pr-verify-live` that is immediate and
total (the serving checkout *is* the evidence); for `devx:pr-verify-merged`
the fresh clone insulates the verdict, but the human is still left believing
their `main` is current. So the run stops before any tab is created.

`git rebase --abort` runs on that path. That is restoration, not resolution —
picking sides in a conflict stays the human's call, but leaving the user's
main checkout parked mid-rebase would be a worse failure than the one being
reported.

## Why `herdr agent list` emptiness is "unknown", not "nothing running"

Lesson carried over from `_iw_live_agents` in
`shell-common/tools/custom/issue_watcher_cron.sh`: a herdr that answers
nothing is not a herdr saying no agent is there. Reading it as "nothing
running" is the one mistake this signal cannot afford. Matching also uses
**both** `cwd` and `foreground_cwd` (the pane's opening directory and where
its shell stands now), prefix-matches on the **physical** path (a worktree can
be reached through a symlink), and refuses an empty path outright — an empty
prefix matches every agent and would close an unrelated tab.

## Why the pane id is read by leaf name

`herdr tab create` answers `.result.pane.pane_id` and `herdr workspace create`
answers `.result.root_pane.pane_id`; the CLI is free to add a third parent.
`pmv_json_first` scans for the first string under a flat key **anywhere** in
the document, so both shapes resolve without hardcoding a path — the same
helper as `_pmt_json_first`. Confirmed against herdr 0.7.5, whose
`herdr worktree list --json` answers `.result.source.source_workspace_id` for
the checkout it is asked about and `open_workspace_id` on each worktree entry.

## Out of scope, deliberately

- The unattended cron path (`pr_merge_train_cron.sh`) is untouched.
- No follow-up action when the verification itself fails — reading the result
  is the human's job.
- No batching or session cap when several PRs merge in a row: one session per
  PR, chosen for predictability over thrift.
