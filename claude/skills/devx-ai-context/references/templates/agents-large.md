# Large Project Template

Use for projects with 100+ files, multiple services or tech domains.
Target: root AGENTS.md (~200 lines, routing only) + nested per service/domain.

---

## Root AGENTS.md — Routing Tower

The root file does ONE thing: tell Claude where to go. Keep implementation
details out of the root entirely.

```markdown
# Project Context

- **Objective**: <one-line goal>
- **Architecture**: <e.g., "Microservices: API Gateway + 3 backend services + shared libs">
- **Stack**: <high-level overview — details in nested files>

# Operational Commands

## Top-Level
- **Test all**: `<command>`
- **Lint all**: `<command>`
- **Deploy (staging)**: `<command>`

## Per-Service (run from service directory)
- See each service's AGENTS.md for service-specific commands

# Golden Rules

## Universal Constraints (apply to ALL services)
- 500-line limit per AGENTS.md
- No emojis
- No secrets committed
- <cross-cutting constraint>
- <cross-cutting constraint>

## Cross-Service Rules
- DO: <inter-service contract rule>
- DO: <shared library usage rule>
- DON'T: <anti-pattern that crosses service boundaries>

# Architecture Decisions

- <Key decision 1 — e.g., "gRPC for internal, REST for external APIs">
- <Key decision 2 — e.g., "Postgres per service, no shared DB">
- <Key decision 3>
- Full ADRs: `./docs/decisions/`

# Naming Conventions

- **Services**: <pattern>
- **APIs**: <pattern>
- **Shared libs**: <pattern>

# Context Map

## Services
- **[<Service 1>](./<path>/AGENTS.md)** — <responsibility>
- **[<Service 2>](./<path>/AGENTS.md)** — <responsibility>
- **[<Service 3>](./<path>/AGENTS.md)** — <responsibility>

## Shared
- **[Shared Libraries](./<path>/AGENTS.md)** — <what's shared>
- **[Infrastructure](./<path>/AGENTS.md)** — <infra patterns>
- **[Tests](./<path>/AGENTS.md)** — <integration/e2e testing>
```

---

## Nested Service AGENTS.md Template

Each service is fully self-contained. Another engineer (or AI) should be
able to work on the service by reading only its own AGENTS.md.

```markdown
# <Service Name> — <one-line responsibility>

## Context

- **Purpose**: <what business problem this service owns>
- **API**: <e.g., "gRPC on :50051, REST on :8080">
- **Data**: <e.g., "Owns user table in Postgres">
- **Consumers**: <which other services call this>

## Stack

- <runtime> <version>
- <framework> <version>
- <key dependency> <version>

## Commands

- **Dev**: `<command>`
- **Test**: `<targeted test command>`
- **Build**: `<command>`

## Patterns

<2–3 sentences on the architectural patterns used in this service>

## Local Rules

- DO: <service-specific rule>
- DON'T: <service-specific anti-pattern>

## Testing

- **Unit**: `<command>`
- **Integration**: `<command>`
- Required: happy path, <service-specific scenario>, failure/timeout
```

---

## Nesting Decision Guide

```
Is the content universal (all services)? → Root AGENTS.md
Is the content specific to one service?  → Service AGENTS.md
Is it shared utility/library content?    → Shared libs AGENTS.md
Is it deployment/infra content?          → Infrastructure AGENTS.md
```
