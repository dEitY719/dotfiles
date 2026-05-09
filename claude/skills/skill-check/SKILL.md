---
name: skill:check
description: >-
  Audit a SKILL.md for structure and UX quality — checks line count,
  progressive disclosure, frontmatter, references usage, output format,
  help flag pattern, step structure, options docs, verdict output, and
  next-action hints. Use when the user says "check my skill", "audit my
  skill", "does this skill follow best practices?", "/skill:check".
  Reports PASS/WARN/FAIL/N/A per criterion with concrete fixes.
  Do NOT use for AGENTS.md or CLAUDE.md files — use agents-md:check or
  claude-md-check instead.
compatibility:
  tools: Read, Glob, Grep, Bash
---

# SKILL.md Quality Auditor

## Help

If the argument is `help`, read `references/help.md` and output its content verbatim, then stop.

## Step 1: Locate the File

If the user specifies a path, use it. Otherwise search for SKILL.md from the
current directory.

## Step 2: Run Ten Checks

Read `references/checks.md` for all 10 check definitions and PASS/WARN/FAIL/N/A criteria.
Assign one result per check.

**Checks 1–5: Structure**
Line Count · Progressive Disclosure · Frontmatter Validity · References Directory · Output Report

**Checks 6–10: UX Quality**
Help Flag Pattern · Step Structure · Options Documentation · Verdict Output · Next-action Hint

## Step 3: Output the Report

Read `references/report-template.md` for the exact format.
