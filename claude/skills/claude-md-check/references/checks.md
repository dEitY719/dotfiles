# claude-md-check — Six Orchestrator Checks

For each check, assign **PASS** / **WARN** / **FAIL** and quote the
specific lines that drove the verdict.

---

## Check 1: Role Definition

The orchestrator must know what it is and what it owns.

**Look for:**
- Explicit agent role/title/persona at the top of the file
- Scope statement: what the agent is responsible for
- Boundaries: what it does NOT do (delegation targets)

**PASS** — role named, responsibility and scope stated
**WARN** — role exists but scope or boundaries are vague
**FAIL** — no role definition at all

---

## Check 2: Reference File Path Pattern

The CLAUDE.md should be a routing layer, not a data store.

**Look for:**
- State, configuration, and domain knowledge referenced by file path
- No large inline tables of operational data (KPIs, personnel, inventory)
- File is thin — length comes from rules/routing, not embedded content

**PASS** — information referenced by path; file stays thin
**WARN** — some content inlined but most is path-referenced
**FAIL** — major operational content embedded directly in CLAUDE.md

**Heuristic:** file over 300 lines warrants close inspection of what's inlined.

---

## Check 3: Commands Interface

Users and other agents need a clear, discoverable interface.

**Look for:**
- Dedicated section listing available slash-commands
- Commands grouped by domain or agent responsibility
- Each command has a one-line description

**Also check** whether the project uses a `.claude/commands/` directory:
- `commands/` files are thin execution scripts (5-10 steps, no persona)
- `agents/` files are rich domain experts (persona, RACI, workflows)
- If `commands/` exists, CLAUDE.md commands list should map to those files

**PASS** — commands section exists with entries and descriptions
**WARN** — commands exist but undocumented, scattered, or incomplete;
  OR agents/ exists but commands/ separation is missing/unclear
**FAIL** — no commands section at all (for an orchestrator-type file)

*Note: if this CLAUDE.md is for a simple single-purpose agent, absence of
commands is acceptable — note this and downgrade to WARN.*

---

## Check 4: Permission Control Rules

Every agent needs guardrails on what it can do autonomously.

**Look for:**
- Explicit classification: what runs automatically vs. what needs approval
- At minimum two tiers; well-structured systems have four:
  - `read-only` — analysis/reports, no side effects, auto-execute
  - `execute` — internal actions within threshold, auto-execute
  - `auto_after_approval` — template-based, approved once then auto
  - `always_draft` — external-facing actions, always require human approval
- The `always_draft` list must cover: deploys, client comms, SNS, invoices
- The approval workflow pipeline: draft → approval-queue → `/approve` → execute
- Reference to a permissions file (e.g., `.company/steering/permissions.md`)

**PASS** — permission tiers defined, approval workflow clear, external actions covered
**WARN** — some rules exist but external actions or thresholds are undefined
**FAIL** — no permission or authorization rules at all

See `example-permissions.md` for a complete permissions file structure.

---

## Check 5: Thin Orchestrator Principle

The most important architectural check. Three sub-criteria:

**5a. Context minimization**
Does the file instruct the agent to keep its own context footprint small?
Is there guidance to avoid loading file contents directly?

**5b. Path-over-content delegation**
Are subagents instructed to receive file paths rather than file contents?
Is "pass the path, not the content" stated or clearly implied?

**5c. Subagent delegation**
Are complex tasks delegated to subagents (e.g., `.claude/agents/`)?
Does the orchestrator avoid doing direct implementation work itself?

**PASS** — all three sub-criteria explicitly addressed
**WARN** — one or two sub-criteria addressed
**FAIL** — orchestrator does direct work with no delegation structure

---

## Check 6: Basic Rules

Operating principles that apply across all commands and agents.

**Look for:**
- Commit / version control conventions
- State update requirements after task completion
- Error handling and escalation policy
- Any cross-cutting rules that apply everywhere

**PASS** — consolidated rules section with meaningful entries
**WARN** — rules exist but scattered across sections
**FAIL** — no general operating rules
