# gh:discussion-create — Step 4 Create Command

Detail companion to SKILL.md Step 4. Writes the drafted body to a temp
file, appends the ai-metrics footer (unless `GH_DISABLE_AI_METRICS=1`),
and runs the three GraphQL calls via `gh_discussion.sh`.

`$TOKENS`, `$HUMAN_H`, `$ELAPSED` come from Step 3.5.
`$TARGET_REPO` is set in Step 1, split into `$_owner` / `$_repo` here.
`$CATEGORY` defaults to `Ideas` per Step 2 (case-insensitive match
against the repo's category list).
`$TITLE` is drafted in Step 3.

```bash
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"

BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write drafted body to "$BODY" ...
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
else
    printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:gh-discussion-create -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:gh-discussion-create -->\n\n</details>\n' \
      "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
fi

_owner="${TARGET_REPO%%/*}"
_repo="${TARGET_REPO##*/}"

REPO_ID=$(_gh_discussion_repo_id "$_owner" "$_repo") || exit 1
CATEGORY_ID=$(_gh_discussion_category_id "$_owner" "$_repo" "$CATEGORY") || exit 1
URL=$(_gh_discussion_create "$REPO_ID" "$CATEGORY_ID" "$TITLE" "$BODY") || exit 1

printf '%s\n' "$URL"
```

확인 질문하지 말고 즉시 실행.

## ai-metrics footer note

The four emoji glyphs in the printf above (`🤖 📊 👤`) are the
ai-metrics footer exception defined in `CLAUDE.md`. The exception
covers exactly this `<details>` wrapper plus the
`<!-- ai-metrics:gh-discussion-create -->` block. The exception does
not extend anywhere else in this skill or the helper.

## Why three calls instead of one mutation

`createDiscussion` requires a `repositoryId` and a `categoryId`, both
of which are **node IDs** (opaque base64 strings), not the
human-readable `owner/repo` and `Ideas` strings the user works with.
GitHub's REST API exposes neither write path nor a single "create by
slug" shortcut — the lookups must happen first. Splitting them into
three helper calls keeps the failure modes distinct:

- repo lookup fails -> network/auth/missing repo
- category lookup fails -> Discussions disabled or category typo
- mutation fails -> permission, validation, or partial outage

Each branch yields a different remediation hint.

## Why no category-ID disk cache

See [`cache-decision.md`](cache-decision.md). Short version: one
GraphQL call per skill invocation is cheap; a stale cache after the
user renames a category would be a silent posting bug.
