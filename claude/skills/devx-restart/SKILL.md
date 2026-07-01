---
name: devx:restart
description: >-
  API 소켓 에러, OOM, 인증 만료(Not logged in), 또는 ESC 키로 현재 세션이
  중단된 후 재개할 때 —
  [Claude Code Only] Resume the previous in-progress task after an interruption
  — an API error (socket disconnect, service flake, OOM, etc.), an auth
  expiry (`Not logged in`), or the user pressing ESC because the turn was
  running too long — without losing context. Use when the user runs
  /devx:restart, /devx-restart, or asks "다시 작업해",
  "이어서 해줘", "끊긴 데서 재개", "API 에러 복구",
  "15분 이상 걸려서 ESC 눌렀어", "작업이 너무 커서 중단했어",
  "다시 로그인했어", "oversized turn interrupted by user ESC". Identifies the in_progress
  TodoList item, breaks the next step into single-tool-call chunks, and
  delegates large reads/searches to subagents (Explore / general-purpose)
  so the main context stays small. Does NOT re-invoke a process skill
  (brainstorming / TDD / debugging) that already produced output earlier
  in the conversation — it resumes from the implementation step they led
  to. Accepts `-h`/`--help`/`help` to print usage.
  (토큰 한계 리셋 후 크론 자동 재개는 devx:resume-after-limit 사용)
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
