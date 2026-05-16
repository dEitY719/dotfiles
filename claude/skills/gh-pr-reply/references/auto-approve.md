# gh:pr-reply Step 8 — Solo-Repo Auto-Approve (allowlist opt-in)

SSOT for the Step 8 logic referenced from `SKILL.md`. The actual
gating function lives in `tests/bats/skills/_fixtures/gh_pr_reply_auto_approve.sh`
(verbatim mirror) and is exercised by
`tests/bats/skills/gh_pr_reply_auto_approve.bats`.

## Why this exists

After `/gh-pr-reply` finishes posting answers to every review comment,
the PR card stays in `In review` until a human intervenes:

- **Solo repos (e.g. `dEitY719/dotfiles`)** — no teammate ever clicks
  Approve, so "review round closed" never registers on the board. The
  built-in `Pull request merged` workflow only fires at merge time, so
  a PR that has been fully addressed sits in `In review` indistinguishable
  from one waiting for the next round.
- **Collaborative repos (e.g. AgentToolbox)** — `Approved` means
  `reviewDecision == APPROVED` and nothing else (issue #231). That
  semantic is sacrosanct.

This skill resolves both shapes by leaving the helper-level fail-closed
guard (#393) in place and adding **opt-in skill-level bypass** keyed
on a repo allowlist. Solo repos opt in; collaborative repos never even
load the env var.

## Relationship to prior decisions

| Prior decision | Relationship |
|---|---|
| #275 — Step 7 auto-Approved move dropped | This skill is **not** a partial revert. The unconditional move stays gone. |
| #231 — `Approved` column = `reviewDecision == APPROVED` (collab repos) | Preserved. Solo bypass is gated by repo allowlist + 4 guards, never auto-fires in collab repos. |
| #393 — helper `_gh_project_status_sync` fail-closed gate on `kind=pr + target=Approved` | Preserved. Step 8 sets `_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1` for one call only — main shell never sees it. |
| #397 — `gh:pr-merge` board-gate | Independent. This skill writes the board state that `gh:pr-merge` later reads. |

## Algorithm (4 guards, all-must-pass)

Every branch binds `STEP8_OUTCOME` before returning. The Step 7
report consumes that variable to render a `Step 8:` row — leaving it
unset means the gate was skipped without evaluation, which the Step 7
report renderer treats as an incomplete (regression) report (#662).

```sh
# Inputs (already resolved by SKILL.md Steps 1-7):
#   PR_NUMBER, TARGET_REPO, COMMENT_COUNT,
#   PR_STATE, PR_IS_DRAFT, PR_REVIEW_DECISION
# Output:
#   STEP8_OUTCOME — exported for the Step 7 report renderer.

# G2: Step 2.5 early-exit safety net (defensive — SKILL.md normally
#     stops at Step 2.5 before reaching Step 8; this catches a stray
#     refactor that forgets to short-circuit).
if [ "${COMMENT_COUNT:-0}" -lt 1 ]; then
    STEP8_OUTCOME="SKIP:comment_count=0"
    return 0
fi

# G1a: env var must be set + non-empty.
_allow="${GH_PR_REPLY_AUTO_APPROVE_REPOS-}"
if [ -z "$_allow" ]; then
    STEP8_OUTCOME="SKIP:allowlist_miss"
    return 0
fi

# G1b: current repo must appear in the CSV (case-exact, no whitespace
#      padding around commas — Status names with internal spaces ride
#      through unchanged via the existing helper convention).
case ",${_allow}," in
    *",${TARGET_REPO},"*) ;;
    *)
        printf '[gh-pr-reply] auto-approve: %s not in allowlist (GH_PR_REPLY_AUTO_APPROVE_REPOS=%s) — skip.\n' \
            "$TARGET_REPO" "$_allow" >&2
        STEP8_OUTCOME="SKIP:allowlist_miss"
        return 0
        ;;
esac

# G3: PR must be OPEN and not a draft.
if [ "$PR_STATE" != "OPEN" ]; then
    printf '[gh-pr-reply] auto-approve: PR #%s state=%s — skip (need OPEN).\n' \
        "$PR_NUMBER" "$PR_STATE" >&2
    STEP8_OUTCOME="SKIP:state=$PR_STATE"
    return 0
fi
if [ "$PR_IS_DRAFT" = "true" ]; then
    printf '[gh-pr-reply] auto-approve: PR #%s is a draft — skip.\n' "$PR_NUMBER" >&2
    STEP8_OUTCOME="SKIP:draft"
    return 0
fi

# G4: reviewDecision must be empty/null or APPROVED. Anything else
#     means a reviewer is in mid-conversation; do not auto-close.
case "${PR_REVIEW_DECISION-}" in
    ""|null|APPROVED) ;;
    *)
        printf '[gh-pr-reply] auto-approve: PR #%s reviewDecision=%s — skip (need null|APPROVED).\n' \
            "$PR_NUMBER" "$PR_REVIEW_DECISION" >&2
        STEP8_OUTCOME="SKIP:reviewDecision=$PR_REVIEW_DECISION"
        return 0
        ;;
esac

# All guards pass. Audit-trace + scoped bypass call.
printf '[gh-pr-reply] auto-approve: solo-repo allowlist match → bypassing #393 fail-closed guard for PR #%s\n' \
    "$PR_NUMBER" >&2

# `|| _rc=$?` keeps the helper call errexit-safe so STEP8_OUTCOME
# is reliably bound to WARN:rc=<N> on non-zero helper return. A bare
# `_gh_project_status_sync …; _rc=$?` would let `set -e` abort the
# gate before the binding, regressing the issue #662 contract.
_rc=0
_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
    _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review" \
    || _rc=$?
if [ "$_rc" -ne 0 ]; then
    printf '[gh-pr-reply] auto-approve: helper rc=%s — continuing (soft-fail).\n' "$_rc" >&2
    STEP8_OUTCOME="WARN:rc=$_rc"
else
    STEP8_OUTCOME="OK:fired"
fi
return 0
```

### Outcome matrix

`STEP8_OUTCOME` is bound on every branch — the Step 7 report row
template (`references/final-summary.md`) maps the value to the
user-visible line:

| 4-guard result | `STEP8_OUTCOME` | Report row |
|---|---|---|
| All PASS + helper rc=0 | `OK:fired` | `[OK]   Step 8: auto-approve fired (helper rc=0)` |
| G1 SKIP (allowlist miss or env unset) | `SKIP:allowlist_miss` | `[SKIP] Step 8: allowlist miss` |
| G2 SKIP (comment_count=0, defensive) | `SKIP:comment_count=0` | `[SKIP] Step 8: comment_count=0` |
| G3 SKIP (state ≠ OPEN) | `SKIP:state=<X>` | `[SKIP] Step 8: state=<X>` |
| G3 SKIP (draft) | `SKIP:draft` | `[SKIP] Step 8: draft` |
| G4 SKIP (reviewDecision) | `SKIP:reviewDecision=<X>` | `[SKIP] Step 8: reviewDecision=<X>` |
| All PASS + helper rc ≠ 0 | `WARN:rc=<N>` | `[WARN] Step 8: helper rc=<N> — continuing` |

`STEP8_OUTCOME` unset after the gate function returns means the gate
never ran. The Step 7 renderer treats that as a regression signal
(see `references/final-summary.md` contract section).

### Why prefix form, not `env`

`_gh_project_status_sync` is a shell function. `env VAR=val funcname …`
would `exec env` and try to find a binary named `_gh_project_status_sync`
on `$PATH` — that fails. The POSIX prefix form
`VAR=val funcname …` keeps the binding scoped to that single function
invocation, satisfying the issue's "main shell 환경 오염 없음" intent.

### Why `--only-from "In review"`

Defense-in-depth. Even if a stray operator overrides the allowlist on a
collab repo, the helper's `--only-from` filter refuses to drag a card
in from `Backlog`/`In progress`/`Done`. Step 8 only ever promotes a
card that has *already* moved to `In review` through the normal flow.

## Audit-trace format

When G1–G4 all pass, this exact line lands on stderr (operator visibility):

```
[gh-pr-reply] auto-approve: solo-repo allowlist match → bypassing #393 fail-closed guard for PR #N
```

The wording deliberately names the bypass and the originating guard
so a future grep across logs surfaces every solo-repo override without
a special label.

## Defense-in-depth (4 simultaneous gates)

For Step 8 to fire on a collab repo by accident, **all four** of the
following must be wrong simultaneously:

1. `GH_PR_REPLY_AUTO_APPROVE_REPOS` must be exported (operator action).
2. The collab repo's `nameWithOwner` must literally appear in the CSV.
3. The card must already be at `In review` (collab Approved column
   semantic still holds — `--only-from "In review"`).
4. The PR's `reviewDecision` must already equal `APPROVED` or be `null`
   (collab repos start at `REVIEW_REQUIRED`, so this gate alone usually
   blocks).

In practice (4) alone protects collab repos: their PRs are configured
to require approval, so `reviewDecision` is never `null` and almost
never reaches `APPROVED` while the card is still at `In review`.

## Soft-fail policy

Helper `_gh_project_status_sync` returns:

- `0` — happy path or silent no-op (no projectV2, transient flake).
- `2` — fail-closed guard rejection. Should never happen here because
  Step 8 already set the bypass, but if a future helper guard adds a
  second condition, this branch fires.

Either non-zero return prints one stderr `helper rc=N — continuing`
warn and the main flow proceeds to the Step 7 final report. The
report itself is unchanged; auto-approve is bookkeeping, not part of
the user-visible answer summary.

## Test matrix

`tests/bats/skills/gh_pr_reply_auto_approve.bats` covers exactly the
issue #410 acceptance criteria, plus the issue #662 `STEP8_OUTCOME`
binding contract:

| # | Setup | Expected outcome | `STEP8_OUTCOME` |
|---|-------|------------------|-----------------|
| 1 | allowlist=`dEitY719/dotfiles`, repo=same, OPEN, not draft, reviewDecision=`APPROVED`, comments=3 | helper called with bypass=1, audit-trace line on stderr, rc=0 | `OK:fired` |
| 2 | allowlist=`dEitY719/dotfiles`, repo=`AgentToolbox/foo` | helper NOT called, "not in allowlist" info, rc=0 | `SKIP:allowlist_miss` |
| 3 | env unset | helper NOT called, no output, rc=0 | `SKIP:allowlist_miss` |
| 4 | allowlist match, `isDraft=true` | helper NOT called, "is a draft" info, rc=0 | `SKIP:draft` |
| 5 | allowlist match, `reviewDecision=CHANGES_REQUESTED` | helper NOT called, "reviewDecision=…" info, rc=0 | `SKIP:reviewDecision=CHANGES_REQUESTED` |
| 6 | comments=0 (Step 2.5 early-exit guard) | helper NOT called, no output, rc=0 | `SKIP:comment_count=0` |
| 7 | helper stub returns 2 | audit-trace + "helper rc=2" warn, rc=0 (soft-fail) | `WARN:rc=2` |
| 8 | issue #662 regression — allowlist HIT + 4 guards PASS but `STEP8_OUTCOME` unset after call | FAIL (renderer would drop the Step 8 row) | non-empty (asserts contract holds) |

## What this is NOT

- **Not a global Approved auto-mover.** Even with the env var set, only
  PRs from listed repos qualify; even within those repos, a single
  failing guard skips the move.
- **Not a substitute for human review on collab repos.** Collab repos
  rely on actual `reviewDecision == APPROVED` from a teammate; this
  skill does not synthesize that signal.
- **Not stateful.** The bypass scope is one helper call. No env mutation
  outlives the function return.
