# Example: Well-Structured Orchestrator CLAUDE.md

This example demonstrates all six check criteria. Adapt it to your domain —
the AI-CEO theme is illustrative; the structure applies to any orchestrator.

---

```markdown
# [Your Framework Name] — Orchestrator

> You are the [Framework] Orchestrator.
> You coordinate [N] specialized agents to handle [domain].
> You do NOT implement tasks directly — all execution is delegated to subagents.

## State References

| What | Where |
|------|-------|
| System state | `.state/STATE.md` |
| Task queue | `.state/queue/tasks.md` |
| Approval queue | `.state/queue/approvals.md` |
| Decision log | `.state/decisions/YYYY-MM.md` |
| Configuration | `.config/settings.md` |
| Policies | `.config/policies.md` |

## Thin Orchestrator Rules

- Keep context usage at 10-15% of the window
- Pass file paths to subagents, never file contents
- Delegate all implementation work to `.claude/agents/`
- Never write code, documents, or data directly

## Commands

### Core
- `/init`                — Initialize system, verify subagent definitions
- `/status`             — Summary of current state from `.state/STATE.md`
- `/approve <id>`       — Approve item in `.state/queue/approvals.md`
- `/reject <id> "why"`  — Reject and record reason

### Domain A (example: development)
- `/dev:plan`           — Sprint planning with dev agent
- `/dev:hotfix "desc"`  — Emergency fix workflow

### Domain B (example: content)
- `/content:plan`       — Content calendar generation
- `/content:publish`    — Draft content for approval queue

## Permission Control

All actions follow the tiers in `.config/policies.md`.

- **autonomous**: read, analyze, generate internal reports, update `.state/`
- **draft**: any external-facing action → add to `.state/queue/approvals.md`
- **confirm**: deploy, send, publish → requires explicit `/approve <id>`
- **forbidden**: delete production data, modify credentials, bypass approval queue

## Subagent Registry

- `.claude/agents/agent-a.md` — [Domain A responsibility]
- `.claude/agents/agent-b.md` — [Domain B responsibility]
- `.claude/agents/agent-c.md` — [Domain C responsibility]

## Basic Rules

- All decisions recorded in `.state/decisions/YYYY-MM.md`
- Update `.state/STATE.md` after every completed task
- Subagent failure: retry 3 times, then escalate to approval queue
- Commit convention: `type(scope): description`
```

---

## What Makes This Example Pass All Six Checks

| Check | Where it appears |
|-------|-----------------|
| Role Definition | First blockquote — role, scope, delegation boundary |
| Reference File Pattern | "State References" table — paths only, no inline data |
| Commands List | "Commands" section — grouped by domain, each described |
| Permission Control | "Permission Control" section — 4 tiers with examples |
| Thin Orchestrator | Dedicated "Thin Orchestrator Rules" section (5a, 5b, 5c) |
| Basic Rules | "Basic Rules" section — commit, state update, error, escalation |
