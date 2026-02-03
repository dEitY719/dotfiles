# Work Management System

Work-related data and logs for productivity tracking and reporting.

## Directory Structure

The work log is now managed as a symlink:

```
~/work_log.txt → ~/para/archive/playbook/logs/work_log.txt
```

All work data is centralized in the playbook directory for better organization and version control.

## Files

### `work_log.txt`

**Location**: `~/para/archive/playbook/logs/work_log.txt`

**Symlink**: `~/work_log.txt` → `~/para/archive/playbook/logs/work_log.txt`

**Purpose**: Central work activity log tracking both development and non-development work.

**Format**:
```
[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | hours | source
  └─ Category: CategoryName
```

**Sources**:
- **Automatic**: Post-commit hook (development work)
- **Manual**: `work-log` CLI (coordination, meetings, assessments)

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

- **Work Log**: `~/para/archive/playbook/logs/work_log.txt`
- **Jira Reports**: `~/para/archive/playbook/docs/jira-records/`
- **Confluence Guides**: `~/para/archive/playbook/docs/confluence-guides/`

## Setup

Symlink is managed by the centralized symlink manager:
```bash
# Initialize all symlinks
symlink-init

# Check symlink status
symlink-check

# Or manually:
ln -sf ~/para/archive/playbook/logs/work_log.txt ~/work_log.txt
```

See `shell-common/config/symlinks.conf` for SSOT configuration.

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
