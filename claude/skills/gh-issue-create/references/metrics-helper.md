# AI Metrics Helper — Common Patterns for gh:* skills

Reference for all skills that record `<!-- ai-metrics:* -->` blocks.

## Opt-out via `GH_DISABLE_AI_METRICS`

Setting `GH_DISABLE_AI_METRICS=1` skips footer attachment in every
`gh:*` skill that posts to GitHub (issue/PR body footer or comment).
Default behaviour (footer attached) is unchanged when the variable is
unset or not equal to `1`.

```bash
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics skipped via GH_DISABLE_AI_METRICS
else
    # ...attach footer / post comment...
fi
```

Scope:

| Skill | Honors env? |
|---|---|
| `gh-issue-create`, `gh-pr`, `gh-pr-merge-emergency` (body footer) | yes |
| `gh-commit`, `gh-pr-reply`, `gh-pr-approve`, `gh-pr-merge`, `gh-pr-resolve-conflict`, `gh-issue-flow` (PR/issue comment) | yes |
| `gh-issue-implement`, `gh-issue-read` (stdout-only context block) | no — never writes to GitHub |
| `gh-add-ai-metrics` (backfill tool) | **no — explicit retrofit intent overrides the env var** |

Backfill is the deliberate "fill in the missing footer" path; respecting
the env there would defeat its purpose. Every other `gh:*` skill must
short-circuit before the GitHub write when the var is `1`. Catalog
entry: `docs/standards/env-vars.md`.

## START_TS Recording

Every skill records its start time at the top of Step 1:

```bash
START_TS=$(date +%s)
```

## Elapsed Time Computation

Just before writing the metrics block:

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
```

## Token Estimation

Character count of key inputs ÷ 4, rounded to nearest 500. Minimum 1 000.

```bash
# Example: issue body + drafts
CHAR_COUNT=$(echo "$ISSUE_BODY$DRAFT_TEXT" | wc -c)
TOKENS=$(( (CHAR_COUNT / 4 / 500 + 1) * 500 ))
[ "$TOKENS" -lt 1000 ] && TOKENS=1000
```

## Human Time Lookup

From `gh-issue-create/references/metrics-baseline.md` by issue type:

| Skill context      | human_h default      |
|--------------------|----------------------|
| `feat` (small)     | 4 h                  |
| `feat` (medium)    | 8 h                  |
| `feat` (large)     | 24 h                 |
| `fix`              | 2 h                  |
| `refactor`         | 4 h                  |
| `docs`             | 1 h                  |
| `chore`            | 0.5 h                |
| `gh-pr-approve`    | 1 h (review fixed)   |
| `gh-pr-merge`      | 0.25 h (merge chore) |
| `gh-pr-reply`      | 0.25 h × comment count |
| `gh-pr-resolve-conflict` | 0.5 h × conflict file count |

## Block Formats by Artifact

### GitHub Issue / PR body footer

```
---
<details>
<summary>🤖 AI Metrics · 📊 ~{TOKENS} tokens · 👤 ~{HUMAN_H} h · 🤖 ~{ELAPSED} min</summary>

<!-- ai-metrics:<skill> -->
📊 ~{TOKENS} tokens · 👤 ~{HUMAN_H} h · 🤖 ~{ELAPSED} min
<!-- /ai-metrics:<skill> -->

</details>
```

Append via `printf` to a temp file before creating the artifact (skip
entirely when `GH_DISABLE_AI_METRICS=1`):

```bash
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics skipped via GH_DISABLE_AI_METRICS
else
    printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:%s -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:%s -->\n\n</details>\n' \
      "$TOKENS" "$HUMAN_H" "$ELAPSED" "$SKILL" "$TOKENS" "$HUMAN_H" "$ELAPSED" "$SKILL" >> "$BODY"
fi
```

### GitHub PR / Issue comment

Post after the artifact is created (skip when
`GH_DISABLE_AI_METRICS=1`):

```bash
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$ISSUE_OR_PR_NUM/comments" \
      -X POST \
      -f body="<!-- ai-metrics:$SKILL tokens=$TOKENS human_h=$HUMAN_H ai_min=$ELAPSED -->
🤖 ~$ELAPSED min · 👤 ~$HUMAN_H h · 📊 ~$TOKENS tokens"
fi
```

### stdout-only (read-only skills)

```
[ai-metrics:<skill>] ~{ELAPSED} min (read-only — not written to GitHub)
```

### Context-only (intermediate skills)

```
[ai-metrics:<skill>] ~{ELAPSED} min — will be included in gh-commit metrics
```

## Idempotency (strip before re-append)

When editing an existing PR body (e.g., `gh-issue-flow`):

```bash
python3 -c "
import re, sys
body = sys.stdin.read()
body = re.sub(
  r'\n?---\n(?:<details>\n<summary>[^\n]*</summary>\n\n)?<!-- ai-metrics(:.*?)? -->.*?<!-- /ai-metrics(:.*?)? -->(?:\n\n</details>)?\n?',
  '', body, flags=re.DOTALL)
sys.stdout.write(body)" < existing_body > stripped_body
```

## Soft-fail Rule

Every ai-metrics step must soft-fail: on any error, print a single
warning line and continue — never block the main flow.

```
[WARN] ai-metrics append failed (<reason>) — continuing.
```
