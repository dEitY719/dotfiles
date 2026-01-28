# make-jira Skill

Generate comprehensive weekly Jira reports from work log entries.

## Quick Start

```bash
# Generate current week's report
/make-jira

# Generate specific week
/make-jira --week 2026-W05

# Generate for specific Jira key
/make-jira SWINNOTEAM-906
```

## How It Works

1. **Parses work_log.txt** containing both:
   - Auto-generated post-commit entries: `[date time] [KEY] | main | hours | source`
   - Manual work-log entries: `[date time] [KEY] | type | category | hours | source`

2. **Filters by week** using ISO calendar (Monday-Sunday)

3. **Groups by Jira key** and aggregates hours

4. **Generates markdown report** at:
   `rca-knowledge/docs/jira-records/YYYY-W##-report.md`

## Implementation Details

**Tool**: `/home/bwyoon/dotfiles/shell-common/tools/custom/make_jira.sh`

**Supported Operations**:
- Current week: `make_jira.sh` (detects current week automatically)
- Specific week: `make_jira.sh 2026-W05`
- Filter by key: `make_jira.sh 2026-W05 SWINNOTEAM-906`

**Output Format**:
```markdown
# [주간보고] 2026-W05 (2026-01-26 ~ 2026-02-01)

## 요약
- Total entries and hours
- Jira task count

## 완료 (Done)
- **JIRA-KEY**: Xh (category)

## Work Log 요약
- JIRA-KEY: Xh

**총 투입**: Xh
**생성**: YYYY-MM-DD HH:MM:SS
```

## Requirements

- `work_log.txt` (either `~/work_log.txt` or `~/dotfiles/work/log/work_log.txt`)
- `rca-knowledge/docs/jira-records/` directory (auto-created)
- GNU `date` command for week calculations

## Next Steps

- Integration with `/make-confluence` for technical documentation generation
- LLM-based summarization of achievements
- Automated index updates in `rca-knowledge/_index.json`
