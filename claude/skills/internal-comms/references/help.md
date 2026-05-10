# skill:internal-comms — Help

## Synopsis

```
/internal-comms <comms-type> [topic]
```

## Description

Write internal communications in the formats the company uses — 3P updates,
company newsletters, FAQ responses, status reports, leadership updates,
project updates, and incident reports. Loads the matching guideline file
from `examples/` and follows its formatting and tone rules.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<comms-type>` | Communication type: `3p`, `newsletter`, `faq`, `general`, etc. | Inferred from request |
| `[topic]` | Subject matter or source content for the comms. | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/internal-comms 3p "this week's progress on auth migration"
/internal-comms newsletter "Q2 launch recap"
/internal-comms faq "common questions about the new pricing"
```

## Stop conditions

- Communication type does not match any guideline in `examples/` — ask for clarification or pick `examples/general-comms.md`.
- Source material is missing — request the underlying notes / data before drafting.
