# Options and Error Handling -- CLI reference

## Options

| Option | Description | Default |
|---|---|---|
| `--agent <name>` | Override agent name | auto-detect |
| `--task "slug"` | Add task slug to branch name (English only) | none |
| `--base <ref>` | Base branch/commit | `origin/main` |
| `--dry-run` | Print plan without creating anything | `false` |

When `--dry-run` is specified, print the full plan (agent, path, branch, base,
command) and stop without creating anything.

`--list` is NOT included here. Use the separate `ai-worktree:list` skill instead.

## Error Handling

| Situation | Action |
|---|---|
| Not a git repo | Print error, stop |
| Inside a worktree | Print error, stop (always use a new terminal on the main repo) |
| Base ref not found | Suggest `main`/`origin/main`, stop |
| Path already exists | Auto-increment to next index |
| Branch in use by another worktree | Print error, ask user for different name |
| Parent dir not writable | Print error, stop |
| Lock acquisition failed (3 retries) | Print error, stop |
| Stale lock (age > 10s) | Auto-remove lock, retry |
| git-crypt active in repo | Auto-bypass: create worktree with filter disabled, encrypted files stay as binary |
