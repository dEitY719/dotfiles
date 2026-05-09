/skill:check — Audit a SKILL.md for structure and UX quality

Usage:
  /skill:check [path/to/SKILL.md]

Arguments:
  [path]    Path to the SKILL.md file to audit (optional)
            If omitted, searches for SKILL.md from the current directory

Examples:
  /skill:check
  /skill:check claude/skills/my-skill/SKILL.md
  /skill:check help

Options:
  help    Show this message

Checks run (10 total):
  Structure (1-5):   Line Count, Progressive Disclosure, Frontmatter Validity,
                     References Directory Usage, Output Report Defined
  UX Quality (6-10): Help Flag Pattern, Step Structure, Options Documentation,
                     Verdict Output, Next-action Hint
