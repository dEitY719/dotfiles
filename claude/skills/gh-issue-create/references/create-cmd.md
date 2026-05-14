# gh:issue-create — Step 4 Create Command

Detail companion to SKILL.md Step 4. Writes the drafted body to a temp
file, appends the ai-metrics footer (unless `GH_DISABLE_AI_METRICS=1`),
and calls either `gh issue create` (default) or the
`_gh_discussion_*` helpers (`DISCUSSION_MODE=1`, #619).

`$TOKENS`, `$HUMAN_H`, `$ELAPSED` come from Step 3.5.
`LABEL_ARGS` / `MILESTONE_ARGS` are the arrays Step 2.5 prepared (one
`--label <name>` per kept label; `--milestone <title>` if resolved).
Both are empty when Step 2.5 was skipped — the `gh issue create`
invocation degrades to its original form. When `DISCUSSION_MODE=1`,
Step 2.5 is skipped unconditionally, so both arrays are empty and the
Discussion branch ignores them.

## Issue path (default)

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write body to "$BODY" ...
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
else
    printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n\n</details>\n' \
      "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
fi
gh issue create --repo "$TARGET_REPO" --title "<title>" --body-file "$BODY" \
    "${LABEL_ARGS[@]}" "${MILESTONE_ARGS[@]}"
```

`--assignee` is still only added when the user asks. User-supplied
`--label` flags survive Step 2.5 (union with auto labels) unless
`--no-auto-labels` was set, in which case Step 2.5 is bypassed and the
user's labels pass straight through `LABEL_ARGS` from Step 1.

## Discussion path (`DISCUSSION_MODE=1`)

Triggered by `--as-discussion <category>` from Step 1.1. Sources the
shared helper used by [[gh-discussion-create]] and calls the three
GraphQL primitives in order. `$CATEGORY` was validated in Step 1.1
against `Ideas` / `Q&A` / `Announcements` / `Lessons` — no extra
validation here.

```bash
# Fail fast if the helper file is missing (skill installed but
# helper not yet symlinked into shell-common/).
if [ ! -r "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh" ]; then
    printf '[FAIL] gh-discussion helper not found at %s/shell-common/functions/gh_discussion.sh\n' \
      "$DOTFILES_ROOT" >&2
    printf 'Next: install gh-discussion-create skill first.\n' >&2
    exit 1
fi
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"

BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write Open-Questions-forward body to "$BODY" (Step 3 sets shape) ...
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
else
    printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:gh-issue-create -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:gh-issue-create -->\n\n</details>\n' \
      "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
fi

_owner="${TARGET_REPO%%/*}"
_repo="${TARGET_REPO##*/}"

REPO_ID=$(_gh_discussion_repo_id "$_owner" "$_repo") || exit 1
CATEGORY_ID=$(_gh_discussion_category_id "$_owner" "$_repo" "$CATEGORY") || exit 1
URL=$(_gh_discussion_create "$REPO_ID" "$CATEGORY_ID" "$TITLE" "$BODY") || exit 1

printf '[OK] Discussion (%s): %s\n' "$CATEGORY" "$URL"
```

The three helper calls match [[gh-discussion-create]]'s
`references/create-cmd.md` byte-for-byte — keep them in lock-step. If
the helper ever changes signature, update both skills together.

확인 질문하지 말고 즉시 실행.

The four emoji glyphs in the printf above (`<U+1F916> <U+1F4CA> <U+1F464>`) are
the ai-metrics footer exception defined in `CLAUDE.md` — the `<details>`
wrapper + `<!-- ai-metrics -->` (or `<!-- ai-metrics:gh-issue-create -->`)
block. The exception does not extend anywhere else in this skill.
