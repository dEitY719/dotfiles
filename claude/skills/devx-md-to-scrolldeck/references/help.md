# devx:md-to-scrolldeck — Help

Convert a Markdown document into a single self-contained HTML **vertical
scroll-snap presentation deck** (scrollytelling) — the kind you send to a
leader who will scroll it themselves or project it in a review.

## Usage

```
/devx:md-to-scrolldeck <input.md> [flags]
/devx-md-to-scrolldeck docs/product/vision-and-roadmap.md
/devx-md-to-scrolldeck docs/report.md --out ~/Downloads/report-deck.html
/devx:md-to-scrolldeck -h            # show this help
/devx:md-to-scrolldeck --help        # show this help
/devx:md-to-scrolldeck help          # show this help
```

Natural-language triggers work too: "이 md를 프레젠테이션으로 만들어줘",
"리더 보고용 슬라이드로 변환해줘", "이 문서를 스크롤 프레젠테이션으로",
"make this markdown into a slide presentation",
"turn this report into slides".

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `<input.md>` | yes | Path to the source Markdown file. One file per run. |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--out <path>` | `<input-dir>/<input-basename>.html` | Explicit output path. |
| `--slides <n>` | auto | Force a slide count instead of the curated estimate. Range 5–20. |
| `--outline-only` | off | Print the nav-dot outline and stop. No HTML is written. |
| `--lang <code>` | inferred | Override `<html lang>` (e.g. `en`, `ko`). |
| `--offline-font` | off | Embed the webfont as base64 instead of linking a CDN. Warned + discouraged — see `references/font-and-bedrock-safety.md`. |
| `--no-open` | off | Skip `xdg-open` / `open` after writing. |

## What the skill does

1. Validates the input Markdown path.
2. Reads the whole document and curates it into 5–20 **narrative beats** —
   this is editorial compression, not a heading-to-slide `map()`. Sections
   merge, split, or get cut.
3. Prints the **nav-dot outline** (slide id, label, archetype, phase,
   source lines, plus what was cut) and pauses for your reaction. This is
   the main quality lever.
4. Builds the deck from `references/scroll-deck-skeleton.md`: top progress
   bar, fixed header with phase + `01 / NN` counter, right-edge dot rail,
   `scroll-snap-type: y mandatory` slides, `IntersectionObserver` active
   tracking, arrow-key navigation, per-slide scroll cues.
5. Verifies against `references/checklist.md`, writes the file in a single
   `Write` call, opens it, and reports the slide count + `file://` URL.

## What the skill will NOT do

- **No hamburger menu, no theme toggle, no PNG export.** Deliberate
  divergence from `devx:visualize` — a scroll deck is a single designed
  light-paper theme; dark slides are editorial contrast, not a user
  setting. Do not add `.viz-menu` back.
- **No base64-embedded font by default.** The webfont comes from a CDN;
  embedding it is a multi-megabyte single line that trips AWS Bedrock's
  `Truncated event message received`. `--offline-font` exists but warns.
- **No echoing HTML into chat.** Summary + URL only, always.
- **No inventing content.** Every figure, name, and quote comes from the
  source document. A slide with no source lines is a slide that gets cut.
- **Not a horizontal carousel.** No `translateX` slide transitions, no
  click-zone navigation, no Reveal.js.
- **No multi-file batching**, and it never modifies the input Markdown.

## Prerequisites

- A Markdown file with headings. Documents under ~150 lines usually make a
  better one-pager — the skill will say so.
- A browser for the `file://` output; internet for the CDN webfont on first
  load (the local font fallback chain keeps it readable offline).

## Pairs with

- `devx:visualize` — the general-purpose sibling for dashboards,
  infographics, posters, and horizontal decks. Use it when the output is
  not a vertical scroll deck.
- `devx:excalidraw-diagram` — when the deliverable is a diagram, not a deck.
