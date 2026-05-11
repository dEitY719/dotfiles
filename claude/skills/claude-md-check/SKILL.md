---
name: claude-md-check
description: >-
  Audit a CLAUDE.md file for an AI agent orchestrator system. Use when building
  or reviewing any AI agent framework — task automation agents, multi-agent
  pipelines, domain-specific orchestrators, or AI-assisted workflows — and you
  want to verify the CLAUDE.md follows sound orchestrator design principles.
  Triggers on: "check my CLAUDE.md", "is my orchestrator config good?",
  "validate my AI agent setup", "review my agent framework", "/claude-md-check".
  Do NOT use for project context files (AGENTS.md) — use agents-md-check instead.
compatibility:
  tools: Read, Glob, Grep, Bash
---

# CLAUDE.md Orchestrator Auditor

> **DEPRECATED** — superseded by `devx:ai-context`. Migrated equivalent:
> `/devx:ai-context check [path]`. This shim remains functional during
> the transition period; new work should use the unified entry point.
> See `claude/skills/devx-ai-context/references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No file reads beyond that.

## Role

You are an AI agent framework architect and auditor. Read the target
CLAUDE.md, evaluate it against six orchestrator design principles, and
produce a structured report with PASS/WARN/FAIL per check and actionable
improvement suggestions.

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `path`   | Path to CLAUDE.md to audit | search from cwd |

Reference material under `references/`: `checks.md` (Step 2 rubric),
`framework-guide.md`, `example-orchestrator.md`, `example-agent.md`,
`example-state.md`, `example-permissions.md`. Read example files only
when you need a concrete "how to fix" snippet.

## Step 1: Locate the File

If the user specifies a path, use it. Otherwise search for CLAUDE.md from
the current working directory. If the file is named AGENTS.md, stop and
respond: "This is a project context file. Use agents-md:check instead."

## Step 2: Run Six Checks

Read `references/checks.md` for the full rubric. Apply each check to the
target file and record PASS / WARN / FAIL with the line range that drove
the verdict.

1. Role Definition
2. Reference File Path Pattern
3. Commands Interface
4. Permission Control Rules
5. Thin Orchestrator Principle (sub-criteria 5a / 5b / 5c)
6. Basic Rules

## Step 3: Output the Report

```
## CLAUDE.md Orchestrator Audit
File: <path>
Lines: <count>

| # | Check                       | Result | Notes                              |
|---|-----------------------------|--------|------------------------------------|
| 1 | Role Definition             | PASS   | ...                                |
| 2 | Reference File Path Pattern | WARN   | ...                                |
| 3 | Commands List               | PASS   | ...                                |
| 4 | Permission Control Rules    | FAIL   | ...                                |
| 5 | Thin Orchestrator Principle | WARN   | 5a: PASS, 5b: WARN, 5c: FAIL       |
| 6 | Basic Rules                 | PASS   | ...                                |

Verdict: [OK] X/6 passed (Y warnings)    # or [FAIL] when any check fails

## Issues & Improvements

### FAIL: Check 4 — Permission Control Rules
**Problem:** <quote specific lines>
**How to fix:** <concrete example — read references/example-orchestrator.md if needed>

### WARN: Check 2 — Reference File Path Pattern
**Problem:** <specific issue>
**How to fix:** <concrete suggestion>

## Summary
<2-3 sentences: overall quality, most critical fix, production-readiness>

Next: fix the highest-FAIL check first (see references/example-orchestrator.md
for a working template), then re-run /claude-md-check to verify.
```

Use `[OK]` when every check is PASS, otherwise `[FAIL]`. Include only
WARN and FAIL items in Issues. Quote actual lines when describing
problems. Reference examples from `references/` when showing how to fix.
