---
name: skill:check
description: >-
  Audit a SKILL.md file for Progressive Disclosure compliance — checks if it
  follows the under-100-lines rule and properly separates detail into references/.
  Use when the user says "check my skill", "is my SKILL.md too long?", "audit
  my skill structure", "does this skill follow progressive disclosure?",
  "/skill:check". Reports PASS/WARN/FAIL per criterion with concrete fixes.
  Do NOT use for AGENTS.md or CLAUDE.md files — use agents-md:check or
  claude-md-check instead.
compatibility:
  tools: Read, Glob, Grep, Bash
---

# SKILL.md Progressive Disclosure Auditor

## Step 1: Locate the File

If the user specifies a path, use it. Otherwise search for SKILL.md from the
current directory. Also check: `ls $(dirname <path>)/` for a `references/` dir.

## Step 2: Run Five Checks

Assign **PASS** / **WARN** / **FAIL** per check.

**Check 1: Line Count**
PASS ≤ 100 | WARN 101–150 | FAIL > 150
Every line over 100 is a candidate for `references/` extraction.

**Check 2: Progressive Disclosure Structure**
PASS — workflow phases only in SKILL.md; detail in `references/`
WARN — mostly workflow but some templates/tables inline
FAIL — large reference content embedded directly in SKILL.md

**Check 3: Frontmatter Validity**
Look for: `name` (no colons, lowercase + hyphens only), `description` present,
only supported attributes (`name`, `description`, `compatibility`, `metadata`,
`user-invocable`, `argument-hint`, `disable-model-invocation`, `license`).
No `allowed-tools` — use `compatibility.tools` instead.
PASS — valid | WARN — minor issues | FAIL — missing fields or unsupported attrs

**Check 4: References Directory Usage**
PASS — `references/` exists with focused files, each referenced from SKILL.md
WARN — `references/` exists but not clearly triggered from SKILL.md body
FAIL — SKILL.md > 100 lines AND no `references/` directory

**Check 5: Output Report Defined**
PASS — output format with example clearly defined
WARN — output described but vague
FAIL — no output format defined

## Step 3: Output the Report

Read `references/report-template.md` for the exact format.
