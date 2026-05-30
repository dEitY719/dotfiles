# Auto-commit and Confirm — Steps 7-8

## Step 7: Auto-commit to the task-history repository

After writing the file, automatically commit it in the repository where the file
lives. The task-history file may be in a different repository than the current
working directory.

Commit format (fixed pattern):

```
chore(task-history): YYYY-MM-DD short task summary
```

Example:

```
chore(task-history): 2026-03-20 write-task-history skill design
```

Steps:

```bash
cd <directory-containing-the-task-history-file>
git add <task-history-file>
git commit -m "chore(task-history): YYYY-MM-DD short task summary"
```

This commit is low-importance and does not require review, so commit directly
without asking the user for confirmation.

## Step 8: Confirm to user

After writing and committing, report the verdict:

```
[OK] write:task-history — entry appended
  path: <task-history-file>
  time: HH:MM
  project: <project-name>
  pr_section: included | skipped
  commit: <hash> chore(task-history): YYYY-MM-DD <summary>

Next: paste JIRA block into ticket / open PR with the markdown block
```
