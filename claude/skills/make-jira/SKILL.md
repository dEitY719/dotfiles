---
name: make-jira
description: >-
  Generate comprehensive weekly Jira reports from work logs.
---

# make-jira

## Invocation

```bash
# Generate current week's report
/make-jira

# Generate specific week
/make-jira --week 2026-W05

# Generate report for specific Jira key only
/make-jira SWINNOTEAM-906
```

## What It Does

1. **Parses work log** (`~/work_log.txt`) for current week's entries
2. **Groups by Jira key** and calculates total hours per key
3. **Fetches commit details** from git log using commit hashes
4. **Aggregates results** with metrics and summaries
5. **Generates report** in Jira-ready markdown format
6. **Saves output** to `rca-knowledge/docs/jira-records/YYYY-W##-report.md`

## Output Format

```markdown
[주간보고] 2026-W05 (2026-01-26 ~ 2026-02-01)

요약
- Main achievement with metric
- Secondary achievement

완료 (Done)
- SWINNOTEAM-906: Feature Title
  * Specific accomplishment 1
  * Specific accomplishment 2

Work Log
- SWINNOTEAM-906: 4.5h (Testing)
- SWINNOTEAM-903: 2.5h (Communication)
- Total: 7.0h
```

## Input Data

- **Primary**: `~/work_log.txt` (work log entries with timestamps, Jira keys, hours)
- **Secondary**: `git log` output (commit messages for context)
- **Optional**: `.claude/skills/make-jira/templates/` (customization)

## Success Criteria

✓ Parses all entries from current week
✓ Groups by Jira key correctly
✓ Calculates time totals accurately
✓ Generates valid markdown output
✓ Saves to correct location with proper naming
