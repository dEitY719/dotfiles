---
name: jira:create
description: >-
  Create Jira tickets through the jiravis `jira create-ticket` CLI. Use this
  skill whenever the user runs /jira:create, /jira-create, asks to create a
  Jira ticket, says "Jira ticket", "Jira create", "Jira 생성", "Jira 티켓
  만들어줘", or wants the current conversation turned into a Jira issue.
  Requires jiravis CLI installed as `jira`.
allowed-tools: Bash, Read, Grep
---

# jira:create

## Help

If the user asks for help (`-h`, `--help`, or `help`), read
`references/help.md` and output it, then stop.

## Role

Create one Jira ticket by calling the bundled wrapper script. The script is a
thin adapter over the jiravis CLI; it validates inputs, handles multiline
descriptions safely, calls `jira create-ticket`, and parses JSON output.

## Workflow

1. Extract required fields from the user request:
   - project key
   - summary
   - description
2. Extract optional fields if present:
   - issue type, default `Task`
   - priority, default `Medium`
   - assignee, labels, components, due date
   - dry run, raw output, text output
3. If a required field is missing, ask only for the missing value and do not
   run the create command.
4. Run `scripts/create_ticket.py` from this skill directory. Prefer
   `--description` for conversation text; the script writes it to a temporary
   file and passes `--description-file` to jiravis.
5. Report the resulting `ticket_id`, `ticket_url`, `summary`, `issue_type`,
   and `priority`. If the script fails, preserve the error code and message.

Stop immediately on any step failure; do not proceed to the next step.

## Command Pattern

```bash
python claude/skills/jira-create/scripts/create_ticket.py \
  --project-key <PROJECT> \
  --summary <SUMMARY> \
  --description <DESCRIPTION> \
  --issue-type Task \
  --priority Medium
```

## Output Format

For success, respond in this shape:

```text
[OK] Created Jira ticket: <ticket_id>
URL: <ticket_url>
Summary: <summary>
Type: <issue_type>
Priority: <priority>
```

For failures, state the failed command area, exit code when available, and the
script error message. Do not expose tokens, config values, or secrets.

```text
[FAIL] create-ticket exit=<code>
<error message>
```

## Constraints

- Do not implement Jira REST calls in this skill.
- Do not copy jiravis internal Python modules into this repository.
- Do not create a ticket when project key, summary, or description is missing.
- Do not hardcode Jira URLs, credentials, account IDs, or project defaults.
- Keep the skill package independently shareable with its own `scripts/`.
