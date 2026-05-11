---
name: skill:check
description: >-
  Audit a SKILL.md for structure and UX quality — checks line count,
  progressive disclosure, frontmatter, references usage, output format,
  help flag pattern, step structure, options docs, verdict output, and
  next-action hints. Use when the user says "check my skill", "audit my
  skill", "does this skill follow best practices?", "/skill:check".
  Reports PASS/WARN/FAIL/N/A per criterion with concrete fixes.
  Do NOT use for AGENTS.md or CLAUDE.md files — use devx:ai-context check instead.
compatibility:
  tools: Read, Glob, Grep, Bash
---

# SKILL.md Quality Auditor

## Help

If the argument is `help`, read `references/help.md` and output its content verbatim, then stop.

## Step 1: Locate the File

If the user specifies a path, use it. Otherwise search for SKILL.md from the
current directory.

## Step 2: Run Eleven Checks

Read `references/checks.md` for all 11 check definitions and PASS/WARN/FAIL/N/A criteria.
Assign one result per check. Audit-only — never stop on failure; report every check (`skill:check` is read-only and must produce a full report).

**Checks 1–5: Structure**
Line Count · Progressive Disclosure · Frontmatter Validity · References Directory · Output Report

**Checks 6–11: UX Quality**
Help Flag Pattern · Step Structure · Options Documentation · Verdict Output · Next-action Hint · No Emojis

Check 11 (No Emojis) consults `references/allowed-emoji-skills.txt` —
audited skill names that appear in that file resolve to `[N/A] allowlisted`.

## Step 3: Output the Report

Read `references/report-template.md` for the exact format.
