---
name: devx:md-to-scrolldeck
description: >-
  Markdown 문서를 리더 보고용 세로 스크롤스냅 HTML 덱(scrollytelling) 한 파일로
  변환한다. Use for /devx:md-to-scrolldeck, /devx-md-to-scrolldeck, "이 md를
  프레젠테이션으로 만들어줘", "turn this report into slides", 또는 .md 를
  가리키며 슬라이드/덱 요청 시. 대시보드·인포그래픽·가로 덱은 devx:visualize.
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
`--no-open` — full table in `references/help.md`.

Missing/unreadable path → `[FAIL] devx:md-to-scrolldeck: input not found:
<path>` + exit 1. Two+ positionals → `[FAIL] one Markdown file per run`.
Non-`.md` extension → `[WARN]`, not a stop.

Output path: `--out <path>` if given, else input's dir + basename with
`.html` (`docs/vision.md` → `docs/vision.html`); overwrite silently if it
already exists, but say so in the final report.

## Step 2: Read + Outline (do not skip)

Read the **entire** document first — you need the ending to know what the
opening should set up. Then apply `references/slide-curation.md` to compress
it into narrative beats; this is the skill's main quality lever, not a
1:1 heading→slide `map()` (see that file for why).

Print the **nav-dot outline** (id, label, archetype, `data-phase`, source
lines, plus what was cut — format in `slide-curation.md` → Step C) before
writing any HTML.

- `--outline-only` → stop here.
- Fewer than 5 beats → `[WARN] too short — devx:visualize one-pager fits better` and ask before continuing.
- More than 20 beats → propose a scope cut, don't silently build 30 slides.
- Otherwise → continue without waiting for approval; the printed outline is what lets the user interrupt, not a blocking prompt.

## Step 3: Build, Write, Verify, Deliver

Copy `references/scroll-deck-skeleton.md` and replace its `YOUR ... HERE`
tokens — **never write this HTML from scratch**. The chrome is load-bearing and
the checklist greps for it: top progress bar, fixed phase header with an
`01 / NN` counter, right-edge dot rail, `scroll-snap-type: y mandatory` slides
tracked by `IntersectionObserver`, arrow-key navigation, print-ready output.

Per-slide: pick the archetype from the outline, vary the slide treatment so no
three are identical, write real content only (never placeholder text or
invented figures). Keep the CDN webfont link; base64-embed only behind
`--offline-font`, after warning — see `references/font-and-bedrock-safety.md`. Do not add back `.viz-menu`,
theme toggle, or PNG export — deliberately out of scope here.

Then, in this order: (1) **one `Write` call** for the whole file — see
`font-and-bedrock-safety.md` § 2 for why one call, no chat echo; (2) run
`references/checklist.md`'s grep block against the file you just wrote —
any failure gets fixed and rewritten before you report, never report a
broken dot rail as `[OK]`; (3) auto-open unless `--no-open` (`xdg-open` on
Linux/WSL, `open` on macOS — never `wslview`, it errors on HTML).

Report:

```
[OK] devx:md-to-scrolldeck slides=<n> out=<path>
file://<absolute-path>
```

Follow with the slide-id list and what was cut. Waived checklist items are
`[WARN] <item>: <reason>`, never silent.

Next: `Review the deck, or re-run with --slides <n> / --outline-only to
adjust the curation before another build.`

## Related Skills

`devx:visualize` — the general-purpose sibling for dashboards, infographics,
posters, and horizontal decks; this skill owns the vertical scroll deck only ·
`devx:excalidraw-diagram` — when the deliverable is a diagram, not a deck.
