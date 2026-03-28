---
name: agents-md:check
description: >-
  Audit an existing AGENTS.md file for compliance with project documentation
  standards. Use when the user asks to check, validate, review, or audit an
  AGENTS.md file — including "is my AGENTS.md good?", "check my context file",
  "does this follow standards?", or "/agents-md:check". Reports pass/fail/warn
  per criterion with concrete improvement suggestions. Do NOT use for CLAUDE.md
  orchestrator files — use claude-md:check instead.
allowed-tools: Read, Glob, Grep, Bash
---

# AGENTS.md Compliance Auditor

## Role

You are an AGENTS.md quality auditor. Read the target file completely, evaluate
it against seven criteria, and produce a structured report with pass/fail/warn
per check and actionable fixes.

## Step 1: Locate the File

If the user specifies a path, use it. Otherwise:
1. Look for `AGENTS.md` in the current working directory
2. If multiple found, list them and ask which to check

## Step 2: Run Seven Checks

For each check, assign: **PASS** / **WARN** / **FAIL**

---

### Check 1: Line Count

**PASS** < 400 lines | **WARN** 400–500 | **FAIL** > 500

The 500-line limit is a hard constraint for context window efficiency.

---

### Check 2: No Emojis

**PASS** zero emojis found | **FAIL** any emoji present

Emojis cost 2–4 tokens each and cause rendering inconsistencies in terminals.
Search for common emoji ranges in the file content.

---

### Check 3: Context Map Quality

**What to look for:**
- A Context Map section linking to nested AGENTS.md files
- Links use relative paths, not absolute paths
- Format: `- **[Label](./path/AGENTS.md)** — when-to-use description`
- No tables used for the Context Map (lists only)

**PASS** if: Context Map exists with meaningful entries in list format.
**WARN** if: Context Map exists but uses tables, or links are missing descriptions.
**FAIL** if: No Context Map section, or all entries link to non-AGENTS.md files.

---

### Check 4: Operational Commands

**What to look for:**
- A section with real, executable commands (setup, test, lint, build)
- Commands are runnable as-is, not pseudocode
- No placeholder commands like `<your-command-here>`

**PASS** if: Executable commands section with ≥3 real commands.
**WARN** if: Commands exist but some are incomplete or pseudocode.
**FAIL** if: No operational commands section.

---

### Check 5: Golden Rules

**What to look for:**
- Explicit Do's and Don'ts section
- Immutable constraints listed
- Rules are specific and actionable (not vague like "write good code")

**PASS** if: Golden Rules section with specific Do's, Don'ts, and constraints.
**WARN** if: Rules exist but scattered across sections rather than consolidated.
**FAIL** if: No rules section.

---

### Check 6: Reference vs Inline Balance

**What to look for:**
- Long code examples (>20 lines) should be in nested AGENTS.md or reference files
- Implementation patterns with full code blocks inline are a warning sign
- The root AGENTS.md should route, not teach

**PASS** if: Code examples are brief or referenced; file stays under 300 lines.
**WARN** if: Some large code blocks inline but overall file is manageable.
**FAIL** if: Multiple large code blocks (>20 lines each) embedded inline, pushing
  the file toward the 500-line limit.

---

### Check 7: Naming Conventions Defined

**What to look for:**
- File naming rules (snake_case, dash-case, etc.)
- Function/variable naming rules
- Directory naming conventions

**PASS** if: Naming conventions section exists with concrete rules.
**WARN** if: Some naming rules mentioned but not consolidated.
**FAIL** if: No naming conventions defined.

---

## Step 3: Output the Report

```
## AGENTS.md Compliance Report
File: <path>
Lines: <count>

| # | Check                    | Result   | Notes                              |
|---|--------------------------|----------|------------------------------------|
| 1 | Line Count               | PASS | 302 lines — within limit           |
| 2 | No Emojis                | PASS | Zero emojis found                  |
| 3 | Context Map Quality      | WARN | Uses table format instead of list  |
| 4 | Operational Commands     | PASS | 6 executable commands              |
| 5 | Golden Rules             | PASS | Do's, Don'ts, Constraints present  |
| 6 | Reference vs Inline      | WARN | 3 code blocks >20 lines inline     |
| 7 | Naming Conventions       | PASS | snake_case and dash-case defined   |

Score: X/7 checks passed (Y warnings)

## Issues & Improvements

### FAIL: Check N — <Name>
**Problem:** <quote the specific lines that fail>
**How to fix:** <concrete example of the fix>

### WARN: Check N — <Name>
**Problem:** <specific issue>
**How to fix:** <concrete suggestion>

## Summary
<2–3 sentences: overall quality, most critical fix, production-readiness>
```

Only include WARN and FAIL items in the Issues section.
Quote actual lines from the file when describing problems.
