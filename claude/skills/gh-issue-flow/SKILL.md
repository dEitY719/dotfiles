---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr
  → devx:schedule (pr-reply, 5 min) → gh:pr-resolve-conflict for a single
  issue number. Use when the user runs /gh:issue-flow, /gh-issue-flow, or
  asks "issue #16 처음부터 PR까지 자동으로", "이슈 구현하고 커밋하고 PR까지
  한방에", "full flow on #42". Uses direct implementation mode only — for
  plan/brainstorming modes, use the atomic gh:issue-implement skill
  manually. Stops on first step failure with a resume-instructions report.
  Precondition: already on a feature branch in a dedicated worktree.
  Accepts `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "composite orchestration (implement→commit→PR→reply→rebase); chain dispatcher with stop-on-error"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-flow — Issue → PR composition

## CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop after Step 2.x.** Three layered guards
prevent it — (1) `--no-next-hint` on Step 2.1, (2) zero conversational text
between the five `Skill()` calls in Step 2, (3) the harness Stop hook
(`claude/hooks/gh_issue_flow_stop_guard.py`). **Do not remove any of them.**
Full failure history (#333, #383), guard rationale, and the
backstop-not-a-license rule are in `references/critical-contract.md` — read
it before editing Step 2.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls. The help output explicitly
names the 5 chained skills: gh:issue-implement, gh:commit, gh:pr,
devx:schedule, gh:pr-resolve-conflict.

## Step 1: Parse Args

| Argument | Description | Default |
|----------|-------------|---------|
| `<issue-number>` | 처리할 GitHub Issue 번호 (양의 정수) | — |
| `[remote]` | git remote 이름 | `origin` |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

No `mode` arg — implementation is always `direct`. Record
`START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 2.6.

## Step 2: Chain the 5 Skills

Invoke in order; each runs only if the previous succeeded. **Zero
conversational text between the calls — no recap, headers, or progress
bullets** (see CRITICAL CONTRACT). After each call, immediately invoke the next.

1. **Step 2.1 — gh:issue-implement** — `--no-next-hint` is load-bearing.
   ```
   Skill(gh:issue-implement, "<N> direct <remote> --no-next-hint")
   ```
2. **Step 2.2 — gh:commit** (only if 2.1 succeeded) — auto-detects the issue
   number from the conversation.
   ```
   Skill(gh:commit)
   ```
3. **Step 2.3 — gh:pr** (only if 2.2 succeeded) — ensures `Closes #<N>`;
   extract `<PR_NUM>` from the PR URL in the output.
   ```
   Skill(gh:pr, "<N>")
   ```
4. **Step 2.4 — devx:schedule** (only if 2.3 succeeded) — schedules
   `/gh-pr-reply <PR_NUM>` 5 min after PR creation.
   ```
   Skill(devx:schedule, "--time 5 \"/gh-pr-reply <PR_NUM>\"")
   ```
5. **Step 2.5 — gh:pr-resolve-conflict** (only if 2.4 succeeded) —
   rebase-resolve; a fresh PR usually prints "이미 충돌 없음 — skip".
   ```
   Skill(gh:pr-resolve-conflict, "<PR_NUM>")
   ```
6. **Step 2.6 — Post AI Metrics to Issue** (only if 2.5 succeeded;
   soft-fail) — aggregate flow-level metrics comment on the linked Issue.
   Full procedure (per-step timing, human-time lookup, token estimate,
   `gh api` body template, `GH_DISABLE_AI_METRICS` short-circuit, soft-fail
   warning) is in `references/ai-metrics-step.md`.

## Step 3: Report

Output format (success template, soft-fail variant, failure template, and
the per-step resume-hint logic) is defined in `references/report-template.md`.
Always end with the `[OK]`/`[FAIL]`/`[SKIP]` structured report.

## Constraints

See `references/constraints.md` for the full list (direct mode only, never
retry/skip a step, no state mutation beyond sub-skills, the Step 2.6
soft-fail exception, the `--no-next-hint` and zero-prose early-stop guards,
and the do-not-stop-mid-flow rule).
