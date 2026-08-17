---
name: gh:issue-relay-flow
description: >-
  Composition skill that turns an already-filed GitHub issue on a
  push-blocked destination remote into a relayed PR in one call: resolve
  the destination remote + create a branch off its default branch → delegate
  implementation (Advisor/Worker) → Advisor verifies the diff and runs the
  target repo's lint/test commands → `gh:relay-merge --commits` uploads the
  patches and posts the apply-guide. Use when the user runs
  /gh:issue-relay-flow, /gh-issue-relay-flow, or asks "이슈 번호로 브랜치
  따고 구현하고 relay까지", "사내PC에서 구현해서 upstream으로 릴레이해줘",
  "issue #1346 브랜치 만들고 Worker 위임하고 relay-merge까지 한 번에". Issue
  registration itself is out of scope — the issue must already exist on the
  destination remote (use `gh:issue-create <remote>` first if it does not).
  Accepts `<issue-number> [--remote <name>] [--base <branch>]` and
  `-h`/`--help`/`help`. The final step is a verbatim
  `Skill(gh:relay-merge, "--commits ...")` call — this skill never
  reimplements patch generation, gist upload, or apply-guide posting.
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "assembly skill — orchestrates branch-setup + Worker delegation + Advisor verification + a gh:relay-merge call, the same composition shape as gh-issue-flow (tier: sonnet)"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-relay-flow — Issue → Branch → Implement → Relay

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

Follow `references/branch-setup.md`. Resolves `--remote` (hard error on a
missing remote — never fall back to `origin`), detects the destination's
default branch (or honors `--base`), fetches it, computes the branch name
`issue-<N>-<title-slug>`, and either creates a fresh branch or handles the
"branch already exists" reuse/reset decision (never auto-resets a branch
that has unique commits without asking).

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

Record `HEAD_SHA=$(git rev-parse HEAD)`, then call `gh:relay-merge`
verbatim — no inline patch/gist/apply-guide logic here. Pass along any
pre-existing unrelated failure paths recorded in Step 4, as exact paths:

`Skill(gh:relay-merge, "--commits <BASE_SHA>..<HEAD_SHA> --target-issue <N> --remote <remote>")`

## Step 6: Report

Relay `gh:relay-merge`'s Step 8 output as-is (destination comment URL, gist
count, whether SIMPLE PATH or relay mode was used), then end with a single
`[OK]`/`[FAIL]` line summarizing the whole chain (branch created, Worker
delegated, Advisor verification result, relay result), followed by a
`Next:` line naming the concrete follow-up — the apply-guide comment URL
(relay mode) or the created PR URL (SIMPLE PATH, no relay needed).

## Constraints

See `references/constraints.md` for the full list: never fall back to
`origin`, never delegate implementation while Open Questions are
unresolved, never auto-reset a reused branch that has unique commits,
never duplicate `gh:relay-merge`'s responsibilities, and how to handle a
failed Advisor verification or a failed `gh:relay-merge` call.
