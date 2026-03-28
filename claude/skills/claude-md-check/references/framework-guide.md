# AI Agent Orchestrator Framework — Core Principles

This guide summarizes the design principles behind well-structured AI agent
orchestrator systems. Use this as a reference when auditing or building a
CLAUDE.md for any AI agent framework.

---

## What Is an Orchestrator?

An orchestrator is a top-level AI agent that:
- Receives high-level instructions from a human operator
- Decomposes them into tasks
- Delegates tasks to specialized subagents
- Synthesizes results and manages state

The orchestrator does NOT do implementation work directly. Its job is coordination.

---

## The Six Principles

### 1. Role Clarity

Every orchestrator needs an explicit identity:

```markdown
> You are the [Name] Orchestrator.
> You are responsible for [scope].
> You do NOT handle: [delegation targets].
```

Without this, the agent has no self-model and will drift into doing
implementation work it should delegate.

### 2. Reference File Pattern

The orchestrator CLAUDE.md should contain:
- WHERE to find information (file paths)
- HOW to route tasks (which subagent handles what)
- WHAT rules apply (operating constraints)

It should NOT contain:
- The information itself (KPIs, personnel lists, product specs)
- Implementation details (code patterns, CLI commands for specific tools)
- Data that changes frequently (current state, metrics)

Rationale: inlining data bloats context, creates staleness, and breaks the
single-responsibility principle. Reference files stay current independently.

### 3. Commands Interface

Users interact with orchestrators through named commands. A command is:
- A trigger phrase or slash-command
- A defined action or workflow
- A predictable output or side effect

Without a commands section, the orchestrator's capabilities are opaque and
the human operator must guess what to ask.

### 4. Permission Tiers

Every agent system needs at least two permission tiers:

| Tier | Description | Examples |
|------|-------------|---------|
| Autonomous | Execute without asking | Read files, generate reports, update internal state |
| Confirm | Require human approval | Send messages, deploy, publish, delete |

Add more tiers as complexity grows (e.g., "draft", "execute with notification").
The key rule: **any action visible to the outside world requires approval.**

### 5. Thin Orchestrator

Context window is a finite resource. The orchestrator should use as little of it
as possible, because:
- Deep context = slow responses
- Full context = less room for task results
- Bloated context = the orchestrator "forgets" earlier instructions

The three rules:
1. Keep context usage to 10-15% of the window
2. Pass file paths to subagents, never file contents
3. Never do implementation work directly — delegate everything

### 6. Operating Rules

Cross-cutting rules prevent drift over long sessions:
- Version control conventions (commit format, when to commit)
- State update discipline (which files to update after which actions)
- Error handling (retry policy, escalation path)
- Logging conventions (where decisions are recorded)

---

## Directory Structure Pattern

```
project/
├── CLAUDE.md                  # Orchestrator definition (thin)
├── .claude/
│   └── agents/                # Subagent definitions
│       ├── agent-a.md
│       └── agent-b.md
└── .state/                    # Mutable state files (referenced by path)
    ├── STATE.md               # Current system state
    ├── decisions/             # Decision log
    │   └── YYYY-MM.md
    └── queue/                 # Pending approvals
        └── approval-queue.md
```

The exact directory names don't matter. What matters:
- CLAUDE.md stays thin (routing + rules only)
- State lives in dedicated files, updated by agents
- Subagents are defined in their own files with clear scope

---

## When to Use This Pattern

This framework pattern is appropriate when:
- Multiple specialized agents need coordination
- Tasks span multiple sessions (state must persist)
- External actions need human oversight
- The system will grow over time (new agents, new commands)

It is overkill for:
- Single-purpose scripts
- One-off automation tasks
- Simple read-only analysis pipelines
