# Pre-Flight Checklist — Verify before outputting any visualization

Run through every item before delivering the HTML file.

## Theme & CSS

- [ ] `html.theme-dark` and `html.theme-light` class-based theme selectors defined (NO `@media prefers-color-scheme`)?
- [ ] JS detects OS preference on first visit, stores in `localStorage`?
- [ ] All text uses `var(--text)` or `var(--text-secondary)`?
- [ ] Hero/title text visible on BOTH dark (`#030712`) and light (`#f8fafc`) backgrounds?
- [ ] Correct font loaded? (Inter default, Noto Sans KR for Korean content, etc.)
- [ ] Non-Latin content has appropriate CJK/RTL font?

## Layout & Responsiveness

- [ ] No horizontal overflow at 375px viewport width?
- [ ] `@media print` hides menu, shows all content?
- [ ] `@media (prefers-reduced-motion: reduce)` present?
- [ ] Minimum sizing rules followed — cards ≥280px, body text ≥16px, sections ≥48px spacing? (see [sizing-rules.md](sizing-rules.md))

## Menu & Interactions

- [ ] `.viz-menu` with toggle, theme, download PNG, print buttons present?
- [ ] `.card:hover` has shadow effect (NO translateY/scale transforms — shadow only)?
- [ ] At least ONE meaningful interaction beyond theme toggle + menu?

## Animations

- [ ] Entrance animations via `.animate` classes (CSS @keyframes)?
- [ ] Scroll sections use `data-reveal` (content visible without JS)?
- [ ] Animated number counters use `data-count` where stats exist?

## JavaScript

- [ ] All top-level JS variables use `var` (not `let`/`const`)?
- [ ] `cycleTheme()` function exists and changes html class?
- [ ] `toggleMenu()` function exists and closes on outside clicks?

## Charts (if using Chart.js)

- [ ] Charts use `var` declarations + `onThemeChange` hook?
- [ ] All charts wrapped with `role="img" aria-label="..."`?
- [ ] All charts have hover tooltips enabled (never disabled)?
- [ ] All charts have explicit container sizing (≥300px height)?
- [ ] `Chart.defaults.animation = false;` set immediately after CDN?
- [ ] Zero console errors on load?

## Semantic HTML

- [ ] `<main>`, `<section>`, `<header>`, `<article>` used correctly?
- [ ] Skip-to-content link or landmark roles present?

---

## Anti-Patterns to Avoid

- ❌ Walls of text — if it reads like a document, it's not a visualization
- ❌ Tiny fonts — minimum 1rem (16px) body, 20px+ for presentation headings
- ❌ Rainbow colors — stick to 2-3 colors from the palette + neutrals
- ❌ Placeholder content — never use "Lorem ipsum" or fake data when real context exists
- ❌ Over-engineering — simplest approach that looks stunning
- ❌ Cramped layouts — when in doubt, add more whitespace
- ❌ Generic design — each visualization should feel intentional, not templated
- ❌ Missing menu — every output needs the hamburger menu
- ❌ Broken print — always include `@media print` styles
- ❌ Static feeling — every file needs at least ONE meaningful interaction
