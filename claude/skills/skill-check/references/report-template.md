# Report Template

Use this exact format when outputting the audit report.

```
## SKILL.md Audit Report
File: <path>
Lines: <count>
References dir: <exists / missing>

| # | Check                        | Result | Notes                           |
|---|------------------------------|--------|---------------------------------|
| 1 | Line Count                   | PASS   | 87 lines — within 100-line goal |
| 2 | Progressive Disclosure       | WARN   | templates inline, not in refs/  |
| 3 | Frontmatter Validity         | PASS   | name, description valid         |
| 4 | References Directory Usage   | FAIL   | no references/ directory        |
| 5 | Output Report Defined        | PASS   | template in Step 3              |

Score: X/5 checks passed (Y warnings)

## Issues & Improvements

### FAIL: Check N — <Name>
**Problem:** <quote specific lines from the file>
**How to fix:** <concrete suggestion with example>

### WARN: Check N — <Name>
**Problem:** <specific issue>
**How to fix:** <concrete suggestion>

## Summary
<2–3 sentences: overall quality, most critical fix, ready for /skill-refactor?>
```

Rules:
- Only include WARN and FAIL items in Issues section
- Quote actual lines from the file when describing problems
- If score < 4/5, end Summary with: "Run /skill-refactor to fix structural issues."
