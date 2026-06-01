/claude-plugin:structure-check — Audit a claude-plugin marketplace repo's structure

Usage:
  /claude-plugin:structure-check [repo-path] [--single | --mono]
  /claude-plugin:structure-check help

Arguments:
  [repo-path]   Path to the claude-plugin repo to audit (optional).
                Defaults to the current directory.

Options:
  --single      Force the single layout (repo itself is one plugin;
                marketplace source "./", skills at root skills/<s>/).
  --mono        Force the mono layout (repo bundles many plugins;
                source "./plugins/<name>", skills at plugins/<p>/skills/<s>/).
                --single / --mono override auto-detection (last one wins).

Layout modes & auto-detection:
  Without a flag the mode is detected in priority order:
    1. --single / --mono flag (if given)
    2. marketplace.json plugins[].source  ("./" => single, "./plugins/.." => mono)
    3. filesystem fallback  (plugins/*/ => mono ; root plugin.json => single)
    4. still ambiguous => defaults to mono, header marks "(추정)"
  The detected mode is printed in the report header.

What it checks (read-only — never edits; paths shown for mono | single):

  Mandatory (M1-M6 — missing → FAIL)
    M1  .claude-plugin/marketplace.json        exists + valid JSON
    M2  >=1 plugin root                         plugins/<p>/ | root plugin.json
    M3  plugin.json valid                       plugins/<p>/.claude-plugin/ | root .claude-plugin/
    M4  SKILL.md valid                          plugins/<p>/skills/<s>/ | skills/<s>/
    M5  docs/skill-guides/ + docs/skill-output/ both directories exist
    M6  README.md                              exists

  Recommended (R1-R5 — missing → WARN)
    R1  docs/skill-guides/<skill>.html         per-skill guide
    R2  docs/skill-output/<skill>-usage.{html,md}  per-skill usage sample
    R3  README is "Simple"                     links into docs/, not too long
    R4  naming consistency                     name: colon ↔ directory hyphen
    R5  per-skill README guide+usage links     README links both for each skill

M5/M6 and R1-R5 are mode-independent — only the M2/M3/M4 check paths and
skill discovery differ between modes. Each item reports PASS / WARN / FAIL /
N/A. N/A means the subject does not exist (e.g. a plugin with 0 skills →
R1/R2/R5 are N/A).

Verdict:
  any FAIL → FAIL ; no FAIL but >=1 WARN → WARN ; all PASS/N/A → PASS

Examples:
  /claude-plugin:structure-check
  /claude-plugin:structure-check ../claude-plugin-visuals
  /claude-plugin:structure-check ../superpowers --single
  /claude-plugin:structure-check . --mono
  /claude-plugin:structure-check help

Sister skill:
  /claude-plugin:structure-refactor   — fix the structure this audit reports
                                         (dry-run by default, --apply to write)

Not this skill:
  /skill:check   — audit a SKILL.md's content quality (Progressive Disclosure)
  /sh:check      — audit a shell script's quality
