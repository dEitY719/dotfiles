/skill:check — Audit a SKILL.md for structure and UX quality

Usage:
  /skill:check [path/to/SKILL.md] [--recursive]

Arguments:
  [path]    Path to the SKILL.md file to audit (optional)
            If omitted, searches for SKILL.md from the current directory

Options:
  --recursive   For composite skills, traverse the Sub-skill Model Plan deeper
                than the default 1-depth (Check 12). Off by default.
  help          Show this message

Examples:
  /skill:check
  /skill:check claude/skills/my-skill/SKILL.md
  /skill:check claude/skills/gh-issue-flow/SKILL.md --recursive
  /skill:check help

Checks run (12 total):
  Structure (1-5):    Line Count, Progressive Disclosure, Frontmatter Validity,
                      References Directory Usage, Output Report Defined
  UX Quality (6-11):  Help Flag Pattern, Step Structure, Options Documentation,
                      Verdict Output, Next-action Hint, No Emojis
  Model (12):         Model Recommendation Metadata (read-only tier advice;
                      rubric: references/model-recommendation.md)
