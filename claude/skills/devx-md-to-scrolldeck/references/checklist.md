# Pre-Flight Checklist — verify before reporting the deck done

Run every item. Most are grep-able against the written file, so verify by
inspection of the file, not from memory. A quick pass:

```sh
DECK=<output>.html
# Match on the class attribute, NOT on '<section class="slide' - a formatted
# file often wraps the attributes onto their own lines and that pattern
# silently undercounts.
grep -c 'class="slide[ "]' "$DECK"            # slide count
grep -c 'class="deck-nav__dot"' "$DECK"       # must equal slide count
grep -c 'class="next-cue"' "$DECK"            # must equal slide count - 1
grep -c 'viz-menu\|cycleTheme\|toggleMenu\|downloadImage\|theme-dark' "$DECK"  # must be 0
grep -c 'url("data:font\|url(data:font' "$DECK"   # must be 0 unless user asked
grep -c 'aria-labelledby=' "$DECK"            # must equal slide count
grep -n 'scroll-snap-type: y mandatory\|scroll-snap-align: start\|scroll-snap-stop: always\|IntersectionObserver\|ArrowDown\|ArrowUp\|prefers-reduced-motion\|@media print\|page-break-after' "$DECK"
```

Cross-checks a plain `grep` cannot do — dot `href`s resolving to real slide
ids, and each `.next-cue` pointing at the *next* slide rather than any
slide — are worth a throwaway script when the deck is long. Getting the
cue chain off by one is the most common wiring bug.

## Curation

- [ ] The nav-dot outline was produced and shown to the user **before** any
      HTML was written?
- [ ] Slide count is between 5 and 20, and matches the outline?
- [ ] Slides are narrative beats, not a 1:1 copy of the source headings?
- [ ] Reference lists / link dumps / appendices were cut, and the cuts were
      reported?
- [ ] Every slide traces to a source line range — nothing invented?
- [ ] Reading the headlines in order tells a coherent story?
- [ ] One idea per slide, headline <= ~10 words, body <= ~40 words?
- [ ] Slide variants alternate — no three consecutive identical treatments?

## Scroll chrome

- [ ] `scroll-snap-type: y mandatory` on `html`, and
      `scroll-snap-align: start` + `scroll-snap-stop: always` on `.slide`?
- [ ] `.deck-nav__dot` count equals `.slide` count, in the same order, and
      every `href="#id"` resolves to an existing slide id?
- [ ] `.progress__bar` present and wired — `updateProgress()` sets its
      `scaleX` from scroll position, on `scroll` and `resize`?
- [ ] `.deck-header` counter reads `01 / NN` with the real slide count, and
      `data-phase` on every slide feeds `.deck-header__phase`?
- [ ] `IntersectionObserver` sets the active slide and moves
      `aria-current="step"` across the dots?
- [ ] `ArrowDown` / `ArrowUp` (plus PageDown/PageUp/Home/End/Space) call
      `goTo()`, and `goTo()` uses `scrollIntoView` with
      `behavior: reduceMotion ? "auto" : "smooth"`?
- [ ] Every slide except the last has a `.next-cue` pointing at the next
      slide's id, and the last slide has none?

## Accessibility and resilience

- [ ] `@media (prefers-reduced-motion: reduce)` present, disabling
      `scroll-behavior`, animations, and the `.reveal` transform?
- [ ] Content is visible without JS — `.reveal` hiding is scoped to `.js`,
      and a `<noscript>` note is present?
- [ ] Every `<section class="slide">` has `aria-labelledby` matching its own
      heading id, and every dot has a descriptive `aria-label`?
- [ ] `<html lang>` matches the source document's language, and Korean text
      keeps `word-break: keep-all`?
- [ ] No horizontal overflow at 375px; snap is disabled under 767px?

## Print

- [ ] `@media print` turns scroll-snap **off** (`scroll-snap-type: none`)?
- [ ] Print hides `.progress`, `.deck-header`, `.deck-nav`, `.next-cue`?
- [ ] Every slide breaks onto its own page
      (`break-after: page` / `page-break-after: always`) so all slides
      stack instead of only the first one printing?
- [ ] `.reveal` forced visible in print?
- [ ] Dark slides set `print-color-adjust: exact`?

## Explicitly out of scope (fail if present)

This format deliberately diverges from `devx:visualize`. Do not "fix" these
back by copying that skill's skeleton — the omissions are intentional.

- [ ] **No** `.viz-menu` hamburger, no `toggleMenu()`?
- [ ] **No** theme toggle / `cycleTheme()` / `.theme-dark` / `.theme-light`
      classes — this deck is a single designed light-paper theme with dark
      slide variants used as *editorial* contrast, not as a user setting?
- [ ] **No** PNG export, no `html-to-image` CDN script?
- [ ] **No** base64 `@font-face` data URI, unless the user explicitly asked
      for offline operation and was warned (see
      `font-and-bedrock-safety.md`)?

## Delivery

- [ ] Written with a **single** `Write` call (`Edit` for follow-ups, never a
      second `Write` to the same path)?
- [ ] **Zero** lines of the generated HTML appear in the chat response — no
      `<head>` excerpt, no `<style>` preview, no markup code block?
- [ ] Output path is the input's directory + basename with `.html`, unless
      the user specified a path?
- [ ] Opened with `xdg-open` (Linux/WSL) or `open` (macOS) — never
      `wslview`?
- [ ] Final reply is summary + `file://` URL + open-command line only?
