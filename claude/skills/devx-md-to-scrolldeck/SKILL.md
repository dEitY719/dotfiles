---
name: devx:md-to-scrolldeck
description: >-
  Convert a Markdown document into a single self-contained HTML vertical
  scroll-snap presentation deck (scrollytelling) for reporting up to
  leadership — progress bar, phase header, right-edge dot rail, snap
  slides, arrow-key navigation, print-ready. Use whenever the user runs
  /devx:md-to-scrolldeck or /devx-md-to-scrolldeck, or says "이 md를
  프레젠테이션으로 만들어줘", "리더 보고용 슬라이드로 변환해줘", "이 문서를 스크롤
  프레젠테이션으로", "이 보고서 슬라이드 덱으로", "make this markdown into a slide
  presentation", "turn this report into slides", "scrollytelling deck from
  this doc" — and also when the user points at a .md file and asks for
  slides, a deck, or a presentation without naming the format. The hard
  part is editorial curation (25 headings become ~14 slides), so always run
  the outline step first. Deliberately omits devx:visualize's hamburger
  menu, theme toggle, and PNG export, and never base64-embeds a font.
  Sister skill of [[devx-visualize]] — that one covers dashboards,
  infographics, posters and horizontal decks; this one owns the vertical
  scroll deck. Accepts `<input.md> [--out <path>] [--slides <n>]
  [--outline-only] [--lang <code>] [--offline-font] [--no-open]` and
  `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  version: 0.1.0
  category: document-creation
  model_recommendation:
    tier: sonnet
    reason: "Editorial compression + bounded HTML generation from a fixed skeleton"
    claude: prefer
    non_claude: advisory-only
  tags: [presentation, html, scrollytelling, markdown, slides]
---

# devx:md-to-scrolldeck — Markdown → vertical scroll-snap deck

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. **No file reads, no file writes.**

## Step 1: Parse Args + Validate Input

Required positional: exactly one `<input.md>`. Flags: `--out <path>`,
`--slides <n>`, `--outline-only`, `--lang <code>`, `--offline-font`,
`--no-open`. Full table in `references/help.md`.

The path must exist as a regular file — on a miss, print
`[FAIL] devx:md-to-scrolldeck: input not found: <path>` and stop with
exit 1. More than one positional → `[FAIL] one Markdown file per run`.
A non-Markdown extension is a `[WARN]`, not a stop — the user may have a
`.txt` that is really Markdown.

Resolve the output path now so later steps have it:

1. `--out <path>` given → honor it verbatim.
2. Otherwise → **same directory, same basename, `.html` extension** as the
   input. `docs/vision.md` → `docs/vision.html`.

If the output already exists, say so in Step 5's report; overwrite it.

## Step 2: Read + Outline (do not skip)

Read the **entire** document before deciding anything — you need the ending
to know what the opening should set up.

Then apply `references/slide-curation.md` to compress it into narrative
beats. This is the main quality lever of the skill: the reference deck this
format comes from turned ~25 headings into 14 slides, merging four
subsections into one slide and splitting another section across two. A 1:1
heading→slide mapping produces a table of contents, which is exactly what a
leadership audience does not want.

Produce the **nav-dot outline** as an intermediate artifact and print it to
the user before writing any HTML — one row per slide with number, `id` slug,
label, archetype, `data-phase`, and the source line range, plus a line
listing what was cut. Format in `references/slide-curation.md` → Step C.

Then:

- `--outline-only` → stop here.
- Fewer than 5 beats → `[WARN] too short for a deck — devx:visualize
  one-pager is a better fit` and ask before continuing.
- More than 20 beats → propose a scope cut rather than silently building 30
  slides.
- Otherwise → state that you are building it and continue. Do not wait for
  approval unless the user asked to review first; the outline is printed so
  they can interrupt.

## Step 3: Build from the Skeleton

Copy `references/scroll-deck-skeleton.md` and replace its `YOUR ... HERE`
tokens. **Never write this HTML from scratch** — the chrome (progress bar,
`scroll-snap-type: y mandatory`, dot rail, `IntersectionObserver`, arrow
keys, print styles, reduced-motion) is load-bearing and the checklist
greps for it.

Per-slide: pick the archetype from the outline, choose a slide variant so
consecutive slides never look identical, and write real content from the
source — never placeholder text, never invented figures.

Fonts: keep the skeleton's **CDN webfont link**. Do not base64-embed a font
unless `--offline-font` was passed, and then only after warning the user —
see `references/font-and-bedrock-safety.md`.

Out of scope by design: `.viz-menu`, theme toggle, PNG export. This is a
deliberate divergence from `devx:visualize`; do not add them back.

## Step 4: Verify

Run `references/checklist.md` against the file you are about to write (or
just wrote). Its grep block checks the mechanical items in one pass: slide
count, dot count, cue count, absence of `.viz-menu` and base64 fonts,
presence of snap / observer / arrow keys / print styles.

Any failure → fix it before reporting. Do not report a deck with a broken
dot rail as `[OK]`.

## Step 5: Write, Open, Report

Three rules, all non-negotiable — reasoning in
`references/font-and-bedrock-safety.md`:

1. **One `Write` call** writes the whole `.html`. `Write` overwrites, so a
   second `Write` to the same path destroys the first. Refine with `Edit`.
   For files over ~1000 lines, seed unique `<!-- DATA:slide-xyz -->`
   anchors and fill them with targeted `Edit` calls.
2. **Auto-open** unless `--no-open`: `xdg-open <file>.html` on Linux/WSL,
   `open <file>.html` on macOS. **Never `wslview`** — it errors on HTML.
3. **Never echo the HTML body into chat.** Not the full file, not a
   preview, not the `<head>`, not a `<style>` excerpt. This avoids the AWS
   Bedrock `Truncated event message received` abort and is harmless on the
   Anthropic-direct path.

Then print the verdict:

```
[OK] devx:md-to-scrolldeck slides=<n> out=<path>
file://<absolute-path>
```

Follow it with the one-line slide list (ids only) and what was cut, so the
user can judge the curation without opening the file. If any checklist item
was waived, emit `[WARN] <item>: <reason>` instead of hiding it.

Next: `Review the deck, or re-run with --slides <n> to force a different
count, or --outline-only first next time to approve the beats before build.`
