---
name: skill:refactor
description: >-
  Refactor a SKILL.md that is too long or lacks Progressive Disclosure structure.
  Shrinks the body to under 100 lines by extracting detail into references/ files.
  Use when the user says "my skill is too long", "refactor my skill", "apply
  progressive disclosure to my skill", "slim down my SKILL.md", "/skill:refactor",
  or after /skill:check reports FAIL/WARN. Distinct from skill:check (audit only).
compatibility:
  tools: Read, Glob, Grep, Write, Edit, Bash
---

# SKILL.md Progressive Disclosure Refactoring Specialist

## Step 1: Analyze

Read the target SKILL.md completely. Also read `references/plan-and-report-templates.md`
now — you'll need it for both the plan (Step 2) and the completion report (Step 4).

Identify:

1. **Line count** — if already ≤ 100 lines with good Progressive Disclosure structure,
   tell the user the skill passes and stop here.
2. **Extractable content** — detail, not workflow:
   - Full output templates, report format blocks
   - Reference tables, configuration examples
   - Domain knowledge, long checklists, examples > 15 lines
3. **Workflow-only content** — phases, steps, decision logic → stays in SKILL.md
4. **Existing `references/`** — check with `test -d $(dirname <path>)/references/`; if exists, list contents

## Step 2: Build Refactoring Plan

Use the plan template from `references/plan-and-report-templates.md`.
Present the plan and wait for user confirmation before writing any files.

## Step 3: Execute

After confirmation:

**3a. Create `references/` files**
- Single-responsibility per file
- Header: `# <Topic> — <purpose>`
- Under 300 lines each

**3b. Rewrite SKILL.md**
- Keep frontmatter unchanged (fix only if frontmatter has issues)
- Replace extracted blocks with pointer lines:
  `Read references/<filename>.md when <trigger condition>.`
- Compress step descriptions to action-oriented one-liners
- Verify line count ≤ 100

**3c. Validate**
- SKILL.md ≤ 100 lines?
- All `references/` files triggered from SKILL.md?
- Output format still reachable?

## Step 4: Report

Use the completion report template from `references/plan-and-report-templates.md`
(already loaded in Step 1).

## Guiding Principle

SKILL.md = **control tower**: phases and pointers only.
`references/` = **knowledge base**: templates, examples, domain detail.
A user reading SKILL.md should understand the full workflow in 2 minutes.
