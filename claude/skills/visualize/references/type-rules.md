# Type-Specific Rules — Detailed requirements per visualization format

Load relevant sections based on the requested visualization type.

## Table of Contents
- [Auto-Recommend Workflow](#auto-recommend-workflow) — when user doesn't specify format
- [Carousel Cards](#carousel-cards)
- [Event Poster](#event-poster)
- [Quote Card](#quote-card)
- [Single-Screen / Fixed-Dimension](#single-screen--fixed-dimension) — posters, 9:16, 1:1
- [Slide Deck](#slide-deck)
- [Type-Specific Interactivity](#type-specific-interactivity) — required interactions per type
- [Layout Variation](#layout-variation) — grid, rhythm, density rules

---

## Auto-Recommend Workflow

When user provides content **without specifying a format**, do NOT pick silently. Instead:

1. **Read and analyze** — headings, lists, tables, data, narrative flow
2. **Recommend 1-2 best-fit types** with a one-line reason each
3. **Wait for confirmation** before building

### Content-to-Type Mapping

| Content Structure | 1st Recommendation | 2nd Recommendation |
|---|---|---|
| Headings + bullet lists (presentation-like) | **Slide Deck** — each heading becomes a slide | **Infographic** — long-scroll summary |
| Tables / comparison data | **Comparison Infographic** — side-by-side visual | **Dashboard** — if numeric-heavy |
| Chronological / dated entries | **Timeline** — alternating left/right | **Status Report** — if progress-oriented |
| KPIs / numbers / metrics | **Dashboard** — cards + charts | **Status Report** — executive summary |
| Step-by-step / how-to | **Process Guide** — numbered accordion | **Slide Deck** — one step per slide |
| Code snippets / commands | **Cheatsheet** — searchable + copy buttons | — |
| System design / components | **Architecture Diagram** — Mermaid + cards | **Slide Deck** — walkthrough |
| Key quotes / insights | **Quote Card** — hero quote layout | **Carousel** — one quote per card |
| Short summary for sharing | **Carousel Cards** — SNS-optimized | **One-Pager** — single viewport |
| Event / announcement | **Event Poster** — portrait, bold headline | **Slide Deck** — if multi-topic |
| Mixed / unclear | **Infographic** — versatile long-scroll | **Slide Deck** — universal fallback |

### Example Response

```
This document has 5 sections with bullet points and 2 data tables.

Recommended formats:
1. **Slide Deck** — 5 sections map cleanly to 7-8 slides with chart slides for the tables
2. **Infographic** — single long-scroll with big numbers and comparison sections

Which format would you prefer? (or just say "1" or "2")
```

**Skip recommendation and build immediately** when user specifies format: "make a dashboard", "visualize as slides", "carousel로 만들어".

---

## Carousel Cards

Carousel cards are huge for social media. Get these right:

- **Square format** — `1080×1080px` (or configurable via CSS var)
- **One idea per card** — bold headline + 1-2 supporting points max
- **Swipe nav** — arrows + dots + touch swipe + keyboard
- **Card counter** — "3 / 8" visible at all times
- **Download all** — PNG export of individual cards or full set
- **Typography dominates** — headline at 2.5-4rem, minimal body text
- **Color-coded** — each card can have a subtle accent shift
- **Print layout** — grid of all cards for printing
- **Max 10 cards** — keep it focused

---

## Event Poster

- **Portrait orientation** — A4/letter ratio or square
- **Visual hierarchy** — Event name (largest) → Date/Time → Location → Description → CTA
- **Bold headline** — 3-5rem, max 6 words
- **Date/time prominent** — styled as a badge or highlighted block
- **QR code area** — placeholder box for registration link
- **Print-first** — looks great printed, dark or light theme

---

## Quote Card

- **Large quotation marks** — decorative `"` `"` in accent color, oversized
- **Quote text** — 1.5-2.5rem, serif or italic weight for contrast
- **Attribution** — name, title, company below quote
- **Square or portrait** — optimized for social sharing
- **Minimal design** — quote is the hero, everything else is subtle

---

## Single-Screen / Fixed-Dimension

When user asks for "one screen," "phone screen," "9:16," or "mobile-fit," create a **fixed-dimension single-viewport** visualization — NOT a scrolling page.

### Dimensions

| Ratio | CSS |
|---|---|
| 9:16 portrait (phone / Instagram Story) | `width: 1080px; height: 1920px;` |
| 1:1 square (Instagram post) | `width: 1080px; height: 1080px;` |
| 4:5 portrait (Instagram portrait) | `width: 1080px; height: 1350px;` |
| 16:9 landscape (presentation slide) | `width: 1920px; height: 1080px;` |

### Critical CSS Pattern

```css
body {
  width: 1080px; height: 1920px; /* or chosen ratio */
  overflow: hidden;               /* MUST — enforces single screen */
  display: flex; flex-direction: column;
}
.poster-header { padding: 44px 48px 0; }
.poster-grid   { flex: 1; padding: 24px 48px 0; } /* flex:1 fills remaining space */
.poster-footer { padding: 16px 48px 36px; }
```

### Layout Rules

- `overflow: hidden` on body — non-negotiable
- `justify-content: space-between` — distributes sections with NO dead gaps
- `flex: 1` on main content area — never use fixed heights that leave dead space
- **Zero dead space rule:** poster canvas should be 100% utilized
- **No hamburger menu** — wastes space; poster is for screenshot/export
- **Test mentally:** count sections, divide total height. Each section gets ~200-300px. If sparse, make elements bigger.

### Font Sizing for 1080px-Wide Posters

- Hero h1: `68-80px` (this is a poster, not a webpage)
- Section labels: `15-18px` uppercase, `letter-spacing: 0.06em`
- Card text: `16-20px`
- Body: `20-24px`

### Content Density for 9:16

- Hero (title + subtitle): ~25% of height
- 2-3 content sections: ~55% of height
- Footer/CTA: ~10% of height
- Breathing room: ~10% of height

**Common mistake:** Making a scrolling page and screenshotting it. A poster is a fixed canvas where every pixel is intentional.

---

## Slide Deck

### Core Requirements

- **16:9 aspect ratio** — `100vw × 100vh`, content centered
- **One idea per slide** — if you need a second thought, make a second slide
- **Max 40 words per slide** — more than that, split or use visuals
- **Headlines max 6 words** — short, punchy, memorable
- **Big number + small label** for stat slides — number at 3-5rem, label at 0.875rem

### Navigation (Required)

- **Keyboard nav** — ← → arrows, Space, Enter
- **Touch nav** — swipe left/right
- **Click nav** — left third = prev, right two-thirds = next
- **Progress bar** — thin gradient bar at top showing position
- **Slide counter** — "3 / 12" in bottom nav
- **Smooth transitions** — `transform: translateX()` with 500ms cubic-bezier

### Responsive Breakpoints

```css
.slide-container { container-type: inline-size; }
.slide-title { font-size: clamp(2rem, 8vw, 4rem); }
@container (width < 768px) { .slide-content { padding: 1rem; } }
```

### Slide Types

1. **Title** — theme-aware gradient background, big headline, subtitle. Center aligned.
2. **Content** — heading + bullets OR heading + visual. Never text-heavy.
3. **Section divider** — full-bleed accent color, section title only.
4. **Stat** — one big number, one label, one insight sentence.
5. **Chart** — Chart.js visualization with title and key takeaway.
6. **Two-column** — split layout for comparisons, text+visual.
7. **Quote** — large pull quote with attribution.
8. **Closing** — CTA, contact info, or summary + social links.

### Theme-Aware Gradients (CRITICAL)

Slide decks MUST look visually distinct in dark vs light themes:

```css
/* Dark theme: deep, saturated gradients */
.theme-dark .slide-title {
  background: linear-gradient(135deg, #1e1b4b 0%, #312e81 50%, #1e3a5f 100%);
}

/* Light theme: soft, pastel gradients */
.theme-light .slide-title {
  background: linear-gradient(135deg, #e0e7ff 0%, #c7d2fe 50%, #dbeafe 100%);
}
```

Rules:
- Title/section slides: theme-specific gradient pairs. **Match colors to subject matter** — tech pitch uses cool blues, game pitch uses vibrant purples/cyans.
- Content slides: `var(--bg)` or `var(--surface)` — NOT hardcoded dark backgrounds
- Data cards: `var(--surface)` with `var(--border)` — auto-adapt
- **Never hardcode** `#1a1a2e` or similar on content slides

### High-Impact Presentation Slides (Business Context)

For investor presentations, startup pitches, executive briefings:
- Hero slide: stronger gradients, larger typography (4-6rem), compelling statistics
- Value proposition: communicate core value in under 5 seconds
- Data storytelling: each chart slide needs clear insight callouts, not just raw data

### Chart Slides

```html
<div class="chart-slide-container">
  <h2>Chart Title</h2>
  <div class="chart-container" style="height: 400px; padding: 40px; border-radius: 12px; background: var(--surface);">
    <canvas id="slideChart" role="img" aria-label="Description"></canvas>
  </div>
</div>
```
- Minimum height **400px** — larger than dashboard charts for readability
- `maintainAspectRatio: false` required

---

## Type-Specific Interactivity

Every file MUST have at least ONE meaningful interaction beyond theme toggle + menu.

| Type | Required Interaction |
|------|---------------------|
| **Cheatsheet** | Search/filter input + copy-to-clipboard on code blocks. Use `<details name="...">` for collapsible groups. |
| **Dashboard** | Filter toolbar or metric drill-down. At minimum: date range or category filter. |
| **Status Report** | Collapsible detail sections (`<details>`). Progress bars animate on scroll. |
| **Quote Card** | Auto-cycling quotes OR swipeable carousel. Share/copy button. |
| **Event Poster** | Animated countdown timer (days/hours/min/sec). RSVP/register button. |
| **Process Guide** | Steps as exclusive accordion (`<details name="steps">`). Or interactive progress tracker. |
| **Architecture** | Clickable nodes with popover details (Popover API). Hover highlights connections. |
| **Timeline** | Filter by era/category. Or click to expand event details. |
| **Comparison** | Toggle categories on/off. Or highlight winner per row. |
| **Carousel** | Touch swipe + keyboard + auto-advance option. Card counter always visible. |
| **Slide Deck** | Already interactive (nav). Add: presenter timer, slide overview grid. |

If a type isn't listed: add at minimum a filter, search, sort, or expand/collapse interaction.

---

## Layout Variation

Every file must feel like a UNIQUE design, not a template with different text.

### Mobile-First Responsive Pattern (MANDATORY)

```css
.grid {
  display: grid;
  gap: 24px;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
}
@media (max-width: 768px) {
  .grid { grid-template-columns: 1fr; gap: 16px; }
  .container { padding: 24px 16px; }
}
@media (max-width: 375px) {
  .card { padding: 16px; }
  .stat-value { font-size: 2rem; }
}
```

**CRITICAL: Always test at 768px and 375px — no horizontal overflow allowed.**

### Variation Principles

- **Grid structure:** Mix 1-col, 2-col, 3-col. Use CSS Grid `span 2` for featured cards.
- **Section rhythm:** Alternate between full-width sections, card grids, and single-focus sections.
- **Content density:** 8 KPI cards + 4 charts feels real; 4 KPI cards + 2 charts feels like a demo.
- **Visual focal point:** Every file needs ONE visually dominant element — not everything at equal weight.
- **No orphaned grid items:** Use `grid-column: span 2` on last item when grid has odd number of items.

### CSS Container Queries (Advanced Responsiveness)

```css
.chart-container { container-type: inline-size; }
@container (max-width: 400px) {
  .chart-legend { display: none; }
  .chart-title { font-size: 1rem; }
}
```
