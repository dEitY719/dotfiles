---
name: ux-guidelines
description: >-
  Apply UX_GUIDELINES.md standards to shell functions and help text. Use when
  refactoring help functions, creating new help commands, or ensuring consistent
  formatting with semantic UX functions (ux_header, ux_section, ux_bullet, etc).
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# UX Guidelines Skill

## Help

If the argument is `help`, read `references/help.md` and output it verbatim, then stop.

## Objective

Enforce `shell-common/tools/ux_lib/UX_GUIDELINES.md` for user-facing shell output.
Keep implementations semantic (`ux_*`), readable, and cross-shell compatible.

Read `references/ux-foundation.md` for principles, color semantics, and UX function
selection rules.

## Mode Selection

Choose one mode before editing:

1. **Individual function refactoring**: a specific function/module is requested.
2. **Bulk compliance review**: user asks to scan `shell-common/**/*.sh` and write
   findings to `docs/abc-review-*.md`.

## Mode A: Individual Function Refactoring

Read `references/refactoring-playbook.md` when executing this mode.

1. Read the target module and locate hardcoded output patterns.
2. Build a section map: header, grouped commands, procedures, warnings, tips.
3. Ensure `ux_lib` is loaded with the approved conditional pattern.
4. Replace hardcoded output (`cat <<EOF`, ANSI codes, raw status strings) with
   semantic UX functions.
5. Keep command behavior unchanged; refactor presentation only unless user asked
   for behavior changes.
6. Validate in both bash and zsh; run targeted help function checks.
7. Report changes with file paths, key replacements, and validation results.

## Mode B: Bulk UX Compliance Review

Read `references/bulk-review-workflow.md` when executing this mode.

1. Discover `shell-common/**/*.sh` files in scope.
2. Analyze each file for UX guideline violations and exclusions.
3. Categorize findings by severity (`high`, `medium`, `low`).
4. Write the report to the requested file (`docs/abc-review-C.md`,
   `docs/abc-review-CX.md`, or `docs/abc-review-G.md`).
5. Include concrete file/line evidence and suggested fixes.
6. Do not commit unless explicitly requested.

## Output Requirements

Always include:

1. Mode used (`individual` or `bulk`).
2. Files inspected and files changed.
3. Validation commands run and outcomes.
4. Remaining risks or follow-up items, if any.
