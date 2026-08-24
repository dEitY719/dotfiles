---
name: gh:issue-relay-flow
description: >-
  Take an issue filed on a push-blocked destination remote to a relayed PR:
  branch → delegated implementation → verification → gh:relay-merge. Use for
  /gh:issue-relay-flow, /gh-issue-relay-flow, "이슈 번호로 브랜치 따고 relay까지",
  "사내PC에서 구현해서 upstream으로 릴레이해줘".
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "assembly skill — orchestrates branch-setup + Worker delegation + Advisor verification + a gh:relay-merge call, the same composition shape as gh-issue-flow (tier: sonnet)"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-relay-flow — Issue → Branch → Implement → Relay

## Role

목적지 remote 가 push 로 막혀 있을 때, **이미 그 remote 에 등록된 이슈 1건**을 릴레이 PR 까지 한 번에 끌고 간다:
목적지 remote 해석 + 기본 브랜치에서 분기 → 구현 위임(Advisor/Worker) → Advisor 가 diff 를 읽고 대상 레포의
lint/test 를 직접 실행 → `gh:relay-merge --commits` 가 패치를 올리고 apply-guide 를 게시. **이슈 등록 자체는 범위
밖** — 목적지 remote 에 이슈가 없으면 먼저 `gh:issue-create <remote>` 로 만든다. 마지막 단계는
`Skill(gh:relay-merge, ...)` 호출 **그대로**이며, 패치 생성 · gist 업로드 · apply-guide 게시를 다시 구현하지 않는다.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args

| Argument | Description | Default |
|----------|-------------|---------|
| `<issue-number>` | Issue already filed on the destination remote (positive integer) | — |
| `--remote <name>` | Destination remote — same remote `gh:relay-merge` will target | `upstream` |
| `--base <branch>` | Override the auto-detected destination default branch | auto-detect |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

Record `BASE_TS=$(date +%s)` for later elapsed-time reporting in Step 6.

**Stop-on-error policy**: Steps 2–5 run in order, each only if the previous
succeeded — a failure stops the chain immediately and reports per that
step's own guidance (branch-reuse question, Open-Questions gate,
re-delegate-on-failure, `gh:relay-merge`'s error surfaced unmodified);
never skip ahead.

## Step 2: Resolve Destination + Branch

Follow `references/branch-setup.md`. Resolves `--remote` (hard error on a missing remote — never fall back to
`origin`), detects the destination's default branch (or honors `--base`), fetches it, computes the branch name
`issue-<N>-<title-slug>`, and either creates a fresh branch or handles the "branch already exists" reuse/reset
decision (never auto-resets a branch that has unique commits without asking).

## Step 3: Delegate Implementation (Advisor/Worker)

Follow `references/worker-brief-checklist.md`. Fetch the issue body +
comments, resolve any unresolved Open Questions with the user **before**
delegating, assemble a self-contained brief, and delegate to an opus
subagent via the `Agent` tool. Record `BASE_SHA=$(git rev-parse HEAD)`
right before delegating — this is the relay range's lower bound.

## Step 4: Advisor Verification

Follow `references/verification.md`. Do not trust the Worker's completion
report — read `git diff <BASE_SHA>..HEAD` directly, discover and run the
target repo's standard lint/test commands, and only proceed once they pass.
On failure, re-delegate with a sharper brief per that file's guidance.

## Step 5: Relay Delegation

Record `HEAD_SHA=$(git rev-parse HEAD)`, then call `gh:relay-merge` verbatim
— no inline patch/gist/apply-guide logic here. Pass Step 4's pre-existing
unrelated failures through `--known-failures` (comma-separated
`<path>[::<test-or-check>]` entries); omit the flag when Step 4 found none:

`Skill(gh:relay-merge, "--commits <BASE_SHA>..<HEAD_SHA> --target-issue <N> --remote <remote> [--known-failures <entries>]")`

## Step 6: Report

Relay `gh:relay-merge`'s Step 8 output as-is (destination comment URL, gist count, whether SIMPLE PATH or relay
mode was used), then end with a single `[OK]`/`[FAIL]` line summarizing the whole chain (branch created, Worker
delegated, Advisor verification result, relay result), followed by a `Next:` line naming the concrete follow-up —
the apply-guide comment URL (relay mode) or the created PR URL (SIMPLE PATH, no relay needed).

## Constraints

See `references/constraints.md` for the full list: never fall back to
`origin`, never delegate implementation while Open Questions are
unresolved, never auto-reset a reused branch that has unique commits,
never duplicate `gh:relay-merge`'s responsibilities, and how to handle a
failed Advisor verification or a failed `gh:relay-merge` call.

## Related Skills

`gh:relay-merge` (final step — patch+gist relay) · `gh:issue-create` (register the
issue on the destination remote first) · `gh:issue-flow` (same shape when the
destination remote *is* pushable). Flag table: `references/help.md`.
