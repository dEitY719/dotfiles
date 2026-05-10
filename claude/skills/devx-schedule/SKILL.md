---
name: devx:schedule
description: >-
  [Claude Code Only] Schedule a skill or command to run after a specified
  delay (default: 5 min). Requires the `CronCreate` tool — does not work on
  Codex / Gemini CLIs. Use when the user says "N분 후에 /skill 실행해",
  "M분 뒤에 [skill] 수행해", "/devx:schedule", "/devx-schedule",
  "schedule /skill in N minutes", or "[command] N분 후에 해줘". Always invoke
  this skill whenever the user wants to defer any slash-command or task to
  run after a time delay.
---

# devx:schedule — Deferred Skill Executor

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

> **Claude Code only** — requires the `CronCreate` tool, which is part of the
> Claude Code harness. Other CLIs (Codex, Gemini, etc.) lack a comparable
> session-spawn scheduler, so this skill cannot run there.
> See [issue #362](https://github.com/dEitY719/dotfiles/issues/362).

## Usage

```
/devx:schedule [--time M] "<command>"
/devx:schedule [--time M] /skill-name [args...]
```

- `--time M` — delay in **minutes** (positive integer, default: **5**)
- `<command>` — skill invocation or natural-language task to run after the delay

## Examples

```
/devx:schedule --time 10 "/gh-pr-reply 350"      # /gh-pr-reply in 10 min
/devx:schedule /gh-pr-resolve-conflict 351        # run in 5 min (default)
/devx:schedule --time 3 "PR #200 리뷰 코멘트 처리해"
```

## Steps

### 1. Parse Arguments

Extract `--time M` (default 5) and the command/skill (everything after the flags).
If M is not a positive integer, default to 5 and warn the user.

| Input | M | command |
|-------|---|---------|
| `--time 10 "/gh-pr-reply 350"` | 10 | `/gh-pr-reply 350` |
| `/gh-pr-resolve-conflict 351` | 5 | `/gh-pr-resolve-conflict 351` |
| `--time 3 "PR 리뷰해"` | 3 | `PR 리뷰해` |

### 2. Calculate Fire Time

Run Bash to get the target cron fields in local time:

```bash
python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(minutes=M)).strftime('%M %H %d %m'))"
```

Replace `M` with the parsed minute value. Output: `<min> <hour> <dom> <month>`.

### 3. Schedule with `CronCreate`

Call `CronCreate`:
- `cron`: `"<min> <hour> <dom> <month> *"` (values from step 2)
- `prompt`: the extracted command (verbatim — passed to Claude at fire time)
- `recurring`: `false` (one-shot — fires once then auto-deletes)

### 4. Confirm to User

Print one line after scheduling:

```
[SCHEDULED] [M]분 후에 실행됩니다: <command>  (job: <returned-id>)
```
