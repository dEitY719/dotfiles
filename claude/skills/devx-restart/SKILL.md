---
name: devx:restart
description: >-
  [Claude Code Only] 같은 세션에서 중단 직후 이어서 재개 — API 에러·OOM·인증
  만료·ESC 로 턴이 끊겼을 때. Use for /devx:restart, /devx-restart,
  "이어서 해줘", "끊긴 데서 재개", "다시 로그인했어", "resume after an API
  error or ESC". 토큰 리밋 리셋 후 크론 재개는 devx:resume-after-limit.
allowed-tools: Bash, Read, Edit, Write, Grep, Agent, TaskList, TaskUpdate
metadata:
  model_recommendation:
    tier: sonnet
    reason: "interrupt recovery orchestration; TodoList interpretation + 1-tool-call chunking + subagent delegation"
    claude: prefer
    non_claude: advisory-only
---

# devx:restart — Resume After API Error

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No tool calls beyond that read.

## Arguments

Only `-h`/`--help`/`help`; full usage in `references/help.md`. No other args —
this skill reads the TodoList in the current session.

## Role

Stay in the current session; resume the prior task in smaller chunks so the
next failure costs less. Don't ask the user to start over.

## Step 1: Identify the Resume Target

Use `TaskList` to read the current todo list. Pick the resume target by this
precedence:

1. The single `in_progress` task — that is exactly where the prior turn died.
2. If no `in_progress`, the first `pending` task in order.
3. If both are empty, ask the user one short line:
   `재개할 작업이 분명하지 않습니다. 어디서 이어가면 될까요?` and stop.

Do not re-invoke a process skill (`superpowers:brainstorming`,
`superpowers:test-driven-development`, `superpowers:systematic-debugging`,
etc.) just because it appeared earlier — its output is already in the
conversation. Resume from the implementation/edit step those skills led to.

Run `git status --short` once to confirm the working tree actually matches
what the picked task implies — self-reported TodoList status can lag disk
reality (e.g. a task marked `completed` whose files are still uncommitted).
If it contradicts the picked task, tell the user in one line before
proceeding; don't silently resume over a mismatch.

If the picked task is coarser than the actual interruption point (e.g. a
todo like "구현 issue #N" when the prior turn died partway through it),
don't guess — use the last completed tool result already in the
conversation to pinpoint exactly where it died, then resume from there. If
no completed tool result exists in context (e.g. the turn died at session
start), fall back to rule 3 above and ask.

## Step 2: Announce + Plan Smaller Steps

Print the announce line first (success template in
`references/output-format.md`). When Step 1 cannot pick a target, emit the
hard-stop template from the same file instead and stop.

Read `references/chunking-rules.md` for 1-tool-call splitting rules and
subagent delegation thresholds.

Mark the task `in_progress` with `TaskUpdate` if it isn't already.

## Step 3: Delegate Large Outputs

Per the thresholds in `references/chunking-rules.md`, large outputs (broad search, full-repo `find`, multi-file conformance checks) MUST go through a subagent.
Brief it with the resume target and cap the response at ~200 words so the main context stays lean.

## Step 4: Execute, Then Hand Back

Run the chunked steps. After each step:

1. Update the TodoList (`TaskUpdate` → `completed` or new `in_progress`).
2. Emit one short user-facing line about what just landed (format in `references/output-format.md`).

When the originally-interrupted task is done, hand control back to the user's
prior flow. Always end with an explicit `Next:` line naming the next concrete
command — never silently return to idle.

## Output

Read `references/output-format.md` for the success and hard-stop templates,
and for the per-step / `Next:` line rules. Both Step 2 (announce) and Step 4
(progress + handoff) render from that file.

## Constraints

- Never re-run a process skill that already produced output earlier — read its result from context.
- Never batch tool calls "to be efficient"; the premise is that the previous batch died mid-way.
- Never modify TodoList task subjects — only status (rewriting them loses the user's intent).
- Never silently skip the Step 2 announce line — the user must see what you picked up to correct it cheaply.
- Never invoke this skill from inside another skill — it is user-triggered recovery, not a building block.

## Related Skills

Same "resume" family, different trigger — `devx:resume-after-limit` (a cron
fires it after the token-limit reset; this one is same-session, no cron) ·
`devx:session-handoff` (writes the handoff for *unfinished* work before the
context window runs out; this one resumes instead of handing off).
