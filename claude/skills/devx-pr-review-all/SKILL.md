---
name: devx:pr-review-all
description: >-
  Fan out every available reviewer on one PR in parallel, then run a reply pass.
  Use for /devx:pr-review-all, /devx-pr-review-all, "PR 다중 리뷰어 병렬로",
  "agy codex simplify 한번에 돌려", "PR 99 전체 리뷰". Not a single-reviewer run
  (gh:pr-review); never approves.
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "parallel review fan-out orchestration; soft-fail gate + inline/deferred reply"
    claude: prefer
    non_claude: advisory-only
---

# devx:pr-review-all — Multi-reviewer PR gate + reply

## Role

Orchestrate a single PR through all available reviewers at once — agy, codex, opencode, hermes, plus a `/simplify`
auto-fix pass — record the aggregate verdict as a merge-gate label, commit any auto-fix changes, then reply to
review comments inline or deferred. No
approve/request-changes decision and no manual per-comment authoring. Every reviewer lane is soft-fail.
This skill is the **only** writer of `review-blocked` / `review-passed`
(`references/review-verdict-label.md`); `gh:pr-merge-train` is their only reader.
Argument/flag table (`<PR#> [remote] [--defer-reply M] [--no-reply]`): `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
it verbatim, then stop. No API calls.

## Step 1: Parse Args

Source and delegate to `devx_pr_review_all_parse`:
`source "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh"` then
`devx_pr_review_all_parse "$@"`. On help, follow Help; on exit 2, print stderr
and stop. Capture `pr`, `remote`, `reply_mode`, `reply_delay`, and `START_TS`.

## Step 2: Pre-flight

- Resolve `TARGET_REPO` for `<remote>` and pass `-R <TARGET_REPO>` on every
  `gh pr`/`gh repo` call.
- PR state must be `OPEN` and not draft (`gh pr view <pr> -R <TARGET_REPO>`)
  → else exit 1 `PR #<pr> is <state>; aborting`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.
- **auto-fix branch context**: if not on the PR head branch, run
  `gh pr checkout <pr> -R <TARGET_REPO>`; `/simplify` acts on the working tree.

## Step 3: Review + auto-fix gate (dispatch all lanes in ONE turn)

The five lanes dispatch together in a single turn. agy/codex/opencode/hermes
are comment-only; `/simplify` may mutate and commit. Each lane is soft-fail.

- **agy** — if `command -v agy`, an Agent runs
  `Skill(gh:pr-review, "--ai agy <pr> <remote>")`; absent or non-zero exit → SKIP/WARN.
- **codex** — if `command -v codex`, an Agent runs
  `Skill(gh:pr-review, "--ai codex <pr> <remote>")`; absent or non-zero exit → SKIP/WARN.
- **opencode** — if `command -v opencode` and `_dotfiles_setup_mode` is
  `internal`, an Agent runs
  `Skill(gh:pr-review, "--ai opencode <pr> <remote>")`; absent, non-internal,
  or non-zero exit → SKIP/WARN.
- **hermes** — if `command -v hermes` and `_dotfiles_setup_mode` is
  `internal`, an Agent runs
  `Skill(gh:pr-review, "--ai hermes <pr> <remote>")`; absent, non-internal,
  or non-zero exit → SKIP/WARN.
- **auto-fix** — an Agent runs built-in `/simplify`; if `git status --porcelain`
  is non-empty, commit with `git commit -am "refactor(<scope>): simplify per /simplify"`.

Never add `/code-review --fix`; it is user-invocation-only (`references/constraints.md`).

## Step 3.5: Aggregate review verdicts and apply the merge-gate label

Runs **after every Step 3 lane has returned and before Step 4's push.** That
order is load-bearing, not cosmetic: the lanes tagged their comments with the
PR's current **remote** head, and `/simplify` has at most committed *locally*
by now. Reading the head sha after Step 4 pushes would read the new sha, every
lane would miss, and the gate would silently label nothing forever.

Full runnable block, exit codes, and rationale: `references/review-verdict-label.md`.
In short — bind `TARGET_HOST` from the same `<remote>` URL as `TARGET_REPO`
(the block in `references/reply-pending-label.sh.md` step 0), then:

1. `head_sha` — one `gh pr view "$pr" -R "$TARGET_REPO" --json headRefOid`.
2. `BODIES` — one `gh api --paginate "repos/$TARGET_REPO/issues/$pr/comments"`.
3. For **each lane that actually ran** in Step 3 (a `[SKIP]`/`[WARN]` lane
   contributes nothing, and `/simplify` never contributes), pipe `BODIES`
   through `devx_pr_review_all_lane_block "$ai" "$head_sha"` →
   `devx_pr_review_all_verdict`, and pipe that stream straight into
   `devx_pr_review_all_apply_label "$pr" "$TARGET_REPO" "$TARGET_HOST"`.
   Never stage the verdicts in a variable and re-expand it — zsh does not
   word-split, and a two-lane PR would silently report one.

The whole step is **soft-fail**: a labelling failure never blocks Steps 4-6,
and an unlabelled PR reads downstream as "not verified", which
`gh:pr-merge-train` `[SKIPPED]`s rather than merges.

## Step 4: Push the auto-fix commit (only if something changed)

Await all lanes, then:

- `/simplify` committed → `git push`.
- The tree was unchanged → skip.

**If the push happened, drop `review-passed` immediately** (soft-fail, same
`_gh_pr_drop_label` helper Step 3.5's SSOT already documents). Step 3.5 labels
against the pre-push head on purpose — but that means a push here moves the
head *the label just certified* out from under it, without a reviewer having
seen the auto-fix diff (PR #1598 review, agy CONCERNS + codex BLOCKER). Never
drop `review-blocked` here — this step holds no evidence any blocker was
addressed, and the auto-fix commit is unreviewed by construction:

```bash
if [ "$PUSHED" = "1" ]; then
    . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"
    if _vl_err=$(_gh_pr_drop_label "$pr" review-passed "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
        echo "[OK] \`review-passed\` 무효화됨 — /simplify 커밋이 push 되어 이전 판정은 만료"
    else
        echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 auto-fix 커밋에 판정이 남아 있다: ${_vl_err}"
    fi
fi
```

## Step 5: pr-reply (per reply_mode)

- `inline` (default) → run `Skill(gh:pr-reply, "<pr> <remote>")` immediately.
- `defer` → **first** add the `reply-pending` label per
  `references/reply-pending-label.sh.md` (idempotent `gh label create`, then
  `_gh_pr_edit_safe_label`; soft-fail — a label failure never blocks the
  schedule), **then**
  `Skill(devx:schedule, "--time <reply_delay> \"/gh-pr-reply <pr> <remote>\"")`.
  The label is what makes `gh:pr-merge-train` hard-skip this PR until the
  reply pass finishes (#1524); `gh:pr-reply` Step 6 removes it.
- `none` → skip.

Only `defer` labels: `inline` and `none` defer nothing, so there is no pending
state to mark.

## Step 6: Report

Print exactly one `[OK]`/`[SKIP]`/`[WARN]` line, e.g.
`[OK] PR #<pr> reviewed (agy:OK codex:SKIP opencode:OK hermes:SKIP simplify:committed) — reply: inline — verdict: review-passed`.
The trailing clause is Step 3.5's outcome: `review-passed`, `review-blocked`,
or `unlabelled`.

## Constraints (full rationale: `references/constraints.md`)

- Reviewer lanes are soft-fail; `/simplify` commits its own changes before push.
- Never add `/code-review`; never run bare `git commit`.
- Inline reply is deterministic; `--defer-reply` is minutes-only and not a guarantee.
- No approve / request-changes here — that is `gh:pr-approve`.

## Related Skills

`gh:pr-review` (one reviewer at a time — this skill fans out over it) · `gh:pr-reply` / `devx:schedule` (the reply
pass) · `gh:pr-approve` (the approve/request-changes decision) · `gh:pr-merge-train` (consumes Step 3.5's
verdict label as a hard merge gate) · `gh:label-bootstrap` (provisions the two labels). Reused by
`gh:issue-flow` (Step 2.4) as its post-PR quality gate.
