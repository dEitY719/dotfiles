# File Entry Structure — Step 6

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
