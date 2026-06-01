---
name: claude-plugin:structure-check
description: >-
  Audit a claude-plugin marketplace repo (e.g. `claude-plugin-visuals`)
  against the standard directory layout and report PASS/WARN/FAIL/N/A.
  Read-only — never edits. Discovers plugins/skills dynamically by directory
  scan, then evaluates mandatory items M1-M6 (FAIL) and recommended items
  R1-R5 (WARN). Use when the user says "check my claude-plugin repo
  structure", "is this marketplace repo standard?", "audit plugin layout",
  "/claude-plugin:structure-check". Sister skill of
  `claude-plugin:structure-refactor` (which fixes what this finds). Do NOT
  use for SKILL.md content quality (use `skill:check`) or shell scripts
  (use `sh:check`).
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

## Step 1: Resolve Repo Path

- Argument given → audit that path. No argument → audit the current
  directory.
- Confirm the path exists; if not, stop with a one-line error pointing to
  `/claude-plugin:structure-check path/to/repo`.
- Check `test -d <path>/.git`; not a git repo → continue, but note it
  (one warning line — the audit still runs).

## Step 2: Discover Plugins + Skills

Read `references/structure-spec.md` for the full standard (it is the
embedded SSOT). Discover dynamically — never hard-code names:

1. `plugins/*/` → each directory is a plugin.
2. `plugins/<p>/skills/*/` → each directory is a skill of that plugin.

Record the plugin and skill lists for the report header and for the
per-skill recommended checks (R1/R2/R5).

## Step 3: Evaluate M1-M6 and R1-R5

For each item in `references/structure-spec.md`, assign exactly one of:

- **PASS** — present and valid.
- **WARN** — recommended item missing/violated (R1-R5 only).
- **FAIL** — mandatory item missing/invalid (M1-M6 only).
- **N/A** — the subject does not exist (e.g. a plugin with 0 skills → its
  R1/R2 are N/A, not FAIL).

JSON validity (M1, M3): parse with `python3 -m json.tool` (or `jq`); a
parse error is FAIL, not WARN. Frontmatter validity (M4): the SKILL.md must
have both `name:` and `description:` keys. R3/R4/R5 use the heuristics
defined in the spec. R5: for each discovered skill `<s>`, grep `README.md`
for both a `skill-guides/<s>.html` and a `skill-output/<s>-usage.{html,md}`
path string (relative or Pages-absolute) — missing either → WARN; no skills
→ N/A.

## Step 4: Output the Report

Read `references/report-template.md` for the exact format. The report has a
header line (path + discovered plugins/skills), a `[필수]` block (M1-M6) and
a `[권장]` block (R1-R5), then the summary verdict:

- any FAIL → **FAIL**
- no FAIL but ≥1 WARN → **WARN**
- all PASS/N/A → **PASS**

Emit the next-action hint **only when** there is ≥1 FAIL or WARN.

## Constraints

- Read-only — never create, move, or edit any file. Fixing is
  `claude-plugin:structure-refactor`'s job.
- N/A is not FAIL — a missing *subject* (no skills, no plugins beyond M2)
  yields N/A for dependent checks.
- Do not audit SKILL.md *content* (that is `skill:check`) or shell script
  quality (that is `sh:check`) — only the directory structure.
- Repo-agnostic: discover plugins/skills by scan; the spec is embedded, not
  read from the target repo.
