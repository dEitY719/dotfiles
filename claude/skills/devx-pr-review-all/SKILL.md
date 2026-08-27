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
auto-fix pass — commit any auto-fix changes, aggregate every lane's verdict into a `review-blocked` / `review-passed`
PR label (#1527), then reply to review comments inline or deferred. No approve/request-changes decision and no manual
per-comment authoring. Every lane is soft-fail. Args (`<PR#> [remote] [--defer-reply M] [--no-reply]`): `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
it verbatim, then stop. No API calls.

## Step 1: Parse Args

Source and delegate to `devx_pr_review_all_parse`:
`source "${SHELL_COMMON}/functions/devx_pr_review_all.sh"` then
`devx_pr_review_all_parse "$@"`. On help, follow Help; on exit 2, print stderr
and stop. Capture `pr`, `remote`, `reply_mode`, `reply_delay`, and `START_TS`.

## Step 2: Pre-flight

- Resolve `TARGET_REPO` **and `TARGET_HOST`** from `<remote>`'s URL, then
  **`export GH_HOST="$TARGET_HOST"`** and pass `-R <TARGET_REPO>` on every `gh`
  call (#1403, #1407). The export is load-bearing, not tidiness: Step 5's
  `_gh_pr_edit_safe_label` calls `gh` itself and contains no host handling of
  its own, so a per-call prefix never reaches it and the label add lands on gh
  CLI's default host (PR #1529 review, agy + codex).
- PR state must be `OPEN` and not draft (`gh pr view <pr> -R <TARGET_REPO>`)
  → else exit 1 `PR #<pr> is <state>; aborting`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.
- **auto-fix branch context**: if not on the PR head branch, run
  `gh pr checkout <pr> -R <TARGET_REPO>`; `/simplify` acts on the working tree.

## Step 3: Review + auto-fix gate (dispatch all lanes in ONE turn)

The five lanes dispatch together in a single turn. agy/codex/opencode/hermes
are comment-only; `/simplify` may mutate and commit. Each lane is soft-fail.

**Record which lanes RAN** — that is all Step 3 owes Step 5. The verdict itself
is *not* read from a lane's return value: `gh:pr-review` returns one `[OK] …`
line and a subagent returns a summary, neither of which carries it. Step 5 reads
it from the `<!-- ai-review:<ai> -->` block each lane posted to the PR instead
(`references/review-verdict-label.md`).

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

## Step 4: Push the auto-fix commit (only if something changed)

Await all lanes, then:

- `/simplify` committed → `git push`.
- The tree was unchanged → skip.

## Step 5: Aggregate verdicts into the merge-gate label

Fetch the PR's comments once, then per lane that RAN:
`devx_pr_review_all_lane_block <ai>` → `devx_pr_review_all_verdict` →
`devx_pr_review_all_aggregate` over those verdicts → apply via
`_gh_pr_edit_safe_label`, clearing the opposite label first. Exact block, label
table, fail-closed rules: `references/review-verdict-label.md`. Soft-fail throughout.

`review-blocked` if any lane blocked; `review-passed` only if ≥1 lane ran and none
blocked or came back `unknown`; **no label otherwise** — "not checked" is never
promoted to "passed", and `gh:pr-merge-train` skips an unlabelled PR (#1527).

## Step 6: pr-reply (per reply_mode)

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

## Step 7: Report

Print exactly one `[OK]`/`[SKIP]`/`[WARN]` line naming the verdict label (or `none`), e.g.
`[OK] PR #<pr> reviewed (agy:blocking codex:SKIP opencode:lgtm hermes:SKIP simplify:committed) — label: review-blocked — reply: inline`.

## Constraints (full rationale: `references/constraints.md`)

- Reviewer lanes are soft-fail; `/simplify` commits its own changes before push.
- Never add `/code-review`; never run bare `git commit`.
- Inline reply is deterministic; `--defer-reply` is minutes-only and not a guarantee.
- Verdict labelling is soft-fail and fail-closed — no verdict means no label (#1527).
- No approve / request-changes here — that is `gh:pr-approve`.

## Related Skills

`gh:pr-review` (one reviewer at a time — this skill fans out over it) · `gh:pr-reply` / `devx:schedule` (the reply
pass) · `gh:pr-approve` (the approve/request-changes decision) · `gh:pr-merge-train` (consumes the Step 5 verdict
label as a hard merge gate, #1527). Reused by `gh:issue-flow` (Step 2.4) as its post-PR quality gate.
