# Footer Detection + Replacement

Detection and edit logic for the `<!-- ai-metrics -->` footer used by
`gh:add-ai-metrics`. Keep regexes here so SKILL.md can stay workflow-only.

## Marker grammar

Two forms exist in the wild — both must be detected as "already tagged":

- `<!-- ai-metrics -->` … `<!-- /ai-metrics -->`
  (the original PR #320 / `gh-issue-create` shape)
- `<!-- ai-metrics:<skill-name> -->` … `<!-- /ai-metrics:<skill-name> -->`
  (the newer `metrics-helper.md` scheme used by post-#320 retro-fit work)

A single regex covers both:

```
<!-- ai-metrics(:[a-zA-Z0-9_-]+)? -->[\s\S]*?<!-- /ai-metrics(:[a-zA-Z0-9_-]+)? -->
```

## Bash detection

A naive `grep '<!-- ai-metrics'` returns false positives on bodies that
*mention* the marker in inline code spans (e.g. issue #324 itself, which
documents the footer format and contains many bare `<!-- ai-metrics -->`
references in backticks). The detector therefore requires the **anchored
pair**: a `---` separator on its own line preceded by 1+ newlines,
immediately followed by the OPEN marker on its own line, content, then
the CLOSE marker on its own line.

```bash
has_footer() {
  # Returns 0 (true) only when an OPEN+CLOSE block follows the `---`
  # separator that gh:issue-create / PR #320 emit. Inline mentions
  # (`<!-- ai-metrics -->` in backticks) do not match. The leading
  # `\n+` tolerates both PR #320's `\n---\n` (single) and the newer
  # `\n\n---\n` (double) append conventions.
  printf '%s' "$1" | perl -0777 -ne '
    exit (
      /\n+---\n<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->\n.*?\n<!-- \/ai-metrics(?::[A-Za-z0-9_-]+)? -->/s
      ? 0 : 1
    )'
}
```

Why perl, not `grep -P`: the multiline `.*?\n` slurp requires `-0777`,
which has no GNU grep equivalent. Perl is a hard dep of the gh CLI's
shipping environment, so this stays portable.

## Append (no existing footer)

```bash
append_footer() {
  local body="$1" tokens="$2" human="$3" elapsed="$4"
  printf '%s\n\n---\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n' \
    "$body" "$tokens" "$human" "$elapsed"
}
```

The leading `\n\n---\n` ensures the footer is visually separated from the
preceding section even when the original body did not end with a newline.

## In-place replace (`--force` path)

`perl -0777` for slurp-mode multiline regex. `python3` is the fallback if
perl is unavailable (rare). Note the negated `:gh-add-ai-metrics` capture
when re-emitting — we always emit the colonless form to stay 1:1 with
`gh-issue-create`'s SSOT shape.

```bash
replace_footer() {
  local body="$1" tokens="$2" human="$3" elapsed="$4"
  local new_block
  new_block=$(printf '<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->' \
    "$tokens" "$human" "$elapsed")
  printf '%s' "$body" \
    | NEW="$new_block" perl -0777 -pe '
        BEGIN { $n = $ENV{NEW} }
        s|<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->.*?<!-- /ai-metrics(?::[A-Za-z0-9_-]+)? -->|$n|s
      '
}
```

The `BEGIN`-block pattern reads `$NEW` from the env so newline-bearing
replacements survive the perl substitution untouched (no `$1` collision).

## `--force` on a card without a footer

`replace_footer` returns the original body unchanged when the regex does
not match. Detect that and degrade to `append_footer`:

```bash
new_body=$(replace_footer "$body" "$tokens" "$human" "$elapsed")
if [ "$new_body" = "$body" ]; then
  new_body=$(append_footer "$body" "$tokens" "$human" "$elapsed")
fi
```

This keeps `--force` semantically "ensure the footer reflects current
metrics" even when the card never had one.

## Edit call

Always write to `mktemp` first — direct `--body "$str"` mishandles backticks
and large bodies. Use `gh issue edit` for issues, `gh pr edit` for PRs.

```bash
TMP=$(mktemp) && trap 'rm -f "$TMP"' EXIT
printf '%s' "$new_body" > "$TMP"
gh "$kind" edit "$N" --repo "$TARGET_REPO" --body-file "$TMP"
```

`$kind` ∈ `{issue, pr}`; the rest of the command is identical.

## Skip path (idempotent guarantee)

When `has_footer` returns 0 and `--force` is off, do not call `gh edit` at
all. This is the API-quota-friendly path described in SKILL.md Constraints.

## Per-card status output format

Each iteration of the per-card loop prints exactly one of these lines.
Glyph and field order are part of the user contract — keep them stable.

| Branch | Format |
|---|---|
| New footer appended | `✓ added #N <title>` |
| Existing footer replaced (`--force`) | `↻ replaced #N <title>` |
| Existing footer left untouched | `→ skipped #N <title>` |
| API or I/O failure | `✗ failed #N <reason>` |

The `failed` branch must not abort the loop — catch the failure, print
the line, and continue with the next card. The Step 4 summary counts
each branch separately (`added=A ↻ replaced=R → skipped=S ✗ failed=F`).

## Final report output format

After the per-card loop completes, print exactly two lines:

```
Summary: ✓ added=A  ↻ replaced=R  → skipped=S  ✗ failed=F  (total T)
[ai-metrics:gh-add-ai-metrics] 🤖 ~{ELAPSED} min · {T} cards processed
```

The second line is **context-only**: this skill does mutate GitHub
artifacts, but its own runtime metric is informational and not written
into any specific card's footer (the per-card metrics are what the
loop just appended). Treat it like the `gh:issue-implement` context
line — emitted to stdout, not posted as a comment.

## Test rubric

A retro-fit run is correct iff:

1. Stripping the new `\n+---\n<!-- ai-metrics -->…<!-- /ai-metrics -->`
   block from the post-edit body yields the original (pre-edit) body
   byte-for-byte (regardless of whether append used `\n---\n` or
   `\n\n---\n`).
2. Running the skill twice without `--force` produces zero edit API
   calls on the second run.
3. Running once with `--force` and once without on the same card
   produces identical bodies (idempotent).
4. `has_footer` returns false on a body that mentions the marker only
   in inline code spans (e.g. `\`<!-- ai-metrics -->\`` inside docs).
   Issue #324 of this repo is the canonical positive example for this
   case after stripping.
