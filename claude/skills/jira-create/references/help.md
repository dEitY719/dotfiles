# jira:create Help

Create Jira tickets through the jiravis CLI.

## Prerequisites

- Python 3.10+
- jiravis CLI installed as `jira`
- `jira` available on `PATH`
- jiravis authentication and config already set up

## Usage

```text
/jira:create
/jira:create help
/jira:create -h
/jira:create --help
/jira:create project JIRAVIS summary "Build adapter" description "Details..."
/jira-create JIRAVIS "Build adapter" "Details..."
```

Wrapper script help:

```bash
python claude/skills/jira-create/scripts/create_ticket.py help
python claude/skills/jira-create/scripts/create_ticket.py -h
python claude/skills/jira-create/scripts/create_ticket.py --help
```

## Required Inputs

| Field | Description |
|---|---|
| project key | Jira project key, for example `JIRAVIS` |
| summary | Jira issue summary |
| description | Jira issue description |

## Optional Inputs

| Field | Default | Description |
|---|---|---|
| issue type | `Task` | `Task`, `Bug`, or `Story` |
| priority | `Medium` | `Critical`, `High`, `Medium`, or `Low` |
| assignee | unset | Passed through to jiravis |
| labels | unset | Comma-separated labels |
| components | unset | Comma-separated components |
| due date | unset | `YYYY-MM-DD` |
| dry run | off | Print planned command without calling Jira |

## What This Skill Does

1. Collects the required fields from the conversation.
2. Refuses to create a ticket if required fields are missing.
3. Runs `scripts/create_ticket.py`.
4. The script writes multiline descriptions to a temporary file and calls
   `jira create-ticket --description-file`.
5. Summarizes the created ticket from JSON output.

## What This Skill Will Not Do

- It will not call Jira REST APIs directly.
- It will not store credentials, URLs, tokens, or project defaults.
- It will not vendor jiravis source code.
- It will not create subtasks or update existing tickets.
