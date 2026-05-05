# AI Metrics Baseline

Maps conventional-commit issue types to estimated junior-developer hours.
Used by `gh:issue-create` and `gh:issue-flow` to populate `<!-- ai-metrics -->` footer blocks.

## Human Time Lookup Table

| Issue Type      | Human Time  |
|-----------------|-------------|
| `feat` (small)  | 4 h         |
| `feat` (medium) | 8 h (1 d)   |
| `feat` (large)  | 24 h (3 d)  |
| `fix`           | 2 h         |
| `refactor`      | 4 h         |
| `docs`          | 1 h         |
| `chore`         | 0.5 h       |
| `perf`          | 3 h         |
| `test`          | 2 h         |
| `misc`          | 2 h         |

## Size Heuristic for `feat`

- **Small** (소): single component, ≤ 2 files, no NF requirements → 4 h
- **Medium** (중): 2–5 files, some NF or cross-component work → 8 h
- **Large** (대): ≥ 3 components, explicit NF requirements, architectural decisions → 24 h

When unsure, default to **medium** (8 h).

## Token Estimation

Priority order — first available wins:

1. Explicit `--tokens <N>` override passed to the skill
2. Sum character counts of (issue body draft + title + key context), divide by 4, round to nearest 500. Minimum 1 000.
3. Fallback: 5 000

## Block Format

Append after a `---` horizontal rule at the end of the body:

    ---
    <!-- ai-metrics -->
    📊 ~X tokens · 👤 ~M h · 🤖 ~L min
    <!-- /ai-metrics -->

- `X` — estimated tokens (see Token Estimation above)
- `M` — human hours from the lookup table (e.g. `4 h`, `8 h`, `~1 d`)
- `L` — elapsed minutes from skill entry to issue/PR creation
