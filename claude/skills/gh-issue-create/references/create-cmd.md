# gh:issue-create — Step 4 Create Command

Detail companion to SKILL.md Step 4. Writes the drafted body to a temp
file, appends the ai-metrics footer (unless `GH_DISABLE_AI_METRICS=1`),
and calls `gh issue create`.

`$TOKENS`, `$HUMAN_H`, `$ELAPSED` come from Step 3.5.
`LABEL_ARGS` / `MILESTONE_ARGS` are the arrays Step 2.5 prepared (one
`--label <name>` per kept label; `--milestone <title>` if resolved).
Both are empty when Step 2.5 was skipped — the `gh issue create`
invocation degrades to its original form.

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

확인 질문하지 말고 즉시 실행.

The four emoji glyphs in the printf above (`<U+1F916> <U+1F4CA> <U+1F464>`) are
the ai-metrics footer exception defined in `CLAUDE.md` — the `<details>`
wrapper + `<!-- ai-metrics -->` block. The exception does not extend
anywhere else in this skill.
