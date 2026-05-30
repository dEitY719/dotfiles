/claude-plugin:structure-check — Audit a claude-plugin marketplace repo's structure

Usage:
  /claude-plugin:structure-check [repo-path]
  /claude-plugin:structure-check help

Arguments:
  [repo-path]   Path to the claude-plugin repo to audit (optional).
                Defaults to the current directory.

What it checks (read-only — never edits):

  Mandatory (M1-M6 — missing → FAIL)
    M1  .claude-plugin/marketplace.json        exists + valid JSON
    M2  plugins/ with >=1 plugin               at least one plugin
    M3  plugins/<p>/.claude-plugin/plugin.json exists + valid JSON
    M4  plugins/<p>/skills/<s>/SKILL.md        exists + name/description
    M5  docs/skill-guides/ + docs/skill-output/ both directories exist
    M6  README.md                              exists

  Recommended (R1-R4 — missing → WARN)
    R1  docs/skill-guides/<skill>.html         per-skill guide
    R2  docs/skill-output/<skill>-usage.{html,md}  per-skill usage sample
    R3  README is "Simple"                     links into docs/, not too long
    R4  naming consistency                     name: colon ↔ directory hyphen

Each item reports PASS / WARN / FAIL / N/A. N/A means the subject does not
exist (e.g. a plugin with 0 skills → R1/R2 are N/A).

Verdict:
  any FAIL → FAIL ; no FAIL but >=1 WARN → WARN ; all PASS/N/A → PASS

Examples:
  /claude-plugin:structure-check
  /claude-plugin:structure-check ../claude-plugin-visuals
  /claude-plugin:structure-check help

Sister skill:
  /claude-plugin:structure-refactor   — fix the structure this audit reports
                                         (dry-run by default, --apply to write)

Not this skill:
  /skill:check   — audit a SKILL.md's content quality (Progressive Disclosure)
  /sh:check      — audit a shell script's quality
