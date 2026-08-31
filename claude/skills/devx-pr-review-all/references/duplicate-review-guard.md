# devx:pr-review-all — Duplicate-review guard

SSOT for how Step 3 avoids re-running a reviewer lane that already reviewed the
PR's current head. Implementation: `devx_pr_review_all_already_reviewed` in
`shell-common/functions/devx_pr_review_all.sh`; regression suite:
`tests/bats/functions/devx_pr_review_all_dedupe.bats`. Issue: #1613.

Why it exists: nothing gated the fan-out on "has this already been reviewed?".
On PR #1608 two sessions reviewed the same head sha `2d7bbdca` 36 minutes
apart, so agy and codex each ran twice and posted duplicate review comments —
wasted reviewer budget, and a comment thread where a reader cannot tell a
re-review from a second opinion.

## The algorithm

Once, before any lane is dispatched:

```sh
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh"

head_sha=$(GH_HOST="$TARGET_HOST" gh pr view "$pr" --repo "$TARGET_REPO" \
    --json headRefOid --jq .headRefOid)

BODIES=$(GH_HOST="$TARGET_HOST" gh api --paginate \
    "repos/$TARGET_REPO/issues/$pr/comments" --jq '.[].body')
```

Then per lane, before dispatching its Agent:

```sh
if [ "$force_review" != "1" ] &&
    printf '%s\n' "$BODIES" | devx_pr_review_all_already_reviewed "$ai" "$head_sha"; then
    echo "[SKIP] $ai already reviewed head $head_sha — pass --force-review to re-run"
    continue
fi
```

`devx_pr_review_all_already_reviewed` is a thin wrapper over
`devx_pr_review_all_lane_block "$ai" "$head_sha"`: rc 0 when that lane has a
complete `<!-- ai-review:<ai>:<head-sha> -->` block, rc 1 otherwise. One parser
for the marker grammar, so the guard and Step 3.5's verdict harvester can never
disagree about what "already reviewed" means. The `<head-sha>` is mandatory
here — without it an older, untagged block would match and every re-review
would be skipped forever.

A guard-skipped lane reports `[SKIP]` and contributes **no** verdict line to
Step 3.5, exactly like a missing CLI. Its earlier verdict is still on the PR
under the same head sha, so the label that run wrote still stands.

## Why here, not inside `gh:pr-review`

`gh:pr-review` is single-shot per invocation: one AI, one PR, one comment. It
has no concept of "another session already ran this lane", and adding one would
put a network read in front of every direct `/gh-pr-review` call — including
the deliberate re-reviews that skill exists to serve. The fan-out orchestrator
is the only layer that knows it is issuing a *batch* and can amortize one
shared `head_sha`/`BODIES` fetch across all of it.

## Why it fails open

A `gh pr view` / `gh api` error here must not abort the review: treat every
lane as not-yet-reviewed and dispatch normally. The worst case is the duplicate
comment this guard merely optimizes away, whereas failing closed would skip a
real review and leave the PR unverified. Same NF-1 soft-fail posture as the
3.3b duplicate-open-PR guard in `gh:issue-implement`, which this parallels —
and the opposite of Step 3.5's fail-**closed** freshness rule
(`review-verdict-label.md`), correctly so: that gate authorizes a merge, this
one only decides whether to spend a reviewer.
