# AI Agent Orchestrator Framework — Core Principles

This guide summarizes the design principles behind well-structured AI agent
orchestrator systems, based on real-world implementations.

---

## What Is an Orchestrator?

An orchestrator is a top-level AI agent that:
- Receives high-level instructions from a human operator
- Routes tasks to specialized subagents or executes commands
- Manages shared state and approval workflows
- Synthesizes results and reports back

The orchestrator does NOT do implementation work directly.

---

## Directory Structure

```
project/
├── CLAUDE.md                        # Orchestrator definition (thin)
├── .claude/
│   ├── agents/                      # Subagent definitions (personas + workflows)
│   │   ├── agent-cto.md
│   │   ├── agent-cmo.md
│   │   └── agent-morning.md
│   └── commands/                    # Command execution scripts (thin instructions)
│       ├── cmd-approve.md
│       ├── cmd-dev-sprint.md
│       └── cmd-mkt-campaign.md
└── .company/                        # Mutable state (referenced by path, never inlined)
    ├── STATE.md                     # Company-wide state
    ├── VISION.md                    # Mission / vision (stable, rarely changes)
    ├── ROADMAP.md                   # Quarterly plan
    ├── approval-queue.md            # Pending approvals
    ├── decisions/
    │   └── YYYY-MM.md               # Decision log per month
    ├── departments/
    │   ├── dev/STATE.md
    │   ├── marketing/STATE.md
    │   ├── sales/STATE.md
    │   └── cs/STATE.md
    ├── products/
    │   └── {product-name}/STATE.md
    └── steering/
        ├── permissions.md           # Permission thresholds
        ├── policies.md              # Company-wide policies
        ├── brand.md                 # Brand guidelines
        └── tech-stack.md           # Tech stack reference
```

---

## agents/ vs commands/ — Critical Distinction

This is the most commonly misunderstood part of the framework.

### `.claude/agents/` — Subagent Definitions
Rich files that define WHO handles a domain and HOW they think:
- **Persona**: character, motto, decision-making style
- **Responsibility scope**: what they own (RACI)
- **Domain expertise**: what they know deeply
- **Permission level**: what they can execute vs. what needs approval
- **Reference files**: state/config files they read while working
- **Workflows**: step-by-step process per command
- **Output templates**: what their deliverables look like
- **Quality checklist**: completion criteria

### `.claude/commands/` — Command Execution Scripts
Thin files that define WHAT happens when a command runs:
- 5-10 steps describing the execution sequence
- References to which agent handles what
- References to which state files to update
- No persona, no expertise sections

**Rule**: agents/ is for domain experts. commands/ is for process scripts.

---

## The Six Design Principles

### 1. Role Clarity

```markdown
> You are the [Framework Name] Orchestrator.
> You coordinate [N] specialized agents to handle [domain].
> You do NOT implement tasks — all execution is delegated to subagents.
```

### 2. Reference File Pattern

CLAUDE.md lists WHERE to find information, never contains the information:

```markdown
## 참조처
- 전사 상태: `.company/STATE.md`
- 승인 대기: `.company/approval-queue.md`
- 권한 설정: `.company/steering/permissions.md`
```

Never inline KPIs, personnel lists, product specs, or operational data.

### 3. Commands Interface

Commands are discoverable and have predictable behavior:
```markdown
- `/cmd:approve <id>`       — Approve item in approval queue
- `/cmd:dev:sprint`         — Trigger dev agent sprint workflow
- `/cmd:mkt:content-plan`   — Trigger CMO content planning
```

### 4. Permission Tiers

Based on real implementations, the typical two-tier model:

| Tier | Korean term | When to use |
|------|-------------|-------------|
| **execute** | 자동 실행 | Internal analysis, report generation, state file updates, drafts |
| **draft** | 승인 필요 | Public posts, deploys, external messages, price changes |

Actions in **draft** tier go to `.company/approval-queue.md` and require
`/cmd:approve <id>` before execution.

### 5. Thin Orchestrator

- Context usage target: 10–15% of window
- Pass file paths to subagents, never file contents
- Orchestrator routes — subagents execute

### 6. Operating Rules

- All decisions → `.company/decisions/YYYY-MM.md`
- Every task completion → update relevant `STATE.md`
- State files use status emoji: 🟢 정상 / 🟡 주의 / 🔴 문제 있음 / ⚪ 미가동
- Subagent failure: retry 3 times, then escalate to approval queue
