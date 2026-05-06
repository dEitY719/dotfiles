---
name: devx:restart
description: >-
  Resume the previous in-progress task after an API error (socket disconnect,
  service flake, OOM, etc.) without losing context. Use when the user runs
  /devx:restart, /devx-restart, or asks "다시 작업해", "이어서 해줘",
  "끊긴 데서 재개", "API 에러 복구". Identifies the in_progress TodoList
  item, breaks the next step into single-tool-call chunks, and delegates
  large reads/searches to subagents (Explore / general-purpose) so the main
  context stays small. Does NOT re-invoke a process skill (brainstorming /
  TDD / debugging) that already produced output earlier in the conversation —
  it resumes from the implementation step they led to. Accepts
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Edit, Write, Grep, Agent
---

# devx:restart — Resume After API Error

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No tool calls beyond that read.

## Role

The user invokes this when their previous work was interrupted — typically by
an `API Error: socket connection was closed unexpectedly` or similar
service-side flake. Pick up where the prior turn left off, but do it in
smaller chunks so the next failure costs less. Stay in the current session;
don't ask the user to start over.

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

Print one line so the user sees what you picked up:

```
재개: <task subject> — 작은 단위로 쪼개서 진행합니다.
```

Then mentally split the next concrete action into 1-tool-call increments:

- One `Read` per file (no batch reads of 5 files).
- One `Edit` per logical change (no multi-file `replace_all` sweeps).
- One `Bash` per command (avoid long `&&` chains that re-run on retry).
- One subagent per investigation (don't fan out 4 in parallel here — the
  whole point is to reduce blast radius on the next flake).

Mark the task `in_progress` with `TaskUpdate` if it isn't already.

## Step 3: Delegate Large Outputs

Anything that would dump > ~200 lines into the main context (broad `grep`,
`find` over the whole repo, reading a 1k-line file you only need a slice of,
multi-file conformance checks) MUST be delegated to a subagent:

- Broad code search / cross-file consistency → `Agent(subagent_type=Explore)`.
- Multi-step research or "go figure out X" → `Agent(subagent_type="general-purpose")`.

Brief the agent with the resume target and ask for a < 200-word report.
Keep the main context lean so the next API hiccup doesn't wipe progress.

## Step 4: Execute, Then Hand Back

Run the chunked steps. After each step:

1. Update the TodoList (`TaskUpdate` → `completed` or new `in_progress`).
2. Emit one short user-facing line about what just landed.

When the originally-interrupted task is done, hand control back to whatever
flow the user was in (e.g. continue `gh:issue-flow`'s next sub-step). Do
NOT silently return to idle without saying which step is next.

## Constraints

- Never re-run a process skill that already produced output earlier in the
  conversation — read its result from context instead.
- Never batch tool calls "to be efficient" inside this skill; the whole
  premise is that the previous batch died mid-way.
- Never modify TodoList task subjects — only status. The user wrote the
  subjects; rewriting them loses intent.
- Never silently skip the announce line in Step 2 — the user needs to see
  what you picked up so they can correct it cheaply if it's wrong.
- Never invoke this skill from inside another skill. It is user-triggered
  recovery, not a programmable building block.
