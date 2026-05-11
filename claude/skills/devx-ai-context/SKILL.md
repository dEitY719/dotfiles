---
name: devx:ai-context
description: >-
  Single entry point for AI context-injection files (CLAUDE.md, AGENTS.md,
  GEMINI.md). Replaces five deprecated skills: agents-md:check / agents-md:create
  / agents-md:refactor / claude-md-check / claude-md-create. Use when the user
  says "check my AGENTS.md", "audit CLAUDE.md", "create AI context file",
  "refactor my context doc", "/devx:ai-context", "/devx-ai-context", or any
  request that touches a CLAUDE.md / AGENTS.md / GEMINI.md file. First
  positional arg is the action: check (default) | create | refactor | help.
  Use --file PATH for a non-standard target and --kind KIND to force the
  adapter (agents / claude / gemini). Do NOT use for SKILL.md (use skill:check)
  or for shell scripts (use sh:check).
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# devx:ai-context — Unified AI Context Doc Skill

Replaces `agents-md:{check,create,refactor}` and `claude-md-{check,create}`.
Legacy skills have been deleted (issue #560) — see
`references/help.md` for the migration table.

## Help

If `$1` is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No file reads beyond that.

## Step 1: Parse Args

Positional: `[action] [path]`. Recognised flags below.

| Arg / Flag      | Description                                       | Default     |
|-----------------|---------------------------------------------------|-------------|
| `action`        | `check` / `create` / `refactor` / `help`          | `check`     |
| `path`          | Explicit target file path                         | auto-detect |
| `--file PATH`   | Same as positional `path`; takes precedence       | —           |
| `--kind KIND`   | Force adapter: `agents` / `claude` / `gemini`     | from name   |
| `-h` / `--help` | Print `references/help.md` verbatim and stop      | —           |

Unknown action → print help and stop.

## Step 2: Resolve Target File

If `--file` (or positional `path`) is given, use it. Otherwise auto-detect
in cwd in priority `CLAUDE.md` → `AGENTS.md` → `GEMINI.md`.

| Situation             | check                                          | create / refactor                       |
|-----------------------|------------------------------------------------|-----------------------------------------|
| One file found        | audit it                                       | proceed against it                      |
| Multiple files found  | audit highest-priority; rest as WARN           | print candidates and prompt; never auto |
| No file found         | abort with hint: `devx:ai-context create`      | proceed (create) / abort (refactor)     |

Map filename → `kind`: `CLAUDE.md`→claude, `AGENTS.md`→agents, `GEMINI.md`→gemini.
`--kind` overrides this mapping for non-standard names.

## Step 3: Dispatch by Action

### action=check (read-only)

Read `references/checks.md` and run **core + adapter** checks against the
target. Core checks always run; adapter checks vary by `kind`. Quote line
ranges that drove each verdict. Never mutate the file.

### action=create (with confirmation)

Run discovery (`Phase 0`):

- `agents` — classify by project size: small (<20 files) / medium (20–100,
  2–3 domains) / large (100+, multiple services).
- `claude` — classify by agent count: simple (1–2) / standard (3–6) / large (7+).
- `gemini` — not yet templated; offer the closest agents template with a
  manual-edit hint.

Read the matching template from `references/templates/`, fill placeholders
from discovery, present a plan, **wait for confirmation**, then write.

### action=refactor (with confirmation)

Read the existing file, list inline blocks / sections that should move to
nested files, present the split plan, **wait for confirmation**, then
extract sections and slim the root.

## Step 4: Report

Use the template in `references/report-template.md` for every action.
Verdict is `[OK]` if no FAIL, else `[FAIL]`. Always end with a `Next:`
line per the same file.

## Constraints

- `check` is audit-only — never mutate the file.
- Always confirm before overwriting in `create` / `refactor`.
- Auto-overwrite is never allowed when multiple context files exist.
- Honor `--file` and `--kind` overrides over auto-detection.
- Cite `references/industry-baseline.md` when stating rationale for adapter
  checks (Codex / Claude Code / Gemini CLI official docs).
- Do NOT run on `SKILL.md` (route to `skill:check`) or `*.sh` (route to
  `sh:check`).
