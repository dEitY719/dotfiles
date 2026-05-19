# Bedrock-Safe Write — Avoid streaming-truncation failures

This skill must complete in **one Write call per HTML file** without echoing
the generated body into chat. Long inline previews trip AWS Bedrock's
single-event size limit and abort the turn with:

```
API Error: Truncated event message received.
```

The same skill runs fine on the public Anthropic API because that path is
more lenient. Anyone running Claude Code through Bedrock (e.g. the corporate
proxy described in `dotfiles` issues #685 / #687 / #688) hits this on any
non-trivial visualization. The fix is to **stop echoing HTML into chat**,
not to shrink the visualization.

## Hard Rules

1. **One `Write` call writes the entire `.html` file.** Never split a fresh
   file across two `Write` calls — `Write` overwrites, so the second call
   would wipe the first. Use `Write` once for create, then `Edit` for any
   follow-up tweak.
2. **Never echo the HTML body into the assistant response.** Not the full
   file, not a "preview", not a `<head>` excerpt, not a 30-line teaser of
   the `<style>` block. The user opens the file via the `file://` URL — the
   chat is for status only.
3. **Final assistant message is summary + URL + open-command only.** Three
   short paragraphs maximum: what was built, the `file://` URL, and the
   confirmation that `xdg-open` (or `open` on macOS) ran. No code blocks.
4. **Status updates between steps stay terse.** "Reading skeleton",
   "Outlining sections", "Writing file" — one short line each. Do not dump
   intermediate HTML drafts into chat as a thinking aid.

## Size-Aware Strategy

| Estimated output | Behavior |
|---|---|
| < 400 lines / < 24 KB | Single `Write`, no inline echo. Default. |
| ≥ 400 lines / ≥ 24 KB | Single `Write`, no inline echo, **mandatory**. The truncation risk dominates at this size on Bedrock. |
| ≥ 1 000 lines | Single `Write` for the skeleton + content shell, then one or more `Edit` calls to fill in long inline data (chart configs, large SVGs). Never a second `Write` to the same path. |

The thresholds are conservative — Bedrock has truncated turns well below
24 KB in practice. When unsure, treat the file as "large" and follow the
≥ 400-line row.

## When the User Asks "Show me the content"

If the user explicitly wants to see what was generated, reply with a
**structural summary**, not the HTML body:

- section headings as a bulleted list
- which charts / tables / interactions were included
- where to find each piece in the file (anchor name or `<section id>`)

Never paste the rendered HTML into chat to satisfy this request. Offer to
open a viewer or render a screenshot instead.

## Reproduction Log (issue #690)

Recorded for future-self search on the error string
`Truncated event message received`.

Trigger: `/devx-visualize README.md` on the dotfiles repo's `README.md`
(10+ sections, code blocks, table, directory tree). User picked the
Dashboard / One-Pager format. Environment: corporate PC, Claude Code via
AWS Bedrock.

| Attempt | Action | Result |
|---|---|---|
| 1 | Skill announced `Building /home/.../README.html`, started streaming the file inline | `API Error: Truncated event message received.` — turn aborted before `Write` fired |
| 2 | `/devx-restart` resumed at the same step with the same approach | Same error, same point — confirming the issue is the streaming payload, not transient flake |
| 3 | User told the model to skip the inline preview and call `Write` directly | `Write` produced a 644-line `README.html` in one shot, `xdg-open` launched it, no error |

Root cause: the model was emitting the HTML as a long assistant message
**before** invoking `Write`. Each visible HTML line counted against the
streaming event size. Bedrock cut the event mid-payload. The fix in
attempt 3 was purely transport-shaped: the assistant said three sentences,
called `Write` once with the full file, and stopped.

## Recovery Procedure

When you see `Truncated event message received` in this skill:

1. Do not retry the same command. The next streamed turn truncates at the
   same point.
2. Send the user a one-line acknowledgement that the previous turn aborted.
3. Call `Write` immediately with the full file body — no inline preview,
   no per-section dump, no "before I write this, here's what it'll look
   like".
4. Confirm completion with summary + `file://` URL + `xdg-open` line only.

## Why This Applies to Both Backends

Tightening chat output is safe on the public Anthropic API too — the user
never wanted a wall of HTML in the chat, they wanted the rendered file.
Removing inline previews makes the skill faster and cheaper on every
backend, with the side effect of eliminating the Bedrock failure mode.
