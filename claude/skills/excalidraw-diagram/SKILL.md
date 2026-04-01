---
name: excalidraw-diagram
description: Create Excalidraw diagram JSON files that make visual arguments. Use when the user wants to visualize workflows, architectures, or concepts.
---

# Excalidraw Diagram Creator

Generate `.excalidraw` JSON files that **argue visually**, not just display information.

**Setup:** See `README.md` for renderer setup and dependencies.

## Customization

Read `references/color-palette.md` before generating any diagram — single source of truth for all colors and brand styles. Edit it to change your brand.

---

## Core Philosophy

**Diagrams should ARGUE, not DISPLAY.** The shape should BE the meaning.

- **Isomorphism Test**: Remove all text — does the structure alone communicate the concept?
- **Education Test**: Could someone learn something concrete, or does it just label boxes?

---

## Design Process

### Step 0: Assess Depth

Determine: **simple** (abstract shapes, mental models) or **comprehensive** (real systems, architecture)?

- Simple → abstract shapes, labels, relationships
- Comprehensive → read `references/evidence-and-research.md` for research mandate, evidence artifacts, and multi-zoom architecture

### Step 1: Understand Deeply

For each concept ask: What does it **DO**? What relationships exist? What's the core flow? What would someone need to **SEE**?

### Step 2: Map Concepts to Patterns

Read `references/visual-patterns.md` for the concept-to-pattern mapping table and full pattern library (fan-out, convergence, tree, timeline, spiral, cloud, assembly line, side-by-side, gap/break).

Each major concept must use a **different** visual pattern. No uniform cards or grids.

### Step 3: Sketch the Flow

Mentally trace how the eye moves through the diagram. There should be a clear visual story.

### Step 4: Generate JSON

Read `references/design-rules.md` for container discipline, color rules, aesthetics, layout, text rules, and JSON structure.

- `references/element-templates.md` — copy-paste JSON templates per element type
- `references/color-palette.md` — semantic color assignments
- `references/json-schema.md` — full JSON schema reference

For large/comprehensive diagrams → read `references/large-diagram-strategy.md` (build one section at a time, never generate entire diagram in one pass).

### Step 5: Render & Validate (MANDATORY)

Read `references/render-validate.md` for the full render-view-fix loop.

Quick reference:
```bash
cd .claude/skills/excalidraw-diagram/references && uv run python render_excalidraw.py <file.excalidraw>
```

Render → Read PNG → audit against vision → fix → repeat (2-4 iterations typical).

### Step 6: Final Quality Check

Read `references/quality-checklist.md` and verify all 27 items before delivering.
