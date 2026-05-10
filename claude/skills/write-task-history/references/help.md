# skill:write-task-history — Help

## Synopsis

```
/write-task-history ["<optional description>"]
```

## Description

Write task history from the current conversation to a daily task-list file.
Generates two copy-paste-ready formats: a JIRA ticket (plain text with `>` /
`-` symbols) and a git PR description (markdown). Writes to
`$TASK_HISTORY_DIR` or `~/para/archive/playbook/docs/task-history/`, then
auto-commits the file in its host repository.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `"<optional description>"` | Extra context to supplement conversation analysis. | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/write-task-history
/write-task-history "fix symlink bug + PR #33 merged"
/write-task-history -h
```

## Stop conditions

- Conversation contains no concrete actions to record — ask the user to describe what was done.
- Target directory cannot be created or is read-only — surface the error before generating output.
