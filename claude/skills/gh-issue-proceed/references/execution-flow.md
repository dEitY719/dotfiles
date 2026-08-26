# gh:issue-proceed — Execution semantics (Step 3)

## Step loop (pseudocode)

```
parsed_steps = parse(execution_protocol)          # matrix or numbered (schema §3)

for step in parsed_steps:
    TaskCreate(subject="Step <n>: <description>",
               activeForm="Executing step <n>")
    start = now()

    result = execute(step,
                     out_of_scope=section["out_of_scope"],
                     safety_layer1=ABSOLUTE_BLOCK_PATTERNS)

    classification = classify(result,
                              allowed=decision_rules.keys,
                              fail_closed_on_unknown=True)   # never invent a class

    apply(decision_rules[classification])                    # §verb registry below

    TaskUpdate(taskId=step.id, status=completed,
               metadata={"result": ..., "classification": ...})

    if now() - start > per_step_timeout:
        apply(decision_rules["TIMEOUT"])                     # retroactive

if all_done_criteria_met and no_abort:
    close_proceed_issue()                                    # self-close (no quota cost)
else:
    keep_open + final_comment
```

## Done-criteria semantics

- Parse all `- [ ]` / `- [x]` items from `done_criteria`.
- `- [x]` items are assumed pre-satisfied (authoring-time).
- Each `- [ ]` item is matched against executed write actions + step
  classifications. Every `- [ ]` item with a matching audit entry →
  `done_criteria_met = True`.
- Ambiguous matching (item text doesn't clearly map to any verb) →
  `done_criteria_met = False`; the skill keeps the issue open.

## Action verb registry

Fixed allowlist. An unknown verb in a decision rule → **fail-closed at
parse time** (before any step runs).

| Verb | Implementation |
|---|---|
| `continue` | proceed to next step |
| `file_issue: <template-key>` | `Skill(gh:issue-create, "--no-ask …")`. Template source: §decision_rules may define named inline templates; `<template-key>` references one by name. No match → minimal default `{title:"<auto>", body:"Filed by /gh:issue-proceed from #<N> step <s>", labels:[]}` |
| `queue_doc_patch: <file>` | accumulate; flushed as a single commit + PR at end of loop |
| `comment_on_self: <body>` | `gh issue comment <PROCEED_N>` |
| `comment_on_other: <N> <body>` | `gh issue comment <N>` |
| `commit_changes` | `Skill(gh:commit)` |
| `open_pr` | `Skill(gh:pr)` |
| `close_issue: <N>` | `gh issue close <N>` |
| `abort_all` | break + final report; proceed issue stays open |
| `skip` | record result only; next step |

## Composition payload protocol

When the skill calls another skill, the payload is **always structured**
(no free-form prompt):

```
Skill(gh:issue-create, "--no-ask", prompt=<<STRUCTURED
TITLE: <...>
BODY: <markdown>
LABELS: <comma-list>
NO_INTERACTIVE: true
STRUCTURED)
```

Callees that see `NO_INTERACTIVE: true` skip confirmation prompts.

**`gh:issue-create` 는 예외 — `--no-ask` 가 정본이다 (#1460).** 이 경계에서
무인성의 근거는 `NO_INTERACTIVE` 필드가 아니라 `--no-ask` 플래그다. 수신측이
실제로 구현·문서화·테스트한 규약이 그쪽이기 때문이다 (#1446 / PR #1455).
플래그 없이 STRUCTURED 필드만 넘기면 Step 3.1 미결 게이트가 응답할 사람이
없는 자리에서 확인을 기다린다. 이 verb 를 호출할 때 `--no-ask` 를 빼지 않는다.

> **Follow-up (design Open-Q3, non-blocking for this skill):** `/gh:commit`
> and `/gh:pr` do not yet formally honor the `STRUCTURED` /
> `NO_INTERACTIVE` contract. Until they do, this skill passes the structured
> block as the prompt and relies on each callee's existing
> no-confirmation-by-design behavior (both already create their
> artifact without an interactive prompt). Tracked as a separate issue;
> it does not block `/gh:issue-proceed` shipping.

## Edge cases

| Case | Behavior |
|---|---|
| Issue already CLOSED | Step 2.1 refusal (`already closed`); precedes schema check |
| Hierarchical protocol (H4+ sub-protocols) | only the canonical `execution_protocol` section is parsed for steps; H4 content is context only |
| Re-running a partially-done issue | TaskList consulted; resume at first non-completed step **iff** the body declares `Re-runnable: true`; else abort `[manual-review] non-idempotent rerun` |
| Network failure mid-step | retry once; second failure → BLOCKED via decision rules |
| Directive references a nonexistent file/command | classify FAIL; comment `[doc-bug] protocol references nonexistent <X>`; abort |
| Decision rules don't cover an actual result class | first unhandled → BLOCKED; counts as a dynamic schema violation |
