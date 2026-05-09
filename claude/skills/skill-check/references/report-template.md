# Report Template

Use this exact format when outputting the audit report.

```
## SKILL.md Audit Report
File: <path>
Lines: <count>
References dir: <exists / missing>

### Structure Checks
| # | Check                        | Result | Notes                           |
|---|------------------------------|--------|---------------------------------|
| 1 | Line Count                   | PASS   | 42 lines — within 100-line goal |
| 2 | Progressive Disclosure       | WARN   | templates inline, not in refs/  |
| 3 | Frontmatter Validity         | PASS   | name, description valid         |
| 4 | References Directory Usage   | FAIL   | no references/ directory        |
| 5 | Output Report Defined        | PASS   | template in Step 3              |

### UX Quality Checks
| # | Check                        | Result | Notes                                 |
|---|------------------------------|--------|---------------------------------------|
| 6 | Help Flag Pattern            | PASS   | -h/--help → references/help.md        |
| 7 | Step Structure               | WARN   | steps present but no stop-on-error    |
| 8 | Options Documentation        | N/A    | skill takes no arguments              |
| 9 | Verdict Output               | FAIL   | output ends without [OK]/[FAIL]       |
|10 | Next-action Hint             | PASS   | teardown shown in success report      |

Score: 5/9 checks passed (2 warnings, 2 fails, 1 N/A)
Verdict: POOR — significant gaps, major rework needed

## Issues & Improvements

### FAIL: Check N — <Name>
**Problem:** <quote specific lines from the file>
**How to fix:** <concrete suggestion with example>

### WARN: Check N — <Name>
**Problem:** <specific issue>
**How to fix:** <concrete suggestion>

## Next Actions
1. <highest priority fix>
2. <next fix>
Run /skill:check again after fixes to verify.
```

Rules:
- Only include WARN and FAIL items in Issues & Improvements section
- Quote actual lines from the file when describing problems
- Score denominator excludes N/A checks
- Verdict labels:
  - All applicable checks PASS → `EXCELLENT — gold standard`
  - ≥80% PASS, no FAIL → `GOOD — production-ready, minor polish needed`
  - ≥60% PASS or any FAIL → `NEEDS WORK — fix FAIL items before shipping`
  - <60% PASS → `POOR — significant gaps, major rework needed`
- Always end with "Next Actions" section listing concrete fixes in priority order
