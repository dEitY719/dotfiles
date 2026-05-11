# devx:ai-context — Core + Adapter Checks

For each check, assign **PASS** / **WARN** / **FAIL** and quote the
specific lines that drove the verdict. Adapter checks run in addition to
core checks and are selected by detected `kind` (`agents` / `claude` /
`gemini`).

The rationale links to `industry-baseline.md` for tool-specific spec
quotes (Codex / Claude Code / Gemini CLI).

---

## Core checks (apply to all kinds)

### C1. Role / Purpose
- **PASS** — explicit role, scope, and ownership stated near the top of
  the file (e.g. `**Purpose**`, `**Ownership**`, `# Module Context`).
- **WARN** — role exists but boundaries (what the file is *not* responsible
  for) are vague.
- **FAIL** — no role definition at all.

### C2. Operational Commands
- **PASS** — at least three executable commands listed (setup / lint / test
  / build), runnable as-is, no pseudocode placeholders.
- **WARN** — commands exist but some are pseudocode, or the section is
  scattered across the body rather than consolidated.
- **FAIL** — no commands section.

### C3. Loading & Scope Model
- **PASS** — file states *when* it loads (auto on session start, on demand,
  via import) and *which agents* read it.
- **WARN** — implicit only — readers can guess but it is not documented.
- **FAIL** — no scope statement.

### C4. Modular References
- **PASS** — long-form content (rule sets, full implementation guides,
  large code blocks) lives in nested AGENTS.md / `references/` / linked
  files. Root file routes rather than teaches.
- **WARN** — some content inlined but file remains manageable.
- **FAIL** — multiple large blocks (>20 lines each) embedded inline.

### C5. Naming Conventions
- **PASS** — file / function / directory naming rules are stated.
- **WARN** — partial or scattered.
- **FAIL** — none.

### C6. Constraints / Golden Rules
- **PASS** — explicit Do / Don't list, constraints are actionable.
- **WARN** — rules exist but scattered across sections.
- **FAIL** — no rules section.

### C7. Size / Context Budget
- **PASS** ≤ 400 lines (root) | **WARN** 400–500 | **FAIL** > 500.
- Rationale: token cost + load latency. Each tool publishes its own
  payload limit — see `industry-baseline.md`.

---

## Adapter `agents` (AGENTS.md, OpenAI Codex)

Spec source: <https://developers.openai.com/codex/guides/agents-md>.

### A-AG1. Discovery
- **PASS** — file is at the project root *or* nested at a subdirectory
  Codex actually walks into.
- **FAIL** — file is buried where Codex will not auto-discover it.

### A-AG2. Override / fallback
- **PASS** — when nested AGENTS.md files exist, root explicitly states
  they override (or are merged with) the root for that subtree.
- **WARN** — nested files exist but precedence is undocumented.
- **N/A** — single AGENTS.md (no nesting).

### A-AG3. Payload budget
- **PASS** — root + nested combined within Codex's documented payload cap.
- **WARN** — close to the cap.
- **FAIL** — over the cap (cite combined byte count).

### A-AG4. Context Map
- **PASS** — list-formatted Context Map enumerating nested AGENTS.md files
  with `when-to-use` descriptions.
- **WARN** — exists but uses tables, or links omit descriptions.
- **FAIL** — no Context Map and the project has nested AGENTS.md files.
- **N/A** — single AGENTS.md (no map needed).

---

## Adapter `claude` (CLAUDE.md, Claude Code)

Spec source: <https://code.claude.com/docs/en/memory>.

### A-CL1. Reference-by-path
- **PASS** — operational data (KPIs, personnel, inventory, large tables)
  referenced by file path; CLAUDE.md remains thin.
- **WARN** — some inlining but most content is path-referenced.
- **FAIL** — major operational content embedded directly.

### A-CL2. Permission Control
- **PASS** — at least two permission tiers defined (e.g. `read-only` /
  `execute`); external-side-effect actions covered (`always_draft` or
  equivalent), with an approval workflow stated.
- **WARN** — some rules but external-action coverage is incomplete.
- **FAIL** — no permission rules.
- **N/A** — file documents project context only, not orchestration.

### A-CL3. Thin Orchestrator (sub-criteria)
- **3a. Context minimization** — instructs the agent to keep its own context
  small, avoid loading file contents directly.
- **3b. Path-over-content delegation** — subagents receive paths, not
  contents.
- **3c. Subagent delegation** — complex tasks delegated (e.g. via
  `.claude/agents/`).
- **PASS** — all three present.
- **WARN** — one or two present.
- **FAIL** — none — orchestrator does direct work with no delegation.
- **N/A** — non-orchestrator file.

### A-CL4. Local + rules layout
- **PASS** — file or its links acknowledge `CLAUDE.local.md` and
  `.claude/rules/` (when applicable to the project).
- **WARN** — partial.
- **N/A** — single-file project with no `.claude/` tree.

---

## Adapter `gemini` (GEMINI.md, Gemini CLI)

Spec source: <https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html>.

### A-GE1. Hierarchy
- **PASS** — file documents (or correctly inhabits) the global / workspace
  / project layering (`~/.gemini/GEMINI.md` + workspace + project).
- **WARN** — single layer present but layering not acknowledged.
- **N/A** — only a global file (no workspace/project layer applicable).

### A-GE2. `/memory` & imports
- **PASS** — file states whether it imports other files (Gemini supports
  imports), or notes that `/memory` is the supported edit path.
- **WARN** — imports used implicitly without acknowledgement.

### A-GE3. `.geminiignore`
- **PASS** — references or honors `.geminiignore` for excluded paths.
- **N/A** — project does not need exclusions.

---

## Verdict aggregation

- All checks PASS → `[OK]`.
- Any FAIL → `[FAIL]`.
- WARN-only → `[OK]` with warning count surfaced.
- `N/A` results do not count toward pass/fail tally.
