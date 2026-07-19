---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr →
  devx:pr-review-all (agy ∥ codex ∥ /code-review --fix → /simplify
  quality gate + deferred pr-reply, 8 min) → gh:pr-resolve-conflict →
  gh:pr-resolve-outdated
  (out-of-date base sync) for a single issue number. Use when the user runs
  /gh:issue-flow, /gh-issue-flow, or asks "issue #16 처음부터 PR까지 자동으로",
  "이슈 구현하고 커밋하고 PR까지 한방에", "full flow on #42". Uses direct
  implementation mode only — for plan/brainstorming modes, use the atomic
  gh:issue-implement skill manually. Stops on first step failure with a
  resume-instructions report. Precondition: already on a feature branch in a
  dedicated worktree. Accepts `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "composite orchestration (implement→commit→PR→gate→reply→rebase); chain dispatcher with stop-on-error"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-flow — Issue → PR composition

## CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop after Step 2.x.** Three layered guards
prevent it — (1) `--no-next-hint` on Step 2.1, (2) zero conversational text
between the six `Skill()` calls in Step 2, (3) the harness Stop hook
(`claude/hooks/gh_issue_flow_stop_guard.py`). **Do not remove any of them.**
The quality gate is no longer inline here — it lives inside the delegated
`devx:pr-review-all` (Step 2.4), so Step 2 is a clean sequence of six
`Skill()` calls with no inline Agent/Bash gate work between them. Only
conversational prose (recaps, headers, bullets) is forbidden between the
calls. Full failure history (#333, #383) and guard rationale:
`references/critical-contract.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls. The help output names the 6
chained skills (gh:issue-implement, gh:commit, gh:pr, devx:pr-review-all,
gh:pr-resolve-conflict, gh:pr-resolve-outdated); devx:pr-review-all runs the
post-PR quality gate (agy ∥ codex ∥ /simplify) and schedules the pr-reply.

## Step 1: Parse Args

| Argument | Description | Default |
|----------|-------------|---------|
| `<issue-number>` | 처리할 GitHub Issue 번호 (양의 정수) | — |
| `[remote]` | git remote 이름 | `origin` |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

No `mode` arg — implementation is always `direct`. Record
`START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 2.6.

## Step 2: Chain the Skills

Invoke in order; each runs only if the previous succeeded. **Zero
conversational text between the calls — no recap, headers, or progress
bullets** (see CRITICAL CONTRACT). The quality gate now lives inside the
delegated Step 2.4 (`devx:pr-review-all`), so Step 2 is a clean six-call
sequence. After each call, immediately proceed to the next.

1. **Step 2.1 — gh:issue-implement** — `--no-next-hint` is load-bearing.
   `Skill(gh:issue-implement, "<N> direct <remote> --no-next-hint")`
2. **Step 2.2 — gh:commit** (only if 2.1 succeeded) — auto-detects the issue
   number from the conversation. `Skill(gh:commit)`
3. **Step 2.3 — gh:pr** (only if 2.2 succeeded) — ensures `Closes #<N>`;
   extract `<PR_NUM>` from the PR URL. `Skill(gh:pr, "<N>")`
4. **Step 2.4 — devx:pr-review-all** (only if 2.3 succeeded; soft-fail) — one
   delegated call runs the post-PR quality gate (agy ∥ codex ∥ `/simplify`),
   commits + pushes any simplify changes synchronously, and schedules
   `/gh-pr-reply <PR_NUM>` 8 min later via `--defer-reply`. The synchronous
   simplify commit lands before the 2.5/2.5.1 rebase steps. Detail:
   `references/quality-gate-step.md`.
   `Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 8")`
5. **Step 2.5 — gh:pr-resolve-conflict** (only if 2.4 succeeded) —
   rebase-resolve; a fresh PR usually prints "이미 충돌 없음 — skip".
   `Skill(gh:pr-resolve-conflict, "<PR_NUM>")`
6. **Step 2.5.1 — gh:pr-resolve-outdated** (only if 2.5 succeeded) — clean
   rebase-sync when the base moved forward with no conflicts; no-op if already
   up to date. `Skill(gh:pr-resolve-outdated, "<PR_NUM>")`
7. **Step 2.6 — Post AI Metrics to Issue** (only if 2.5.1 succeeded;
   soft-fail) — aggregate flow-level metrics comment on the linked Issue.
   Full procedure: `references/ai-metrics-step.md`.

## Step 3: Report

Output format (success template, soft-fail variant, failure template, and
the per-step resume-hint logic) is defined in `references/report-template.md`.
Always end with the `[OK]`/`[FAIL]`/`[SKIP]` structured report.

## Constraints

See `references/constraints.md` for the full list (direct mode only, never
retry/skip a step, quality-gate + Step 2.6 soft-fail exceptions, the
simplify-commit-before-rebase rule, the `--no-next-hint` and zero-prose
early-stop guards, and the do-not-stop-mid-flow rule).
