# skill:devx-visualize — Help

## Synopsis

```
/devx:visualize [<file-or-content>]
```

## Description

Create beautiful, self-contained HTML visualizations from any content or idea.
Writes a single `.html` file, auto-opens it via `xdg-open` (Linux/WSL) or
`open` (macOS), and returns a `file://` URL.

Covers slide decks, presentations, infographics, dashboards, flowcharts,
diagrams, timelines, comparison tables, data visualizations, landing pages,
one-pagers, org charts, mind maps, process flows, kanban boards, report
summaries — any visual that helps humans digest information faster. Natural
triggers: "visualize this", "make a deck", "create a slide", "build an
infographic", "show me a dashboard", "make this visual", "이거 시각화해줘".

Not this skill: an `.excalidraw` file is `devx:excalidraw-diagram`; a vertical
scroll-snap deck built from a Markdown file is `devx:md-to-scrolldeck`.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<file-or-content>` | Path to a source file, pasted content, or a topic to visualize. | Use conversation context |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/devx:visualize /path/to/notes.md
/devx:visualize "Q2 product roadmap with 4 epics and 12 stories"
/devx:visualize -h
```

## Stop conditions

- Format is ambiguous — run the Auto-Recommend workflow (see `references/type-rules.md`) and wait for confirmation.
- Required skeleton (`references/skeleton.md`) cannot be loaded — surface the error before writing HTML.
