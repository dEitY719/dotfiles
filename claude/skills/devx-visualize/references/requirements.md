# devx-visualize: Critical Requirements

These requirements must be followed for every visualization.

[WARN] **EVALUATION FAILURE GUARANTEED WITHOUT THESE ELEMENTS.** Always start from [skeleton.md](skeleton.md).

1. **CSS Custom Properties:** Exact names required: `--bg, --surface, --surface-hover, --border, --text, --text-secondary, --accent, --accent-secondary, --positive, --negative, --warning`
2. **Utility Menu (MANDATORY):** `.viz-menu` with `.viz-menu-toggle`, `.viz-menu-dropdown`, download PNG (`downloadImage()`), print (`window.print()`), and html-to-image CDN script. See [menu.md](menu.md) for full implementation.
3. **Theme Classes (EVALUATION CRITICAL):** Define BOTH `.theme-light` and `.theme-dark` in stylesheet — class-based only, **never** `@media prefers-color-scheme`. See [design-system.md](design-system.md).
4. **Semantic HTML:** `<main id="main-content">`, multiple `<section>` elements, skip-to-content link.
5. **Chart.js (EVALUATION CRITICAL, charts only):** CDN before `</head>`, `Chart.defaults.animation = false;` immediately after, ChartManager pattern (preferred). See [chartjs-patterns.md](chartjs-patterns.md).
6. **Responsive Design:** No horizontal overflow at 375px. Font hierarchy: `h1 ≥ 3rem, h2 ≥ 2rem, h3 ≥ 1.5rem, body = 1rem`. See [sizing-rules.md](sizing-rules.md).
7. **Print & Accessibility:** `@media print`, `@media (prefers-reduced-motion: reduce)`, aria-labels on all interactive elements and charts.
8. **Entrance Animations (MANDATORY):** `.animate` classes or `data-reveal` — evaluation detects and requires animation presence. See [animations.md](animations.md) for patterns.
9. **JavaScript:** `cycleTheme()`, `toggleMenu()`, all top-level variables in the **generated HTML** use `var` (never `let`/`const` — avoids TDZ errors with CDN-loaded libraries).
10. **Bedrock-Safe Output (NON-NEGOTIABLE):** Deliver the generated HTML via the tool layer — a single `Write` for the file body (plus `Edit` follow-ups for ≥1 000-line outputs per the Size-Aware Strategy), never a second `Write` to the same path. **Never echo the HTML body — full or partial — into the chat response.** Reply with summary + `file://` URL + open command only, no inline code block of the markup. This avoids the AWS Bedrock `API Error: Truncated event message received` failure (issue #690) and is harmless on the Anthropic-direct path. Full rules and size thresholds in [bedrock-safe-write.md](bedrock-safe-write.md).
