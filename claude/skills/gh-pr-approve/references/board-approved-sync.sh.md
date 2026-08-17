# Step 4.5 — promote the PR card to `Approved`

`gh:pr-approve` is the **sole owner** of the `Approved` column (issue
#1350). No other skill may promote a card into it. Run this block right
after the Step 4 review submission succeeds, and only on the paths that
represent a human deciding "this PR is reviewed and ready":

| Step 4 path | Promote? | Bypass needed? |
|---|---|---|
| 4a clean LGTM (`--approve`) | yes | no — `reviewDecision` is now `APPROVED` |
| 4b approve with follow-up issues (`--approve`) | yes | no — same |
| 4c request changes | **no** | — |
| self-PR, `--self-record` | yes | **yes** (`reviewDecision` stays empty forever) |
| self-PR, analysis-only (default) | **no** — no GitHub mutation at all | — |
| self-PR, `--admin-merge` | **no** — the merge itself drives the card to `Done` | — |

## Why `--self-record` needs the bypass

`shell-common/functions/gh_project_status.sh` fail-closes any
`_gh_project_status_sync pr <N> "Approved"` whose `reviewDecision` is not
`APPROVED` (#393). GitHub refuses self-approval server-side, so a solo
repo's own PR is stuck at `reviewDecision == ""` no matter what. The
guard stays in place for every other caller; `--self-record` is the one
place where a human has explicitly said "I reviewed my own PR", so it
carries the single-call bypass.

## Why prefix form, not `env`

`_gh_project_status_sync` is a shell function. `env VAR=val funcname …`
would `exec env` and look for a binary named `_gh_project_status_sync`
on `$PATH` — that fails. The POSIX prefix form `VAR=val funcname …`
scopes the binding to that one invocation, so the main shell never sees
the bypass.

## Why `--only-from "In review"`

Defense-in-depth: the filter refuses to drag a card in from `Backlog` /
`In progress` / `Done`. A re-review on an already-merged PR therefore
cannot resurrect a `Done` card into `Approved`.

## The block (soft-fail — never blocks the Step 5 report)

```sh
# Inputs: PR_NUMBER; BOARD_BYPASS=1 only on the --self-record path.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        printf '[gh-pr-approve] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
            "$_HELPER" >&2
    else
        _rc=0
        if [ "${BOARD_BYPASS:-0}" = "1" ]; then
            printf '[gh-pr-approve] self-record: bypassing #393 fail-closed guard for PR #%s (operator intent).\n' \
                "$PR_NUMBER" >&2
            _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
                _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review" || _rc=$?
        else
            _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review" || _rc=$?
        fi
        if [ "$_rc" -ne 0 ]; then
            printf '[gh-pr-approve] board sync rc=%s — continuing (soft-fail).\n' "$_rc" >&2
        fi
    fi
fi
# helper missing → board sync silently skipped (NF-1, #644).
```

Helper returns `0` on the happy path *and* on a silent no-op (repo has no
projectV2 attachment). `GH_PROJECT_STATUS_SYNC=0` opt-out is absorbed by
the helper itself.

## Report line

Step 5 prints one line so the operator can see what happened:

```text
Board: PR #<N> card -> Approved (only-from "In review")
Board: skipped (rc=<N>) — card may need a manual move
Board: not promoted (request-changes / analysis-only path)
```

## See also

- `references/board-policy.md` — what the `Approved` column means.
- `references/self-pr-handling.md` — the `--self-record` procedure.
- `shell-common/functions/gh_project_status.sh` — #393 write-side guard.
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
