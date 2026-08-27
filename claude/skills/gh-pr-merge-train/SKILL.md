---
name: gh:pr-merge-train
description: >-
  Clean up and merge your own open PRs one at a time — each routed to
  gh:pr-resolve-outdated / -conflict / -ci-fail, then gh:pr-merge. Use for
  /gh:pr-merge-train, /gh-pr-merge-train, "열린 PR 순차로 정리하고 머지해",
  "머지 트레인 돌려". A single PR is gh:pr-merge, not this.
allowed-tools: Bash, Read, Grep, Skill
metadata:
  model_recommendation:
    tier: sonnet
    reason: "serial multi-PR orchestration; routing is deterministic but state must be re-derived per PR and two rows delegate real reasoning (conflict, CI)"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-merge-train — Sequential PR cleanup + merge

## Role

한 저장소의 열린 **본인 PR** 을 D-2 순서로 정렬해 **한 번에 1건씩** 정리·머지한다.
상태 판정과 스킬 라우팅은 결정론적이므로 이 스킬이 루프를 돌고, LLM 판단은
**충돌 해결과 CI 수정 두 지점에서만** 필요하다 — 그 둘은 원자 스킬에 위임한다.
한 PR 이 막혀도 그 PR 만 건너뛰고 train 은 계속한다.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output its
content verbatim, then stop. **No API calls.** That file tables the positionals
(`[owner/repo]`, `[remote]`) and names the five atom skills the train calls.

## Step 1: Bind the GitHub target

Copy the binding block from `references/github-target.md` and run it **before
any `gh` call** — `TARGET_REPO` / `TARGET_HOST` / `GH_HOST` come from one and
the same remote URL (#1403/#1407). An explicit `owner/repo` positional pins
`TARGET_REPO` directly; the host still comes from the remote URL.

## Step 2: Collect and order the queue

```bash
GH_HOST="$TARGET_HOST" gh pr list --repo "$TARGET_REPO" --author @me --state open \
  --limit 50 --json number,updatedAt,isDraft,mergeable,mergeStateStatus,baseRefName,title
```

`--author @me` is not optional (D-7) — never auto-merge a colleague's PR. Drop
every PR updated within the last **11 minutes** (D-6) and every draft. Sort
`CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, ties by ascending PR number (D-2).
Ordering and quiet-period rationale: `references/ordering.md`.

**`gh pr list` failure ends the run** with an empty report — never merge
without knowing state.

## Step 3: Read the approval policy per base branch

Read `required_approving_review_count` from **both** rulesets and classic
branch protection per `references/approval-gate.md`, **once per distinct
`baseRefName`**, cached per base — two calls per base, never per PR. Either
source requiring `>= 1` → gate on, unapproved PRs `[SKIPPED]`; both reporting
no policy → off (D-5). Classify by **HTTP status, not exit code**: `403`/`404`
mean no policy can apply, 5xx / 401 / network mean undetermined and stay
fail-closed — collapsing the two is what made unattended merges impossible on
free-plan private repos (#1519). Even with the gate off, a non-empty
non-`APPROVED` `reviewDecision` is `[SKIPPED]` before `gh:pr-merge` is called —
it would refuse, and NF-2 forbids clearing that.

## Step 4: Run the train — one PR at a time

For each PR in queue order, run the loop in `references/train-loop.md`:
**re-query state immediately before processing** (F-3 — the previous merge
invalidated everything behind it), route through the D-1 table
(`references/routing-table.md`), then merge with `Skill(gh:pr-merge, "<N>")`.
Gate off with an empty `reviewDecision` first runs one
`Skill(gh:pr-approve, "<N> <remote> --self-record")` and reads the board back as
its verdict — no approval, no merge, and no re-run for an already-reviewed head.
The `BEHIND` / `DIRTY` rows rebase inside a **detached scratch worktree** the
train creates and unconditionally removes per attempt (#1493). Attempts are
capped at 3 per PR (F-5); a failure skips that PR and the train continues
(F-6). Never process two PRs concurrently.

## Step 5: Report

Emit the structured `[MERGED]` / `[SKIPPED]` / `[FAILED]` report — one line per
PR with a reason — per `references/report-format.md` (F-9). Always as plain
assistant text, never via a `Bash` heredoc or `Write`.

## Constraints

- **Never call `gh:pr-merge-emergency`** (NF-2). Admin bypass is not this
  skill's path; an unmergeable PR is `[SKIPPED]` with a reason.
- **Never abort the whole train** for one PR's failure (F-6).
- **No merge strategy argument** — `gh:pr-merge`'s default rebase is what
  `required_linear_history` allows (D-4).
- **No review judgement of its own** — `gh:issue-flow` already ran
  `devx:pr-review-all`, and the gate-off path delegates to `gh:pr-approve`
  rather than deciding anything here.
- **No ai-metrics comment.** Every atom the train calls posts its own; a
  train-level one would only duplicate them on the same PR.
- Full list: `references/constraints.md`.

## Related Skills

Atoms this train calls: `gh:pr-resolve-outdated` · `gh:pr-resolve-conflict`
· `gh:pr-resolve-ci-fail` · `gh:pr-approve` (`--self-record`, gate-off path
only) · `gh:pr-merge`. Deliberately **not** called:
`gh:pr-merge-emergency` (NF-2). Upstream producer of the PRs this train drains:
`gh:issue-flow`. Unattended trigger: `shell-common/tools/custom/pr_merge_train_cron.sh`
(`references/cron-dispatcher.md`).
