# gh:pr-merge-train — State to action routing (D-1)

Deterministic. No judgement is exercised in this table — the two rows that need
judgement (`DIRTY`, `UNSTABLE`-with-a-failure) delegate it to an atom skill.

## Reading the state

Immediately before processing each PR (F-3):

```bash
GH_HOST="$TARGET_HOST" gh pr view "$N" --repo "$TARGET_REPO" \
  --json number,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,url
```

## The table

| `mergeStateStatus` | `mergeable` | Action |
|---|---|---|
| `CLEAN` | `MERGEABLE` | `Skill(gh:pr-merge, "<N>")` directly |
| `BEHIND` | `MERGEABLE` | `Skill(gh:pr-resolve-outdated, "<N>")` → re-query → merge |
| `DIRTY` | `CONFLICTING` | `Skill(gh:pr-resolve-conflict, "<N>")` → re-query → merge |
| `UNSTABLE` | `MERGEABLE` | inspect `statusCheckRollup` — see below |
| `BLOCKED` | — | record the reason, `[SKIPPED]` |
| `UNKNOWN` | `UNKNOWN` | poll, then re-evaluate; `[SKIPPED]` after 3 polls |
| `DRAFT` | — | `[SKIPPED]` (a draft is not a merge candidate) |

`isDraft == true` short-circuits the table: skip before reading anything else.

## `UNSTABLE` — split on the rollup, not on the status

`UNSTABLE` means "mergeable, but a check is not green". Two very different
situations share that word, and conflating them is how a train starts "fixing"
a test that had not finished running:

```bash
GH_HOST="$TARGET_HOST" gh pr view "$N" --repo "$TARGET_REPO" \
  --json statusCheckRollup \
  --jq '[.statusCheckRollup[]? | {name: (.name // .context), status, conclusion}]'
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
between. Always re-run the `gh pr view` above and re-enter the table before
calling `gh:pr-merge`. That re-entry is what the 3-attempt cap (F-5) counts.
