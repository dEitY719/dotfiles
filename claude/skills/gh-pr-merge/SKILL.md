---
name: gh:pr-merge
description: >-
  Merge an approved GitHub PR — rebase by default, or squash/merge — without
  asking. Use for /gh:pr-merge, /gh-pr-merge, "PR 51 머지해", "squash merge", "#99
  머지". Refuses un-approved PRs, failing CI, drafts, conflicts — bypass is
  gh:pr-merge-emergency.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr merge wrap with policy/preflight gate; bounded mutation, no deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-merge — Merge Approved PR (3 strategies)

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and stop
(no API calls). That file also tables the positionals
`<pr-number> [rebase|squash|merge] [remote]` and the per-strategy guidance.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Bind `TARGET_REPO` **and** `TARGET_HOST` from
  that one remote URL and `export GH_HOST` per `references/github-target.md`
  (#1403/#1407). Missing remote → list `git remote -v`, stop (no silent fallback).
- `--auto` — optional flag, any position after the positionals (#1707). Merge
  **fire-and-forget**: hand the PR to the base branch's merge queue instead of
  blocking until it merges. Step 3 and Step 3.5 below own the behavior.
- `--finalize` — optional flag, any position (#1707). Run **only** the
  post-merge completion sequence on a PR that is **already merged**, then stop:
  skip Step 2 and Step 3 entirely, jump straight to Step 4 per
  `references/finalize-merged-pr.sh.md`, and print `[FINALIZED] #<N>` instead
  of `[OK] PR #<N> merged`. `gh:pr-merge-train`'s Step 0 sweep is its only
  caller. If `gh pr view <N> --json state` is not `MERGED`, print
  `[FAIL] PR #<N> not finalized — state is <state>, expected MERGED` and stop:
  every step in that sequence is a GitHub write that assumes a merge happened.
  `--auto` and `--finalize` together is a usage error — they are the two halves
  of one deferred merge, never one invocation.

## Step 2: Pre-flight (parallel)

Run in one message: `GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
and `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required`.

Then detect base-branch protection via
`GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/branches/<baseRefName>/protection"` (exit 0 →
present; 403/404 → absent). The exact protection-vs-`reviewDecision` behavior
table is in `references/strategy-selection.md` → "Branch protection detection".

**Hard stops** (full table in `references/strategy-selection.md` →
"Hard-stop decisions"): `state != OPEN`; `isDraft`; `mergeable ==
CONFLICTING`; `mergeStateStatus ∈ {BEHIND, BLOCKED, DIRTY}`; any required
check FAILURE/pending; `reviewDecision != APPROVED` → suggest
`/gh-pr-merge-emergency`. Conditional exception: protection **absent**
**AND** `reviewDecision == ""` → accept and print
`INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
(a non-empty non-APPROVED value still stops).

The projectV2 board Status is **not** a merge gate (#1513) — do not read it
here. Rationale + the retired Step 2-B in `references/board-policy.md`.

## Step 3: Merge (no confirmation)

Without `--auto` — the default, unchanged:

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

With `--auto` (#1707), paste this block instead. It **tries the queue-aware
form first and falls back to the line above**, so the flag can never be the
reason a merge that would otherwise have worked does not:

```bash
# Substitute PR_NUMBER / TARGET_REPO / TARGET_HOST / STRATEGY_FLAG (one of
# --rebase / --squash / --merge, per references/strategy-selection.md).
#
# `--auto` is the whole point of #1707: with a merge queue active on the base,
# it hands the PR to the queue and returns immediately, so N PRs cost ONE
# batched CI cycle instead of N serial rebase+CI round trips.
#
# What `--auto` does on a base with NO merge queue, verified against
# cli/cli v2.45.0 `pkg/cmd/pr/merge/merge.go` (the version installed here):
# gh computes `autoMerge = --auto AND NOT isImmediatelyMergeable(state)`, and
# `CLEAN` IS immediately mergeable — so for the only PRs the train ever merges
# (the D-1 `CLEAN`/`MERGEABLE` row), `--auto` collapses to the ordinary
# `mergePullRequest` mutation and the PR merges immediately, exit 0, branch
# deleted. The flag is a genuine no-op there, not a hopeful one.
#
# The fallback covers the case that is NOT a no-op: a PR gh does not consider
# immediately mergeable, where `--auto` really does reach
# `enablePullRequestAutoMerge` — a mutation GitHub refuses outright when the
# repo has `allow_auto_merge: false`, which is the CURRENT state of
# dEitY719/dotfiles. Without the retry, that path would fail a merge the
# pre-#1707 skill would have completed, on a train the 5-minute cron runs
# unattended. See
# ../../gh-pr-merge-train/references/merge-queue-investigation.md.
#
# Deliberately NO error-string matching: gh's and GitHub's wording for
# "auto-merge is not available here" has several forms and is not a stable
# API. Retrying the plain merge on ANY failure costs one extra call on a path
# that was already failing, and the second failure is the one reported — which
# is exactly the error the pre-#1707 skill would have printed.
#
# Caveat, same source: when a merge really IS deferred, gh returns before the
# merge happens and `--delete-branch` silently does nothing in that run (it
# returns early on the deferred path, with no warning). The head branch is
# then GitHub's "Automatically delete head branches" setting to clean up, not
# this skill's. Nothing downstream depends on it: the train's tab-close reads
# the LOCAL worktree branch, which `--delete-branch` never touched anyway.
if MERGE_OUT=$(GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
        "$STRATEGY_FLAG" --delete-branch --auto 2>&1); then
    printf '%s\n' "$MERGE_OUT"
else
    printf '[INFO] gh:pr-merge: --auto refused (%s) — retrying the plain merge.\n' \
        "$(printf '%s' "$MERGE_OUT" | tr '\n' ' ')"
    GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
        "$STRATEGY_FLAG" --delete-branch
fi
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns
"merge method is not allowed", print the repo-settings guidance from
`references/strategy-selection.md` and stop. **Never** silently switch
strategies.

## Step 3.5: Did it actually merge? (`--auto` only)

Skip this step entirely unless `--auto` was given — without the flag, Step 3
returning success means the PR is merged, exactly as before.

With `--auto`, success means "GitHub accepted responsibility for the merge",
which is **not** the same as "the PR is merged". Ask:

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json state,mergedAt
```

| `state` | Meaning | Do |
|---|---|---|
| `MERGED` | the queue was off, or the PR merged immediately | continue to Step 4 exactly as today |
| `OPEN` | **queued, not yet merged** | print the `[QUEUED]` report below and **stop** — run none of Step 4, none of Step 5 |
| `CLOSED` | someone closed it out from under us | `[FAIL] PR #<N> not merged — closed` |

```
[QUEUED] PR #<N> added to merge queue — not yet merged
  Branch:  <headRefName> → <baseRefName>
  URL:     <pr-url>
```

`[QUEUED]` is a **third outcome**, not a dressed-up success and not a failure:
nothing went wrong, and nothing is finished. Running Step 4/5 here would sync
a board to `Done`, post an ai-metrics footer and dispatch a post-merge
verification for a merge that has not happened — and dropping `review-passed`
would destroy the one signal that says this PR still owes a completion pass.
`gh:pr-merge-train`'s Step 0 sweep finalizes it on a later tick
(`_gh_pr_merge_train_needs_finalize`, `references/finalize-merged-pr.sh.md`).

## Step 4: Sync Project Board Status

Steps 4 and 5 together are **the post-merge completion sequence**, and its
membership and order are defined once in `references/finalize-merged-pr.sh.md`
(#1707). `--finalize` re-enters at exactly this point, running the same six
steps against a PR the merge queue merged with no session watching — same
order, same SSOT blocks, only the Step 5 report line differs (`[FINALIZED]`
rather than `[OK]`). Change the sequence there, not only here.

Run the two post-merge board reconciliations (PR card → Done; linked Issue cards
→ Done) per `references/project-board-sync.md` — paste the snippets verbatim
(that file also holds the failure modes and gating rationale). Both helpers
auto-detect repos without a projectV2 attachment and silently return; failures
hit stderr, never block the report.

Then run the herdr idle-tab hint per `references/herdr-tab-notify.sh.md` — one
`[INFO]` line when the merged branch's local worktree still has an idle herdr
tab (soft-fail and read-only; skip entirely when there is no local worktree, no
`herdr`, or the agent is not idle — never close a tab or delete a worktree).

After the board sync completes, post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip entirely when `GH_DISABLE_AI_METRICS=1`).

The `review-passed` label is **not** dropped here — it is the last thing Step 5
does, after every other write and after the post-merge verification dispatch.
That ordering is load-bearing, not tidiness: see
`references/finalize-merged-pr.sh.md`.

## Step 5: Fetch Merge SHA + Report

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").
Under `--finalize` the same report is printed with `[FINALIZED] #<N>` as its
verdict line — the merge SHA and branch fields are identical, only the claim
"this run merged it" is not made twice (#1707).

**After** the report has printed, paste this block verbatim — it is the
post-merge verification gate **and** its dispatch, in one run:

```bash
# Substitute the five values before running; every one of them is already in
# hand from Steps 1-2, so nothing here re-queries GitHub. Bind them all, even
# the ones an earlier step already set: each block runs in its own shell, and
# an unbound TARGET_REPO makes the registry lookup below answer empty — the
# silent no-dispatch #1565 is about.
PR_NUMBER=<N>                 # the merged PR
TARGET_REPO=<owner/repo>      # Step 1's single remote URL, the registry key
HEAD_BRANCH=<headRefName>     # Step 2's `gh pr view` already read it
BASE_BRANCH=<baseRefName>     # ditto — never a hardcoded `main`
REMOTE=<remote>               # the `[remote]` positional, default `origin`

# A binding mistake is not just an empty value — it is also an unsubstituted
# placeholder (`<owner/repo>` left as-is) or a whitespace-only value, both of
# which pass `[ -n ]` and would silently reproduce this same #1576 bug (PR
# #1603 review, agy + codex: "non-empty" != "correctly substituted"). None of
# the three can be told apart from an unwatched repo by the lookup below, so
# name every offender and never look up a half-bound run — the dispatch
# closes tabs and rebases the main checkout.
PMV_MISSING=""
_pmv_need() {
    case "$2" in
    '' | '<'*'>') PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    *[!" "]*) ;;
    *) PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    esac
}
_pmv_need PR_NUMBER "${PR_NUMBER-}"
_pmv_need TARGET_REPO "${TARGET_REPO-}"
_pmv_need HEAD_BRANCH "${HEAD_BRANCH-}"
_pmv_need BASE_BRANCH "${BASE_BRANCH-}"
_pmv_need REMOTE "${REMOTE-}"

WATCHED_FILE="${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}"
VERIFY_SKILL=""
if [ -n "$PMV_MISSING" ]; then
    printf '[WARN] gh:pr-merge: post-merge verification gate has unbound values (%s) — substitute all five values (no placeholders, no blanks) and re-run this block.\n' \
        "$PMV_MISSING"
elif command -v jq >/dev/null 2>&1 && [ -r "$WATCHED_FILE" ]; then
    VERIFY_SKILL=$(jq -r --arg r "$TARGET_REPO" \
        '(if type == "array" then . else (.repos // []) end) | .[] | select(.repo == $r) | .verify_skill // empty' "$WATCHED_FILE" 2>/dev/null)
fi
# Empty VERIFY_SKILL with all five values bound — repo not registered, no
# registry, or no jq, so the feature is simply unavailable — means do nothing
# at all: no output, no dispatch, and no [WARN] either. An unwatched repo
# stays byte-identical to its pre-#1511 behavior.
if [ -n "$VERIFY_SKILL" ]; then
    # gh:pr-post-merge-verify's dispatch block is READ from its SSOT and run
    # here, rather than reached through `Skill(gh:pr-post-merge-verify, ...)`.
    # As a Skill() call this step ran 0/10 inside gh:pr-merge-train and 1/1 at
    # top level, while every pasted block in Step 4 ran 10/10 — and a tab that
    # is never closed starves issue-watcher's _IW_MAX_PER_REPO budget (#1565).
    PMV_BLOCK="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md"
    # The fence marker is built with printf, never typed, so this block can sit
    # inside a fenced block of its own without closing it. Only the FIRST bash
    # fence is taken — the file's later snippets are documentation, not steps.
    PMV_FENCE=$(printf '\140\140\140')
    if [ -r "$PMV_BLOCK" ] && PMV_SH=$(mktemp 2>/dev/null); then
        # The staged file must not outlive this block. The sourced dispatch
        # returns early on most of its paths, and a caller running under
        # `set -e` can leave the shell entirely between the two lines below —
        # so cleanup is armed before anything can go wrong and cleared on the
        # success path, the same shape as _PMT_ERRF in
        # shell-common/tools/custom/pr_merge_train_cron.sh.
        trap 'rm -f "$PMV_SH"' EXIT INT TERM
        awk -v f="$PMV_FENCE" \
            '$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b' \
            "$PMV_BLOCK" >"$PMV_SH"
        # shellcheck source=/dev/null
        . "$PMV_SH"
        rm -f "$PMV_SH"
        trap - EXIT INT TERM
    else
        printf '[WARN] gh:pr-merge: could not stage %s — post-merge verification skipped.\n' "$PMV_BLOCK"
    fi
fi
```

The dispatch owns every step and every failure mode from there (all soft-fail,
so the report above stands regardless), and re-runs the same registry gate on
its own so it stays usable standalone. Detail:
`claude/skills/gh-pr-post-merge-verify/SKILL.md`.

**Last of all** — after the report, after ai-metrics, after the dispatch block
above has returned — drop the now-readerless `review-passed` label per
`references/review-passed-cleanup.sh.md` — `_gh_pr_drop_label "$PR_NUMBER"
review-passed "$TARGET_REPO" "$TARGET_HOST"` (#1636, soft-fail: the merge
already succeeded, so a failed delete is one `[WARN]` line and never touches
the report or the exit status).

This is the **last** write of the sequence on purpose (PR #1725, codex
BLOCKER). That label is the only signal `_gh_pr_merge_train_needs_finalize`
matches on, so dropping it while any later step is still outstanding makes a
run that dies in between permanently undiscoverable by the next tick's Step 0
sweep. Ordering it here bounds an interrupted run to "gets swept again next
tick" — every step above is idempotent enough to repeat.
`references/finalize-merged-pr.sh.md` owns the full rationale.

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh:pr-merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.
- Never run Step 4/5's completion steps for a PR that is not `MERGED` (#1707).
  A `[QUEUED]` PR keeps its `review-passed` label — that label is what a later
  `gh:pr-merge-train` Step 0 sweep matches on, and dropping it early makes the
  finalize pass unfindable.

## Related Skills

`gh:pr-approve` produces the approval this skill gates on · `gh:pr-merge-emergency`
is the admin-override path when approval cannot be obtained · `gh:pr-post-merge-verify`
owns the dispatch block Step 5 runs inline for repos registered in
`${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}`,
and stays a standalone manual entry point
(`/gh-pr-post-merge-verify <N>`) · `gh:pr-merge-train` is the only caller of
`--auto` and `--finalize`: its per-PR merge passes the first, and its Step 0
sweep passes the second to finish PRs the merge queue merged unattended
(#1707).
