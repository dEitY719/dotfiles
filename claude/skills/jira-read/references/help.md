# jira:read Help

Read Jira ticket details through the jiravis CLI.

## Prerequisites

- Python 3.10+
- jiravis CLI installed as `jira`
- `jira` available on `PATH`
- jiravis authentication and config already set up

## Usage

```text
/jira:read JIRAVIS-123
/jira-read JIRAVIS-123
JIRAVIS-123 읽어줘
```

## Required Inputs

| Field | Description |
|---|---|
| ticket id | Jira key in `PROJECT-123` form |

## Optional Modes

| Mode | Description |
|---|---|
| raw JSON | Print raw jiravis JSON output |
| text | Ask jiravis for text output and pass it through |
| verbose | Add `--verbose` when using text mode |

## What This Skill Does

1. Finds a Jira key in the request.
2. Normalizes it to uppercase.
3. Runs `scripts/read_ticket.py`.
4. The script calls `jira get-ticket-detail --output json --no-confirm`.
5. Summarizes the ticket for implementation context.

## What This Skill Will Not Do

- It will not mutate Jira.
- It will not call Jira REST APIs directly.
- It will not store credentials, URLs, tokens, or project defaults.
- It will not vendor jiravis source code.
