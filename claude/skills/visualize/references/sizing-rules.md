# Sizing Rules — Minimum dimensions and text visibility requirements

## Minimum Sizing Rules

Elements must be large enough to read and feel substantial:

| Element | Minimum |
|---|---|
| Timeline cards | width 280px, padding 20px |
| Chart containers | 60% of parent width, height 300px (360px+ for dashboards) |
| Stat numbers | font-size 2rem (32px), bold/extrabold weight |
| Card content area | padding 24px |
| Section spacing | **48px between major sections** — use `margin-bottom: 48px` or larger |
| Slide headings | 2rem (32px) minimum, 6 words maximum |
| Body text | 1rem (16px) — never smaller |
| Mobile touch targets | 44px minimum |

**If content feels too small, it IS too small. Err on the side of larger.**

### Timeline Layout

Distribute timeline items evenly to prevent large gaps. If 5 items only fill 60% of vertical space, add content sections (investment breakdown, impact metrics) to fill remaining 40%. Never leave massive empty space below the last item.

### Chart Containers in Grid Layouts

Use `flex-grow: 1` so charts fill available space — 300px is a floor, not a target.

### Font Size Hierarchy (EVALUATION CRITICAL)

**MANDATORY descending scale — each level must be visibly smaller than the previous:**

| Level | Minimum | Notes |
|---|---|---|
| h1 | **3rem (48px)** | Slide deck title slides: ≥3rem |
| h2 | **2rem (32px)** | At least 0.5rem smaller than h1 |
| h3 | **1.5rem (24px)** | At least 0.5rem smaller than h2 |
| body | **1rem (16px)** | Never smaller |

Example valid hierarchy: h1: 3rem, h2: 2.5rem, h3: 1.5rem, body: 1rem.

**Font weight hierarchy (MANDATORY):**
- h1: ≥ 700 (bold)
- h2: ≥ 600 (semibold)
- h3: ≥ 500 (medium)
- body: 400 (regular)

---

## Text Visibility Rules

**Text must ALWAYS be visible.** This is the #1 cause of broken outputs.

- Dark theme: text MUST use `var(--text)` → resolves to ~`#f9fafb` (near-white)
- Light theme: text MUST use `var(--text)` → resolves to ~`#0f172a` (near-black)
- On gradient backgrounds: add `text-shadow: 0 1px 3px rgba(0,0,0,0.3)` for readability
- On hero slides with gradient/image backgrounds: use dark overlay `rgba(0,0,0,0.5)`
- **NEVER** set text color close to the background color
- Mental test: "Would this text be visible on BOTH dark (`#030712`) and light (`#f8fafc`) backgrounds?"

### Stat Value Colors

For stat value color semantics (which colors mean good/bad, KPI grid accent restraint), see [references/design-system.md](references/design-system.md) → "Accent Restraint Rules" section.
