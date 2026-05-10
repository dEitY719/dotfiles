# skill:devx-schedule — Help

## Synopsis

```
/devx:schedule [--time M] "<command>"
/devx:schedule [--time M] /skill-name [args...]
```

## Description

Schedule a skill or command to run after a specified delay using the
`CronCreate` tool. Claude Code only — Codex and Gemini CLIs lack a comparable
session-spawn scheduler.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `--time M` | Delay in minutes (positive integer). | `5` |
| `<command>` | Skill invocation or natural-language task to run after the delay. | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/devx:schedule --time 10 "/gh-pr-reply 350"
/devx:schedule /gh-pr-resolve-conflict 351
/devx:schedule --time 3 "PR #200 리뷰 코멘트 처리해"
```

## Stop conditions

- `CronCreate` tool is unavailable (non-Claude-Code harness) — refuse and explain.
- `--time` is not a positive integer — fall back to default `5` and warn the user.
