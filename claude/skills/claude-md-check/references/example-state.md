# Example: State File Structures

State files are the persistent memory of an AI agent system. They are:
- Written by agents after task completion
- Read by the orchestrator to understand current system status
- Never embedded in CLAUDE.md — always referenced by path

---

## System State (.state/STATE.md)

The single source of truth for overall system health and current focus.

```markdown
# System State

## Status: [ACTIVE / PAUSED / ERROR]

## Current Focus
<one-line description of what the system is working on right now>

## Active Tasks
| Agent | Task | Started | Status |
|-------|------|---------|--------|
| dev   | ... | YYYY-MM-DD | in progress |
| content | ... | YYYY-MM-DD | waiting |

## Recent Completions (last 7 days)
- YYYY-MM-DD: <what was completed>
- YYYY-MM-DD: <what was completed>

## Blockers
- <blocker description> — waiting on: <what/who>

## Last Updated: YYYY-MM-DD by <agent-name>
```

---

## Agent State (.state/{domain}/STATE.md)

Each agent maintains its own state file. The orchestrator reads these
when generating a system-wide status report.

```markdown
# {Agent Name} — State

## Status: [ACTIVE / IDLE / ERROR]

## Current Tasks
- [ ] <task> — due: YYYY-MM-DD
- [x] <completed task> — done: YYYY-MM-DD

## KPIs (if applicable)
| Metric | Current | Target | Trend |
|--------|---------|--------|-------|
| ...    | ...     | ...    | up/down/flat |

## Recent Output
| Date | Output | Notes |
|------|--------|-------|
| YYYY-MM-DD | <deliverable> | ... |

## Blockers
- <blocker or "none">

## Last Updated: YYYY-MM-DD
```

---

## Approval Queue (.state/queue/approvals.md)

All external-facing actions wait here for human approval before execution.

```markdown
# Approval Queue

## Pending

### [ID-001] Deploy v2.3.1 to production
- **Requested by**: dev agent
- **Date**: YYYY-MM-DD
- **Action**: `./deploy.sh v2.3.1 --env production`
- **Rationale**: Hotfix for login bug (see .state/decisions/YYYY-MM.md)
- **Risk**: Low — reverts cleanly with `./rollback.sh`
- **Approve**: `/approve ID-001`
- **Reject**: `/reject ID-001 "reason"`

### [ID-002] Send weekly newsletter
- **Requested by**: content agent
- **Date**: YYYY-MM-DD
- **Action**: Send to 1,200 subscribers via Mailchimp
- **Preview**: `.state/content/newsletter-YYYY-MM-DD.md`
- **Approve**: `/approve ID-002`

## Approved (last 30 days)
| ID | Action | Approved | By |
|----|--------|----------|----|
| ID-000 | ... | YYYY-MM-DD | human |

## Rejected
| ID | Action | Rejected | Reason |
|----|--------|----------|--------|
```

---

## Decision Log (.state/decisions/YYYY-MM.md)

Persistent record of significant decisions. Enables retrospectives and
prevents re-litigating resolved questions.

```markdown
# Decision Log — YYYY-MM

## YYYY-MM-DD: <Short Decision Title>

- **Decision**: <what was decided>
- **Context**: <why this came up>
- **Rationale**: <why this option was chosen>
- **Alternatives considered**: <other options and why they were rejected>
- **Impact**: <which agents / parts of the system are affected>
- **Next action**: <what happens now>
```

---

## State File Design Rules

1. **Agent writes, orchestrator reads** — agents update their own state;
   the orchestrator reads state to coordinate, not to store data itself

2. **Flat over nested** — prefer `.state/dev/STATE.md` over `.state/STATE.md`
   having a dev section; easier to delegate and reason about ownership

3. **Date every update** — always include "Last Updated: YYYY-MM-DD" so
   the orchestrator can detect stale state

4. **Status emoji-free** — use text status (ACTIVE/IDLE/ERROR) not emoji,
   for terminal compatibility and grep-friendliness

5. **Queue is append-only** — never delete from approval queue; move to
   Approved/Rejected sections for audit trail
