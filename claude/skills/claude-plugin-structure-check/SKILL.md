---
name: claude-plugin:structure-check
description: >-
  Audit a claude-plugin marketplace repo (e.g. `claude-plugin-visuals`)
  against the standard directory layout and report PASS/WARN/FAIL/N/A.
  Supports both `mono` (`plugins/<p>/skills/`) and `single`
  (repo-root `skills/`) layouts — auto-detected, or forced with
  `--single` / `--mono`. Read-only — never edits. Discovers plugins/skills
  dynamically by directory scan, then evaluates mandatory items M1-M9 (FAIL,
  incl. M7-M9 marketplace `plugins[].source` install-integrity) and recommended
  items R1-R8 (WARN). Use when the user says "check my
  claude-plugin repo structure", "is this marketplace repo standard?",
  "audit plugin layout", "/claude-plugin:structure-check". Sister skills:
  `claude-plugin:structure-refactor` (fixes what this finds),
  `claude-plugin:rename-repo` (renames the repo to the team convention).
  Do NOT use for SKILL.md content quality (use `skill:check`) or shell
  scripts (use `sh:check`).
compatibility:
  tools: Read, Glob, Grep, Bash
metadata:
  model_recommendation:
    tier: haiku
    reason: "read-only directory-structure audit; dynamic scan + JSON/frontmatter validation; bounded PASS/WARN/FAIL report"
    claude: prefer
    non_claude: advisory-only
---

# claude-plugin Structure Auditor

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No filesystem scan.

## Step 1: Parse Args + Resolve Repo Path

- Positional `[repo-path]` → audit that path. None → audit the current
  directory.
- Flags `--single` / `--mono` → force the layout mode, overriding
  auto-detection (Step 2). Mutually exclusive; if both given, last wins.
- Confirm the path exists; if not, stop with a one-line error pointing to
  `/claude-plugin:structure-check path/to/repo`.
- Check `test -d <path>/.git`; not a git repo → continue, but note it
  (one warning line — the audit still runs).

## Step 2: Detect Mode + Discover Plugin Roots + Skills

Read `references/structure-spec.md` for the full standard (embedded SSOT) —
see "Layout modes", "Mode detection", and "Mandatory items by mode".

For detailed evaluation rules and mode/type classification logic: see [references/evaluation-rules.md](references/evaluation-rules.md)

Record the detected mode, plugin-root list, and skill list for the report
header and the per-skill recommended checks (R1/R2/R5).

## Step 3: Evaluate M1-M9 and R1-R8

Apply PASS/WARN/FAIL/N/A to each item per the scoring rules in
[references/evaluation-rules.md](references/evaluation-rules.md).

## Step 4: Output the Report

Read `references/report-template.md` for the exact format. The report has a
header line (path + detected mode + discovered plugins/skills), a `[필수]`
block (M1-M9) and a `[권장]` block (R1-R8), then the summary verdict:

- any FAIL → **FAIL**
- no FAIL but ≥1 WARN → **WARN**
- all PASS/N/A → **PASS**

Emit the next-action hint **only when** there is ≥1 FAIL or WARN. Always append
the "structure-check PASS ≠ install/runtime 성공" disclaimer (report-template.md
→ "Install/runtime disclaimer", #1084).

## Constraints

- Read-only — never create, move, or edit any file. Fixing is
  `claude-plugin:structure-refactor`'s job.
- N/A is not FAIL — a missing *subject* (no skills, no plugins beyond M2)
  yields N/A for dependent checks.
- Do not audit SKILL.md *content* (that is `skill:check`) or shell script
  quality (that is `sh:check`) — only the directory structure.
- Repo-agnostic: detect mode + discover plugin roots/skills by scan; the
  spec is embedded, not read from the target repo. A `--single`/`--mono`
  override means "score by *that* mode" — a wrong override surfaces as a
  normal M2 FAIL, never a silent skip.
