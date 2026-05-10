# skill:devx-excalidraw-diagram — Help

## Synopsis

```
/devx:excalidraw-diagram <topic-or-spec>
```

## Description

Create `.excalidraw` JSON files that make a visual argument about a workflow,
architecture, or concept — not just label boxes. Each major concept must use a
different visual pattern (fan-out, convergence, tree, timeline, etc.). Output
is rendered to PNG via the bundled `render_excalidraw.py` for validation.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<topic-or-spec>` | The concept, system, or workflow to visualize. | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/devx:excalidraw-diagram "OAuth refresh-token flow"
/devx:excalidraw-diagram "monorepo build graph for our 6 services"
/devx:excalidraw-diagram -h
```

## Stop conditions

- Topic is too vague to map onto a visual pattern — ask for clarification before generating JSON.
- Renderer dependencies (uv / Python) unavailable — surface setup steps from `README.md`.
