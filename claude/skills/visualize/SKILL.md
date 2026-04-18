---
name: visualize
description: >-
  Create beautiful, self-contained HTML visualizations from any content or idea.
  Use for slide decks, presentations, infographics, dashboards, flowcharts,
  diagrams, timelines, comparison tables, data visualizations, landing pages,
  one-pagers, org charts, mind maps, process flows, kanban boards, report
  summaries, or any visual that helps humans digest information faster. Trigger
  on requests like "visualize this," "make a deck," "create a slide," "build an
  infographic," "show me a dashboard," "make this visual," or any request to
  present information in a visual HTML format.
license: MIT
metadata:
  author: careerhackeralex
  version: 0.3.2
  category: document-creation
  tags: [visualization, html, slides, dashboard, infographic]
---

# Visualize

Turn any idea, data, or content into a stunning single-file HTML visualization.

## After Creating a File

**Always do BOTH after writing the HTML file:**
1. **Auto-open:** `xdg-open <filename>.html` (Linux/WSL) · `open <filename>.html` (macOS). **Do NOT use `wslview`** — it frequently errors on HTML files; `xdg-open` works reliably on WSL.
2. **Return URL:** Include `file://<absolute-path>` in response

Example: `Created your visualization! 📄 file:///home/user/project/output.html`

## Critical Requirements (NON-NEGOTIABLE)

⚠️ **EVALUATION FAILURE GUARANTEED WITHOUT THESE ELEMENTS.** Always start from [references/skeleton.md](references/skeleton.md).

1. **CSS Custom Properties:** Exact names required: `--bg, --surface, --surface-hover, --border, --text, --text-secondary, --accent, --accent-secondary, --positive, --negative, --warning`
2. **Utility Menu (MANDATORY):** `.viz-menu` with `.viz-menu-toggle`, `.viz-menu-dropdown`, download PNG (`downloadImage()`), print (`window.print()`), and html-to-image CDN script. See [references/menu.md](references/menu.md) for full implementation.
3. **Theme Classes (EVALUATION CRITICAL):** Define BOTH `.theme-light` and `.theme-dark` in stylesheet — class-based only, **never** `@media prefers-color-scheme`. See [references/design-system.md](references/design-system.md).
4. **Semantic HTML:** `<main id="main-content">`, multiple `<section>` elements, skip-to-content link.
5. **Chart.js (EVALUATION CRITICAL, charts only):** CDN before `</head>`, `Chart.defaults.animation = false;` immediately after, ChartManager pattern (preferred). See [references/chartjs-patterns.md](references/chartjs-patterns.md).
6. **Responsive Design:** No horizontal overflow at 375px. Font hierarchy: `h1 ≥ 3rem, h2 ≥ 2rem, h3 ≥ 1.5rem, body = 1rem`. See [references/sizing-rules.md](references/sizing-rules.md).
7. **Print & Accessibility:** `@media print`, `@media (prefers-reduced-motion: reduce)`, aria-labels on all interactive elements and charts.
8. **Entrance Animations (MANDATORY):** `.animate` classes or `data-reveal` — evaluation detects and requires animation presence. See [references/animations.md](references/animations.md) for patterns.
9. **JavaScript:** `cycleTheme()`, `toggleMenu()`, all top-level variables in the **generated HTML** use `var` (never `let`/`const` — avoids TDZ errors with CDN-loaded libraries).

🔥 **Copy skeleton → Replace "YOUR CONTENT HERE" → Save file.**

## Core Principles

1. **Single-file HTML** — one `.html` file, inline CSS/JS, opens anywhere, works offline.
2. **Light theme optimized** — modern designs prioritize light mode. Dark available via toggle.
3. **Beautiful by default** — first output looks professional with zero iteration.
4. **Content-first** — visualization serves the message. Never sacrifice clarity for aesthetics.
5. **Responsive** — works on desktop, tablet, mobile unless explicitly fixed-dimension.
6. **Visual restraint** — no floating gradient orbs, rainbow borders, or ornamental animations.

## Output Rules

Start from [references/skeleton.md](references/skeleton.md) — **NEVER write HTML from scratch.**

- Write ONE `.html` file. Path rules:
  1. **File input** (`/visualize /path/abc.md`) → same dir, same basename, `.html` extension
  2. **No file input** → `~/Downloads/` with descriptive kebab-case name
  3. **User-specified path** → always honor it
- For Reveal.js nav pattern and full CDN library list, see [references/libraries.md](references/libraries.md).
- SVG for icons and simple graphics — never external image URLs unless user provides them.

## Design System

Full specs in [references/design-system.md](references/design-system.md) (typography, color, spacing, animation, accessibility) and [references/css-techniques.md](references/css-techniques.md) (advanced CSS, glass morphism, scroll techniques).

Key: Inter font mandatory, class-based theming only, `--bg/--surface/--text/--accent/--border` minimum CSS vars.

## Visualization Types

Choose the right format. For detailed structural patterns, see [references/types.md](references/types.md).
For type-specific rules (Carousel, Slide Deck, Poster, Auto-Recommend workflow, interactivity requirements, layout variation), see [references/type-rules.md](references/type-rules.md).

When user provides content **without specifying format**: analyze → recommend 1-2 formats → wait for confirmation. See type-rules.md for the content-to-type mapping table.

## Context Awareness

This skill runs mid-conversation. Use all available context: conversation history, URLs (crawl + extract), pasted data (CSV/JSON → charts), code/architecture (→ system diagrams). Always use real content — never placeholder data.

## Process

1. **Understand** — message, audience, format. If format unclear, run Auto-Recommend from [references/type-rules.md](references/type-rules.md).
2. **Start from skeleton** — [references/skeleton.md](references/skeleton.md). NEVER start blank.
3. **Structure** — outline sections before filling the skeleton.
4. **Build** — add content, charts, styles. All colors as CSS vars.
5. **Verify** — run [references/checklist.md](references/checklist.md) before outputting.

Chart.js patterns → [references/chartjs-patterns.md](references/chartjs-patterns.md) | Debugging → [references/debugging.md](references/debugging.md)
