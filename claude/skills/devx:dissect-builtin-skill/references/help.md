# devx:dissect-builtin-skill — Help

## Synopsis

```
/devx:dissect-builtin-skill <skill-name>
```

## Description

Analyze a Claude Code built-in skill and produce structured Korean documentation.
Loads the target skill's prompt via the Skill tool, then writes `README.md`
(Korean analysis) and `PROMPT.md` (verbatim original prompt) into
`claude/built-in-skills/<skill-name>/`.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<skill-name>` | Name of the built-in skill to dissect (e.g. `simplify`, `loop`). | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/devx:dissect-builtin-skill simplify
/devx:dissect-builtin-skill loop
/devx:dissect-builtin-skill -h
```

## Stop conditions

- Target skill is not a built-in (Skill tool load fails) — inform the user and suggest alternatives.
- Output filename `SKILL.md` is requested — refuse (conflicts with Claude Code skill loading).
