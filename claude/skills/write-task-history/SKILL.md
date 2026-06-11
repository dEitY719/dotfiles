---
name: write:task-history
description: >-
  오늘 한 작업을 JIRA 티켓 + PR 설명 형식으로 daily log에 기록. Write task
  history from current conversation to a daily task list file. Generates two
  copy-paste-ready formats: JIRA ticket (plain text with section symbols) and
  git PR description (markdown). Use this skill whenever the user wants to
  record, document, or summarize completed work from the current session. Also
  trigger when the user mentions task history, work log, JIRA ticket drafting
  from conversation context, or preparing PR descriptions based on what was
  just done. Works across any project. (재사용 패턴 문서화는 write:insight,
  장애 분석은 write:rca)
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "simple session summary: conversation mining -> JIRA + PR templates -> append file + auto-commit; bounded structured output"
    claude: prefer
    non_claude: advisory-only
---

# write-task-history

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

Document completed work from the current conversation into a daily task history file,
producing copy-pasteable JIRA ticket and git PR formats.

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `<description>` | Free-text extra context | none — mine the conversation |
| `-h` / `--help` / `help` | Print `references/help.md` verbatim and stop. | — |

Env: `TASK_HISTORY_DIR` (default `~/para/archive/playbook/docs/task-history/`)

## Step-by-step workflow

Steps 1–8 are sequential — if Step 1 cannot resolve a writable directory, or Step 7
commit fails, stop and report rather than producing a partial entry.

### Step 1: Determine output file path

Resolve the storage directory and today's filename:

```
directory = $TASK_HISTORY_DIR or ~/para/archive/playbook/docs/task-history/
filename  = YYYY-MM-DD-task-list.md  (e.g. 2026-03-20-task-list.md)
```

Run `mkdir -p` on the directory if it does not exist.

### Step 2: Analyze the current conversation

Extract **what was done** (concrete actions/changes), **why** (background, trigger),
and **what resulted** (outcomes, files, PRs, issues). Use any description argument as
extra context, but still analyze the conversation for completeness.

### Step 3: Gather git information (if in a git repo)

Collect project name (`basename "$(git remote get-url origin)" .git`), recent commits
(`git log --oneline -10`), current branch, and diff scope (`git diff main...HEAD
--stat`). Use the conversation to identify this session's commits, not just today's.

### Step 4: Generate JIRA ticket format

Read `references/jira-template.md` for the JIRA Description-pasteable text block.

### Step 5: Generate PR format (conditional)

Read `references/pr-template.md` for the markdown PR template. Skip entirely if no
commits exist in the conversation.

### Step 6: Write to file

Read `references/file-entry-structure.md` for the append/create + separator policy
and per-entry structure.

### Step 7–8: Auto-commit + confirm

Read `references/commit-confirm.md` for the commit pattern and final verdict block.

## Rules and Example

Read `references/rules.md` for output conventions (emoji-free, append-only, language).
Read `references/example.md` for a full worked entry.

## Final Output

```
[OK] write:task-history — entry appended
  path: <task-history-file>
  time: HH:MM
  project: <project-name>
  pr_section: included | skipped
  commit: <hash> chore(task-history): YYYY-MM-DD <summary>

Next: paste JIRA block into ticket / open PR with the markdown block
```
