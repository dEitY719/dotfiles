# Fonts and Safe Delivery

Two independent rules that both exist because a scroll deck is a *large*
single file. This reference is self-contained on purpose — do not rely on
another skill's copy of it.

---

## 1. Fonts: CDN link by default, never a base64 blob

**Default (always, unless the user asks otherwise): link the webfont from a
CDN.** The skeleton already does this:

```html
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin />
<link
  rel="stylesheet"
  href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css"
/>
```

Alternatives, all fine:

| Content | Link |
|---|---|
| Korean (default) | Pretendard via jsDelivr, as above |
| Korean, Google-only environment | `https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap` |
| Latin-only | `https://fonts.googleapis.com/css2?family=Inter:wght@400;600;800&display=swap` |
| Serif display for headlines | none needed — the skeleton's `--display` stack is all system fonts |

Always keep a full local fallback chain in `--sans` / `--display` so the
deck stays readable if the CDN is blocked.

### Why not embed the font

A base64 `@font-face` is a single enormous line. In the hand-made reference
deck this skill was modelled on, **one line held 2,743,627 characters — 96%
of the file's 2.86 MB.** That is the exact shape that trips the streaming
failure described below, and it also makes every later `Edit` on the file
slow and risky.

### If the user genuinely needs offline

Only when the user explicitly says the deck must work with **no network at
the venue** (air-gapped room, locked-down conference laptop):

1. Warn first, in one line: embedding adds ~1–3 MB as a single line and
   raises the risk of the turn aborting with a truncation error.
2. Offer the cheaper option first — system fonts only. Deleting the CDN
   link and relying on `--sans`'s local chain costs nothing and works
   offline today.
3. If they still want it embedded: write the deck **with** a
   `<!-- DATA:webfont -->` placeholder in place of the `@font-face` block,
   in the single `Write` call. Then fill it with one targeted `Edit`, and
   generate the base64 with a shell command writing straight into the file
   rather than passing megabytes through the model. Never paste base64
   into chat.

---

## 2. Safe delivery: one Write, zero HTML in chat

A scroll deck is routinely 1500–3500 lines. Emitting any of it into the
assistant message risks aborting the turn with:

```
API Error: Truncated event message received.
```

on AWS Bedrock (which is how this repo's corporate machine runs Claude
Code). The public Anthropic API is more lenient, but the rules below cost
nothing there and make every run faster, so they apply unconditionally.

### Hard rules

1. **One `Write` call writes the entire `.html` file.** `Write` overwrites,
   so a second `Write` to the same path destroys the first. Create with
   `Write`, refine with `Edit`.
2. **Never echo the HTML body into the response.** Not the full file, not a
   preview, not the `<head>`, not a 20-line teaser of the `<style>` block,
   not "here's what it'll look like before I write it".
3. **Final message = summary + `file://` URL + open-command line.** No code
   blocks of markup.
4. **Status lines between steps stay terse.** "Outlining", "Writing deck" —
   one short line each. Do not draft HTML in chat as a thinking aid.

### Size-aware strategy

| Estimated output | Behavior |
|---|---|
| < 400 lines | Single `Write`, no inline echo. |
| >= 400 lines | Single `Write`, no inline echo — **mandatory**. Truncation risk dominates here. |
| >= 1000 lines | Single `Write` for the chrome + slide shells, then targeted `Edit` calls to fill long inline blocks. Never a second `Write` to the same path. |

Most decks from a real document land in the >= 1000 row. Seed the skeleton
with unique anchors that `Edit` can match unambiguously:

```html
<!-- DATA:slide-roadmap-track -->
<!-- DATA:slide-anatomy-stack -->
<!-- DATA:webfont -->
```

A bare `<!-- TODO -->` is not unique enough and breaks `Edit`'s uniqueness
check.

### If the user asks "show me what you made"

Reply with a **structural summary** — the slide list with ids and labels,
which archetype each uses, what was cut — not the markup. Offer to open it
or screenshot it instead.

### If a turn does abort with a truncation error

Do not retry the same way; the next turn truncates at the same point.
Acknowledge in one line, then deliver the file with a single `Write`
(plus `Edit` fills) and finish with summary + URL only.
