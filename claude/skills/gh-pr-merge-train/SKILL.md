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

머지는 **fire-and-forget** 이다 (#1707): `gh:pr-merge` 를 `--auto` 로 호출해
merge queue 에 넣고 기다리지 않으며, 실제 머지 후 처리는 다음 tick 의 Step 0
finalize sweep 이 맡는다. 이 저장소에서 merge queue 자체는 **쓸 수 없고**(조직
소유 저장소 전용), 그 조사 결과와 사람이 직접 실행해야 하는 활성화 절차는
`references/merge-queue-investigation.md` 에 있다 — 이 스킬은 그 명령을
실행하지 않는다.

N번의 직렬 CI 왕복을 실제로 없앤 것은 큐가 아니라 **`main` ruleset 의 strict
required-status-checks 해제**다 (#1707). 그래서 `BEHIND` + `MERGEABLE` PR 은
로컬 리베이스 없이 바로 머지되고, 그 대가로 "리베이스된 결과가 착지 전에는
CI 를 거치지 않는다" 는 위험을 받아들인다. 무엇을 얻고 무엇을 잃었는지, 그
위험을 받치는 안전망(Step 3.6 + `main` push CI)은
`references/strict-mode-relaxation.md` 에 있다. `DIRTY` 는 이 완화의 영향을
전혀 받지 않는다 — 실제 충돌은 언제나 `gh:pr-resolve-conflict` 가 먼저다.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output its
content verbatim, then stop. **No API calls.** That file tables the positionals
(`[owner/repo]`, `[remote]`) and names the atom skills the train calls.

## Step 1: Bind the GitHub target

Copy the binding block from `references/github-target.md` and run it **before
any `gh` call** — `TARGET_REPO` / `TARGET_HOST` / `GH_HOST` come from one and
the same remote URL (#1403/#1407). An explicit `owner/repo` positional pins
`TARGET_REPO` directly; the host still comes from the remote URL.

## Step 0: Finalize PRs the merge queue merged since the last tick

Runs **before** Step 2 builds this tick's queue, because these PRs are already
merged — they are not candidates, they are unfinished business (#1707).

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_merge_train.sh"
GH_HOST="$TARGET_HOST" gh pr list --repo "$TARGET_REPO" --author @me --state merged \
  --limit 30 --json number,title,state,labels \
  | jq -c '.[]?' \
  | while IFS= read -r _pr; do
        printf '%s' "$_pr" | _gh_pr_merge_train_needs_finalize || continue
        printf '%s\n' "$(printf '%s' "$_pr" | jq -r '.number')"
    done
```

Each number that comes out gets **one**
`Skill(gh:pr-merge, "<N> rebase <remote> --finalize")`, then a
`[FINALIZED] #<N> <title>` line in the Step 5 report.

`_gh_pr_merge_train_needs_finalize` is the **shared** predicate in
`shell-common/functions/gh_pr_merge_train.sh`, beside the label predicates
Step 3.5 uses — run it, do not paraphrase it. It answers "MERGED **and** still
carrying `review-passed`", and that combination is the signal precisely because
`gh:pr-merge` drops that label as the last step of a completed merge (#1636):
a merged PR that still has it is a PR whose completion steps never ran, which
is what an enqueued (`--auto`) merge leaves behind.

The finalize work itself is **not done here**. The train writes nothing to
GitHub of its own (`references/constraints.md`); `gh:pr-merge --finalize` owns
every one of those mutations already, and the sequence it runs is defined in
`../gh-pr-merge/references/finalize-merged-pr.sh.md`. `--state merged` with
`--limit 30` bounds the sweep: a PR older than that window and still labelled
is a human's problem, not a loop's.

## Step 2: Collect and order the queue

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_merge_train.sh"
# One file per PR, holding the head sha THIS train pushed (#1708). Same
# `--path-format=absolute` care `references/train-loop.md` → "Detached scratch
# worktree" already documents for `--git-common-dir` — see there for why.
STATE_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/pr-merge-train-pushed-sha"

RAW=$(GH_HOST="$TARGET_HOST" gh pr list --repo "$TARGET_REPO" --author @me --state open \
  --limit 50 --json number,updatedAt,isDraft,mergeable,mergeStateStatus,baseRefName,title,labels,headRefOid)
FILTERED=$(printf '%s' "$RAW" | _gh_pr_merge_train_filter_targets --now "$(date +%s)")
QUEUE=$(printf '%s' "$RAW" | _gh_pr_merge_train_readmit_own_pushes "$STATE_DIR" "$FILTERED")
```

`--author @me` is not optional (D-7) — never auto-merge a colleague's PR.
`_gh_pr_merge_train_filter_targets` is the **shared** filter (#1524): it drops
drafts, every PR carrying the `reply-pending` label, and every PR inside the
D-6 quiet period — the exact same function
`shell-common/tools/custom/pr_merge_train_cron.sh` runs, so the two can never
disagree. **Do not re-implement or paraphrase that filter here** — run it.

`_gh_pr_merge_train_readmit_own_pushes` is a **separate, additive second pass**
that runs AFTER it and **never changes what the shared filter does** (#1708) —
the dispatcher's own pre-check keeps calling the untouched filter alone. It
re-admits only a PR the filter dropped *solely* for the quiet period whose
current `headRefOid` is one this train recorded pushing in an earlier run's
Step 4 remediation (`references/train-loop.md`); `reply-pending` and `isDraft`
always win over it. `headRefOid` is in the `--json` list for this pass. Print
one line per re-admitted PR so a PR that looks "too fresh" is not mysterious:

```
[INFO] gh:pr-merge-train: PR #<N> re-admitted — this train pushed its current head (#1708 D-6 exemption).
```

Sort `QUEUE` — the union, not `FILTERED` — `CLEAN` → `BEHIND` → `UNSTABLE` → `DIRTY`, ties by
ascending PR number (D-2). Ordering, the label, and the quiet-period rationale:
`references/ordering.md`.

**`gh pr list` failure ends the run** with an empty report — never merge
without knowing state.

## Step 3: Read the approval policy per base branch

Read `required_approving_review_count` from **both** rulesets and classic
branch protection per `references/approval-gate.md`, **once per distinct
`baseRefName`**, cached per base — two calls per base, never per PR. Either
source requiring `>= 1` → gate on, unapproved PRs `[SKIPPED]`; both reporting
no policy → off (D-5). Classify by **HTTP status, not exit code**: a `403`/`404`
is "no policy", not a failed lookup, and only a genuinely undetermined answer
stays fail-closed (#1519). Even with the gate off, a non-empty non-`APPROVED`
`reviewDecision` is `[SKIPPED]` before `gh:pr-merge` is called — it would
refuse, and NF-2 forbids clearing that.

## Step 3.5: Apply the review verdict gate

Over the PRs Step 2 let through — **not** a new API call, the `labels` field
is already in hand — run the decision table in `references/review-verdict-gate.md`:
`review-blocked` (even alongside a stale `review-passed`) is
`[SKIPPED] review-blocked — reviewer verdict is blocking`; neither label is
`[SKIPPED] review not verified — no review-passed label`; `review-passed`
alone stays in the queue. Ask with
`_gh_pr_merge_train_has_review_blocked_label` /
`_gh_pr_merge_train_has_review_passed_label` (same file Step 2 sourced) — **do
not** re-derive the `jq` here, and **never** parse a review comment body: the
verdict is decided by `devx:pr-review-all`, which is the labels' only writer.

**Absence is "not verified", not "passed"** — that is the whole gate (#1527 /
#1564). Neither outcome spends an F-5 attempt and neither is ever `[FAILED]`.
There is deliberately no staleness window here, unlike `reply-pending`'s.

This pass is label-presence only, on purpose — it costs no API call. It
cannot yet tell a `review-passed` label issued for the current head apart
from a stale one; that sha-freshness check (#1601) happens once per PR, right
before it is actually acted on, at Step 4's F-3 re-query
(`references/routing-table.md`) — the same point that already re-derives
everything else Step 2/3.5 could not have seen coming.

## Step 3.6: Read the base's check policy and health — once per base

Run the block in `references/strict-mode-relaxation.md` → "New: the train
refuses to pile onto a red base", **once per distinct `baseRefName`**, cached
per base like Step 3's approval lookup. It costs one extra read-only REST call
per base (the rules body is the one Step 3 already fetches) and **none** per PR.

It answers two questions with the shared predicates in
`shell-common/functions/gh_pr_merge_train.sh` — run them, do not paraphrase:

- `_gh_pr_merge_train_behind_may_merge_directly` → `$BEHIND_DIRECT`. `yes` means
  strict checks are off on this base, so the D-1 table's `BEHIND` row merges
  directly instead of rebasing locally (`references/routing-table.md`).
  Anything unread or unclear is `no` — the pre-#1707 local remediation.
- `_gh_pr_merge_train_base_ci_red` → is the base's tip already failing a check
  **it requires**? If so, every PR on that base is `[SKIPPED] <base> is red`
  and the merge phase does not run for it. Never `[FAILED]`: the next tick
  proceeds the moment the base is green.

This is the safety net that replaces what strict mode used to guarantee. It
cannot prevent one bad merge — nothing can, once strict is off — but it stops
the train from stacking more onto a base already known to be broken. Scope,
limits, and the accepted risk: `references/strict-mode-relaxation.md`.

## Step 4: Run the train — one PR at a time

For each PR in queue order, run the loop in `references/train-loop.md`:
**re-query state immediately before processing** (F-3 — the previous merge
invalidated everything behind it), route through the D-1 table
(`references/routing-table.md`), then merge with
`Skill(gh:pr-merge, "<N> rebase <remote> --auto")` — fire-and-forget, so a
`[QUEUED]` answer ends that PR's turn rather than starting a wait (#1707).
Gate off with an empty `reviewDecision` first runs one
`Skill(gh:pr-approve, "<N> <remote> --self-record")` and reads the board back as
its verdict — no approval, no merge.
After a **successful** merge, close that PR's implementation tab when its herdr
agent is `idle` — the block in `references/train-loop.md` → "Closing the merged
PR's implementation tab". A merged PR whose tab stays open keeps counting toward
issue-watcher's `_IW_MAX_PER_REPO` budget and starves the pipeline (#1565).
The `DIRTY` row — and `BEHIND` only when Step 3.6 left `$BEHIND_DIRECT` at `no`
— rebases inside a **detached scratch worktree** the train creates and
unconditionally removes per attempt (#1493). With `$BEHIND_DIRECT = yes`,
`BEHIND` merges directly and builds no worktree at all (#1707). Attempts are
capped at 3 per PR (F-5); a failure skips that PR and the train continues
(F-6). Never process two PRs concurrently.

## Step 5: Report

Emit the structured `[FINALIZED]` / `[MERGED]` / `[QUEUED]` / `[SKIPPED]` /
`[FAILED]` report — one line per PR with a reason — per
`references/report-format.md` (F-9). Always as plain assistant text, never via
a `Bash` heredoc or `Write`.

## Constraints

- **Never call `gh:pr-merge-emergency`** (NF-2). Admin bypass is not this
  skill's path; an unmergeable PR is `[SKIPPED]` with a reason.
- **Never abort the whole train** for one PR's failure (F-6).
- **No merge strategy choice** — `rebase` is the only value the train ever
  passes, and it is `gh:pr-merge`'s own default, which is what
  `required_linear_history` allows (D-4). It is spelled out only because
  `--auto` is a flag that cannot sit in a positional slot (#1707).
- **No review judgement of its own** — `gh:issue-flow` already ran
  `devx:pr-review-all`, and the gate-off path delegates to `gh:pr-approve`
  rather than deciding anything here. Step 3.5 reads that fan-out's verdict
  **label** and nothing else; parsing a review comment body here is forbidden
  (`references/review-verdict-gate.md` → "What this gate is not").
- **No ai-metrics comment.** Every atom the train calls posts its own; a
  train-level one would only duplicate them on the same PR.
- Full list: `references/constraints.md`.

## Related Skills

Atoms this train calls: `gh:pr-resolve-outdated` · `gh:pr-resolve-conflict`
· `gh:pr-resolve-ci-fail` · `gh:pr-approve` (`--self-record`, gate-off path
only) · `gh:pr-merge`. Deliberately **not** called:
`gh:pr-merge-emergency` (NF-2). Upstream producer of the PRs this train drains:
`gh:issue-flow`; of the Step 3.5 verdict labels it gates on: `devx:pr-review-all`
(sole writer) and `gh:label-bootstrap` (provisioning). Unattended trigger:
`shell-common/tools/custom/pr_merge_train_cron.sh` (`references/cron-dispatcher.md`).
