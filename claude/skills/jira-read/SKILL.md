---
name: jira:read
description: >-
  Read Jira ticket details through the jiravis `jira get-ticket-detail` CLI.
  Use this skill whenever the user runs /jira:read, /jira-read, asks to read a
  Jira ticket, provides a key like ABC-123, says "Jira issue detail",
  "Jira 읽어줘", "Jira 이슈 파악", or wants a Jira ticket summarized for
  implementation context. Read-only. Requires jiravis CLI installed as `jira`.
allowed-tools: Bash, Read, Grep
---

# jira:read

## Help

If the user asks for help (`-h`, `--help`, or `help`), read
`references/help.md` and output it, then stop.

## Role

Read one Jira ticket by calling the bundled wrapper script. The script is a
thin read-only adapter over the jiravis CLI; it validates ticket keys, calls
`jira get-ticket-detail`, and normalizes JSON output for implementation work.

## Workflow

1. Extract a Jira ticket key from the user request or explicit argument.
2. If no key is present, ask for the ticket key and stop.
3. Run `scripts/read_ticket.py --ticket-id <KEY>` from this skill directory.
4. Report the normalized ticket context:
   - ticket id, URL, summary, status, priority
   - assignee and reporter
   - description
   - labels, components, created and updated timestamps
   - subtasks
5. If the user asks for raw JSON or text output, pass the matching script flag.

## Command Pattern

```bash
python claude/skills/jira-read/scripts/read_ticket.py --ticket-id <PROJECT-123>
```

## Output Format

For normal reads, respond in this shape:

```text
Jira ticket: <ticket_id>
URL: <ticket_url>
Summary: <summary>
Status: <status>
Priority: <priority>
Assignee: <assignee>
Reporter: <reporter>

Description:
<description>

Metadata:
Labels: <labels>
Components: <components>
Updated: <updated_at>

Subtasks:
<subtask list or None>
```

## Constraints

- Read-only: never call create, update, transition, delete, comment, or link commands.
- Do not implement Jira REST calls in this skill.
- Do not copy jiravis internal Python modules into this repository.
- Do not hardcode Jira URLs, credentials, account IDs, or project defaults.
- Keep the skill package independently shareable with its own `scripts/`.
