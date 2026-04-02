# Options and Error Handling — CLI reference

## Options

| Option | Description | Default |
|---|---|---|
| `--force` | Skip pre-flight checks, force remove dirty worktree, force delete unmerged branch | `false` |
| `--keep-branch` | Don't delete the branch after removing worktree | `false` |
| `--dry-run` | Print plan without executing anything | `false` |

When `--dry-run` is specified, print the full plan (worktree path, branch,
main repo path, actions to take) and stop without executing anything.

## Error Handling

| Situation | Action |
|---|---|
| Not inside a worktree | Print error, stop |
| Uncommitted changes | Warn, stop (unless `--force`) |
| Unpushed commits | Warn, stop (unless `--force`) |
| Worktree remove fails | Try `--force` if opted in, else stop |
| Branch not fully merged | Warn, skip branch delete (unless `--force`) |
| Main branch not found | Try `master`, then error |
| Pull conflict | AI agent attempts resolution, reports to user |
| Main repo path invalid | Print error, stop |
