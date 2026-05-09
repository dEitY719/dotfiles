# Skill Quality Checks

Ten checks, each rated PASS / WARN / FAIL / N/A.

---

## Structure Checks (1–5)

### Check 1: Line Count
PASS ≤ 100 | WARN 101–150 | FAIL > 150
Every line over 100 is a candidate for `references/` extraction.

### Check 2: Progressive Disclosure Structure
PASS — workflow phases only in SKILL.md; detail in `references/`
WARN — mostly workflow but some templates/tables inline
FAIL — large reference content embedded directly in SKILL.md

### Check 3: Frontmatter Validity
Look for: `name` present, `description` present, only known attributes present.
Known attributes: `name`, `description`, `allowed-tools`, `compatibility`,
`metadata`, `user-invocable`, `argument-hint`, `disable-model-invocation`, `license`.
**Naming**: read `references/naming-convention.md` — `category:action` colon
form is the SSOT convention and reports as PASS, not WARN. Folder/name
kebab-vs-colon mismatch is also PASS when folder is the kebab form of the
colon name (e.g., `name: gh:pr` + folder `gh-pr/`).
PASS — valid | WARN — minor issues | FAIL — missing fields or unknown attributes

### Check 4: References Directory Usage
PASS — `references/` exists with focused files, each referenced from SKILL.md
WARN — `references/` exists but not clearly triggered from SKILL.md body
FAIL — SKILL.md > 100 lines AND no `references/` directory

### Check 5: Output Report Defined
PASS — output format with example clearly defined
WARN — output described but vague
FAIL — no output format defined

---

## UX Quality Checks (6–10)

### Check 6: Help Flag Pattern
PASS — `-h`/`--help`/`help` arg → reads `references/help.md` verbatim, then stops. No API calls.
WARN — help exists but inline (not in `references/help.md`) or not verbatim
FAIL — no `-h`/`--help`/`help` support at all

### Check 7: Step Structure
PASS — execution steps numbered (Step 1, Step 2, …) with explicit stop-on-error policy
WARN — steps described but unnumbered, or no stop-on-error policy stated
FAIL — no clear execution flow
N/A — skill is a single read-only lookup (no multi-step execution)

### Check 8: Options Documentation
PASS — all accepted options in a table: Option | Description | Default
WARN — options listed but missing defaults or described in prose only
FAIL — options accepted but not documented
N/A — skill takes no arguments or options

### Check 9: Verdict Output
PASS — final output has explicit `[OK]`/`[FAIL]` verdict + structured key-value pairs
WARN — success/failure indicated but unstructured (plain prose)
FAIL — no explicit verdict in output
N/A — skill is purely informational (no action outcome to report)

### Check 10: Next-action Hint
PASS — success report includes next steps, follow-up commands, or teardown
WARN — partial guidance (mentions what comes next but no concrete commands)
FAIL — output ends without any guidance on what to do next
N/A — skill is terminal (no natural follow-up action exists)
