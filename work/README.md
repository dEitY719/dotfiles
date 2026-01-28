# Work Management System

Work-related data and logs for productivity tracking and reporting.

## Directory Structure

```
work/
└── log/
    └── work_log.txt          # Main work activity log
```

## Files

### `log/work_log.txt`

**Purpose**: Central work activity log tracking both development and non-development work.

**Format**:
```
[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | hours | source
  └─ Category: CategoryName
```

**Sources**:
- **Automatic**: Post-commit hook (development work)
- **Manual**: `work-log` CLI (coordination, meetings, assessments)

**Symlink**: `~/work_log.txt` → `~/dotfiles/work/log/work_log.txt`

## Related Tools

### Commands
- `work-log add` - Manually log work activities
- `work-log list` - View recent entries
- `make-jira` - Generate weekly Jira reports
- `make-confluence` - Transform docs to Confluence guides
- `work-help` - Show work system overview

### Implementation Files
- **CLI Tools**: `shell-common/tools/custom/work_log.sh`
- **Aliases**: `shell-common/aliases/work-aliases.sh`
- **Functions**: `shell-common/functions/work.sh`
- **Skills**: `claude/skills/make-jira/`, `claude/skills/make-confluence/`
- **Hooks**: `git/hooks/post-commit`

## Output Locations

- **Jira Reports**: `~/para/archive/rca-knowledge/docs/jira-records/`
- **Confluence Guides**: `~/para/archive/rca-knowledge/docs/confluence-guides/`

## Setup

Symlink is automatically created by `bash/setup.sh`:
```bash
ln -sf ~/dotfiles/work/log/work_log.txt ~/work_log.txt
```

## Usage Examples

```bash
# Log manual work
work-log add SWINNOTEAM-906 -t coordination -c Communication -T 2.5h

# View recent entries
work-log list --count 10

# Generate weekly report
make-jira

# Transform documentation
make-confluence docs/technic/parallel-testing.md
```

---

*Work Management System v1.0*
*Last Updated: 2026-01-28*
