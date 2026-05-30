# Options — gh:discussion-create arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `[remote]` (positional) | Git remote whose repo will own the Discussion. | `origin` |
| `[category]` (positional) | Discussion category. Case-insensitive match against the repo's category list. Allowed: `Ideas`, `Q&A`, `Announcements`, `Lessons`. | `Ideas` |
| `--force-discussion` | Bypass the routing guard (Step 2.1) when you know the chat is RFC-shaped despite a decided tone. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

The two positional args are order-insensitive when one is clearly a
category (e.g. `Q&A`, `Ideas`); otherwise the first non-flag positional
is treated as the remote.
