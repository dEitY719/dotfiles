# AI Metrics Helper — Common Patterns for gh:* skills

Reference for all skills that record `<!-- ai-metrics:* -->` blocks.

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
<!-- ai-metrics:<skill> -->
📊 ~{TOKENS} tokens · 👤 ~{HUMAN_H} h · 🤖 ~{ELAPSED} min
<!-- /ai-metrics:<skill> -->
```

Append via `printf` to a temp file before creating the artifact:

```bash
printf '\n---\n<!-- ai-metrics:%s -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:%s -->\n' \
  "$SKILL" "$TOKENS" "$HUMAN_H" "$ELAPSED" "$SKILL" >> "$BODY"
```

### GitHub PR / Issue comment

Post after the artifact is created:

```bash
gh api "repos/$TARGET_REPO/issues/$ISSUE_OR_PR_NUM/comments" \
  -X POST \
  -f body="<!-- ai-metrics:$SKILL tokens=$TOKENS human_h=$HUMAN_H ai_min=$ELAPSED -->
🤖 ~$ELAPSED min · 👤 ~$HUMAN_H h · 📊 ~$TOKENS tokens"
```

### stdout-only (read-only skills)

```
[ai-metrics:<skill>] 🤖 ~{ELAPSED} min (read-only — not written to GitHub)
```

### Context-only (intermediate skills)

```
[ai-metrics:<skill>] 🤖 ~{ELAPSED} min — will be included in gh-commit metrics
```

## Idempotency (strip before re-append)

When editing an existing PR body (e.g., `gh-issue-flow`):

```bash
python3 -c "
import re, sys
body = sys.stdin.read()
body = re.sub(r'\n?---\n<!-- ai-metrics -->.*?<!-- /ai-metrics -->\n?', '', body, flags=re.DOTALL)
sys.stdout.write(body)" < existing_body > stripped_body
```

## Soft-fail Rule

Every ai-metrics step must soft-fail: on any error, print a single
warning line and continue — never block the main flow.

```
⚠️  ai-metrics append failed (<reason>) — continuing.
```
