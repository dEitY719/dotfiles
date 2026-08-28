# gh:pr-merge-train — State to action routing (D-1)

Deterministic. No judgement is exercised in this table — the two rows that need
judgement (`DIRTY`, `UNSTABLE`-with-a-failure) delegate it to an atom skill.

## Reading the state

Immediately before processing each PR (F-3):

```bash
STATE=$(GH_HOST="$TARGET_HOST" gh pr view "$N" --repo "$TARGET_REPO" \
  --json number,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName,labels,url)
```

Keep `$STATE`. Every question the rest of this file asks about the PR is
answered by a `jq` over it — re-fetching the same PR to read one more field is
a round trip the state you already hold has covered.

## The table

| `mergeStateStatus` | `mergeable` | Action |
|---|---|---|
| `CLEAN` | `MERGEABLE` | `Skill(gh:pr-merge, "<N>")` directly |
| `BEHIND` | `MERGEABLE` | `gh:pr-resolve-outdated` in a scratch worktree → re-query → merge |
| `DIRTY` | `CONFLICTING` | `gh:pr-resolve-conflict` in a scratch worktree → re-query → merge |
| `UNSTABLE` | `MERGEABLE` | inspect `statusCheckRollup` — see below |
| `BLOCKED` | — | record the reason, `[SKIPPED]` |
| `UNKNOWN` | `UNKNOWN` | poll, then re-evaluate; `[SKIPPED]` after 3 polls |
| `DRAFT` | — | `[SKIPPED]` (a draft is not a merge candidate) |

Four conditions **short-circuit the table** — check all four before reading
`mergeStateStatus` at all:

| Condition | Verdict |
|---|---|
| `isDraft == true` | `[SKIPPED] draft` |
| `labels[].name` contains `reply-pending` | `[SKIPPED] reply-pending — review reply not yet complete` |
| `labels[].name` contains `review-blocked` | `[SKIPPED] review-blocked — reviewer verdict is blocking` |
| `labels[].name` contains neither verdict label | `[SKIPPED] review not verified — no review-passed label` |

```bash
printf '%s' "$STATE" | _gh_pr_merge_train_has_reply_pending_label \
  && echo "[SKIPPED] reply-pending"

# The verdict gate, re-asked (references/review-verdict-gate.md). Order
# matters: review-blocked wins over a stale review-passed.
if printf '%s' "$STATE" | _gh_pr_merge_train_has_review_blocked_label; then
    echo "[SKIPPED] review-blocked — reviewer verdict is blocking"
elif ! printf '%s' "$STATE" | _gh_pr_merge_train_has_review_passed_label; then
    echo "[SKIPPED] review not verified — no review-passed label"
fi
```

All four are defense-in-depth: Step 2 already dropped drafts and
`reply-pending` PRs from the queue via `_gh_pr_merge_train_filter_targets`, and
Step 3.5 already applied the verdict gate to what survived. The re-check earns
its place because a label can be **added or changed mid-run** — a deferred
`devx:pr-review-all` pass can fire minutes after Step 2 built the queue,
adding `reply-pending` (#1524) or flipping a verdict label (#1564) — and
F-3's re-query is the only thing that would see it. A PR whose `review-passed`
turned into `review-blocked` between the queue build and its turn must not
merge on the strength of a snapshot.

`_gh_pr_merge_train_has_reply_pending_label` and the two
`_gh_pr_merge_train_has_review_*_label` predicates are the single-PR siblings
of the array filter — same `gh_pr_merge_train.sh` sourced in Step 2, same
predicates Step 3.5 ran, so the checks cannot drift apart the way the
quiet-minutes number used to. Do not re-derive the `jq` here.

The two rebase rows (`BEHIND`, `DIRTY`) never operate on the current checkout.
The train builds a detached scratch worktree for `headRefName` first and passes
its path to the atom via `--worktree` — that is why `headRefName` is in the
`--json` list above. Mechanics: `train-loop.md` → "Detached scratch worktree".

## `UNSTABLE` — split on the rollup, not on the status

`UNSTABLE` means "mergeable, but a check is not green". Two very different
situations share that word, and conflating them is how a train starts "fixing"
a test that had not finished running:

```bash
printf '%s' "$STATE" |
  jq '[.statusCheckRollup[]? | {name: (.name // .context), status, conclusion}]'
```

| Rollup contains | Action |
|---|---|
| any `conclusion` in `FAILURE` / `TIMED_OUT` / `CANCELLED` / `ACTION_REQUIRED` | `Skill(gh:pr-resolve-ci-fail, "<N>")` |
| only `IN_PROGRESS` / `QUEUED` / `PENDING` | **wait** — poll, do not call a fix skill |
| everything `SUCCESS` / `NEUTRAL` / `SKIPPED` | re-query; the state is about to become `CLEAN` |

Waiting means the poll loop in `train-loop.md`, and hitting the poll ceiling
means `[SKIPPED]` with `checks still running` — the next tick re-evaluates. It
does **not** mean calling `gh:pr-resolve-ci-fail` on a green-so-far PR.

## `BLOCKED` — record what blocked it

`BLOCKED` is the platform saying a rule is unmet: a required check missing
(distinct from failing), a required review absent, a merge queue requirement, a
policy violation. This skill does not fight rules — it records which one and
moves on:

```bash
GH_HOST="$TARGET_HOST" gh pr checks "$N" --repo "$TARGET_REPO" --required
```

Use that output (plus `reviewDecision`) as the `[SKIPPED]` reason. **Never**
escalate a `BLOCKED` PR to `gh:pr-merge-emergency` (NF-2): a bypass is a
deliberate human act with an audit trail, not a train's fallback.

## `UNKNOWN` — GitHub is still computing

`UNKNOWN` is transient: GitHub computes mergeability asynchronously and answers
`UNKNOWN` until it finishes. It is not an error and must not be treated as one.
Poll (see `train-loop.md`), then re-enter this table with the resolved status.
Three polls without resolution is `[SKIPPED]`, re-evaluated next tick.

## After every remediation: re-query, do not assume

An atom skill returning success means *it* succeeded, not that the PR is now
mergeable — another train step, or a colleague, may have moved the base in
between. Always re-run the `gh pr view` above (refreshing `$STATE`) and re-enter the
table before calling `gh:pr-merge`. That re-entry is what the 3-attempt cap (F-5) counts.
