# Options — gh:discussion-convert arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `<discussion-number>` (positional, required) | Positive integer. | — |
| `[remote]` (positional) | Git remote whose repo owns the Discussion + new Issue. | `origin` |
| `--no-comment` | Skip the `Linked to issue #<M>` backlink comment on the Discussion. | off |
| `--no-lock` | Skip the `Lock conversation` step. | off |
| `--no-close` | Skip the close step (Discussion stays open). | off |
| `--no-board-sync` | Skip the `In progress` Status transition on the project board. | off |
| `--force-category` | Bypass the Step 3 `Ideas`-only guard. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Suppress ai-metrics handling (parity with [[gh-discussion-create]]). | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |
