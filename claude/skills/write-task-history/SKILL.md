---
name: write-task-history
description: Write task history from current conversation to a daily task list file. Generates two copy-paste-ready formats: JIRA ticket (plain text with section symbols) and git PR description (markdown). Use this skill whenever the user wants to record, document, or summarize completed work from the current session. Also trigger when the user mentions task history, work log, JIRA ticket drafting from conversation context, or preparing PR descriptions based on what was just done. Works across any project.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# write-task-history

Document completed work from the current conversation into a daily task history file,
producing JIRA ticket and git PR formats that can be directly copy-pasted.

## When to use

- User says "/write-task-history" with optional description
- User asks to record, log, or summarize today's work
- User wants a JIRA ticket or PR description based on work just completed

## Step-by-step workflow

### Step 1: Determine output file path

Resolve the storage directory and today's filename:

```
directory = $TASK_HISTORY_DIR or ~/para/archive/playbook/docs/task-history/
filename  = YYYY-MM-DD-task-list.md  (e.g. 2026-03-20-task-list.md)
```

Run `mkdir -p` on the directory if it does not exist.

### Step 2: Analyze the current conversation

Review the full conversation to extract:

- **What was done**: list of concrete actions and changes
- **Why it was done**: background, motivation, or triggering event
- **What resulted**: outcomes, files created, PRs merged, issues resolved

If the user provided a description argument, use it as additional context but still
analyze the conversation for completeness.

### Step 3: Gather git information (if in a git repo)

Run these commands to collect context:

```bash
# Project name from remote
basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null

# Commits made during this conversation (look for hashes mentioned in conversation)
git log --oneline -10

# Current branch and diff scope (if not on main)
git branch --show-current
git diff main...HEAD --stat 2>/dev/null
```

Use the conversation context to identify which commits were made during this session,
not just today's commits. This avoids false positives from unrelated commits.

### Step 4: Generate JIRA ticket format

Write inside a `text` code block. Use `>` for section headers and `-` for items.
Do not use markdown formatting, emoji, or special characters beyond `>` and `-`.
The content should be directly pasteable into a JIRA Description field.

**Template:**

```text
[Title]
[project-name] Concise summary of work

[Description]
> Background
- Why this work was needed
- Context or triggering event

> Work performed
- Specific action 1
- Specific action 2
- Specific action 3

> Results
- Outcome 1
- Outcome 2

> Notes
- Additional context if relevant
```

Omit the "Notes" section if there is nothing noteworthy.

### Step 5: Generate PR format (only if commits exist)

Only produce this section if the conversation included git commits, branch creation,
or PR activity. If no commits were made, skip entirely — do not write an empty section
or a placeholder.

Write inside a `markdown` code block. Use plain section headers without emoji.

**Template:**

```markdown
## Title
Short PR title (under 70 characters)

## Summary
- Change description 1
- Change description 2

## Changes
- `file-or-path`: what changed
- `file-or-path`: what changed

## Test plan
- [ ] Verification step 1
- [ ] Verification step 2
```

### Step 6: Write to file

Check if the target file already exists:

- **File does not exist**: Create it with a level-1 heading, then the entry.
- **File exists**: Append a `---` separator followed by the new entry.

Each entry uses this structure:

```markdown
## HH:MM | project-name | Short task title

### JIRA Ticket

\`\`\`text
(JIRA content here)
\`\`\`

### PR

\`\`\`markdown
(PR content here — or omit this entire section if no commits)
\`\`\`
```

The timestamp is the current time when the skill runs (24-hour format).

### Step 7: Auto-commit to the task-history repository

After writing the file, automatically commit it in the repository where the file lives.
The task-history file may be in a different repository than the current working directory.

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

### Step 8: Confirm to user

After writing and committing, tell the user:
- The file path that was written to
- The commit hash and message
- Whether a PR section was included or skipped

## Important rules

- Never use emoji in any output (repo convention)
- JIRA format uses only `>` and `-` symbols for structure, no markdown
- PR section is conditional: only when commits exist in conversation context
- Always append, never overwrite existing file content
- The `text` and `markdown` code blocks are essential for copy-paste workflow
- Determine project name from `git remote`, falling back to directory name, then "N/A"
- Write content in the same language the user used during the conversation

## Example

Given a conversation where the user fixed a bug and committed:

File: `~/para/archive/playbook/docs/task-history/2026-03-20-task-list.md`

```markdown
# Task History: 2026-03-20

---

## 14:30 | dotfiles | Fix symlink creation for pip config

### JIRA Ticket

\`\`\`text
[Title]
[dotfiles] pip config symlink 생성 오류 수정

[Description]
> 배경
- setup.sh 실행 시 ~/.config/pip/pip.conf symlink가 생성되지 않는 문제 발견
- 디렉터리 미존재가 원인

> 수행 내용
- shell-common/setup.sh에서 mkdir -p 호출 추가
- pip config symlink 생성 로직 수정
- 테스트 후 PR 생성

> 결과
- setup.sh 실행 시 pip config 정상 생성 확인
- PR #33 생성 및 머지 완료
\`\`\`

### PR

\`\`\`markdown
## Title
fix: add mkdir for pip config directory before symlink creation

## Summary
- Add `mkdir -p ~/.config/pip` before creating pip.conf symlink
- Fixes setup.sh failure on fresh installations where ~/.config/pip does not exist

## Changes
- `shell-common/setup.sh`: Added directory creation before symlink

## Test plan
- [ ] Run setup.sh on clean home directory
- [ ] Verify ~/.config/pip/pip.conf symlink exists after setup
\`\`\`
```
