# Debug Skill

Help the user debug an issue they're encountering in this current Claude Code session.

{{if debug logging was NOT already enabled}}

## Debug Logging Just Enabled

Debug logging was OFF for this session until now. Nothing prior to this /debug invocation was captured.

Tell the user that debug logging is now active at `{{debugLogPath}}`, ask them to reproduce the issue, then re-read the log. If they can't reproduce, they can also restart with `claude --debug` to capture logs from startup.

## Session Debug Log

The debug log for the current session is at: `{{debugLogPath}}`

{{logInfo — includes log size and last 20 lines in a code block, OR "No debug log exists yet — logging was just enabled." if file doesn't exist}}

For additional context, grep for [ERROR] and [WARN] lines across the full file.

## Issue Description

{{userArg || "The user did not describe a specific issue. Read the debug log and summarize any errors, warnings, or notable issues."}}

## Settings

Remember that settings are in:
* user - {{userSettingsPath}}
* project - {{projectSettingsPath}}
* local - {{localSettingsPath}}

## Instructions

1. Review the user's issue description
2. The last 20 lines show the debug file format. Look for [ERROR] and [WARN] entries, stack traces, and failure patterns across the file
3. Consider launching the claude-code-guide subagent to understand the relevant Claude Code features
4. Explain what you found in plain language
5. Suggest concrete fixes or next steps

{{endif — debug logging not enabled section}}
