---
name: sh:check
description: >-
  Audit a shell script (`*.sh`) against the dotfiles quality bar derived from
  `git_worktree.sh` — the canonical reference implementation. Reports
  PASS/WARN/FAIL/N/A across 10 criteria covering POSIX hygiene, sourcing
  guards, naming, ZSH compatibility, help UX, UX-lib usage, input validation,
  verdict structure, and next-action hints. Use when the user says "check
  this shell script", "is my .sh file production-ready?", "audit this shell
  function", "/sh:check". Mirrors `skill:check` but for `.sh` files instead
  of `SKILL.md`. Do NOT use for SKILL.md (use `skill:check`) or AGENTS.md
  (use `agents-md:check`).
compatibility:
  tools: Read, Glob, Grep, Bash
---

# Shell Script Quality Auditor

## Help

If the argument is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No further checks.

## Step 1: Locate the File

- Argument given → audit that path. Reject if it doesn't exist or doesn't
  end in `.sh`/`.bash`/`.zsh` (warn but continue if the user insists).
- No argument → search the current directory for `*.sh` files. If exactly
  one is found, audit it. If multiple, list them and ask which one. If none,
  output a help hint pointing to `/sh:check path/to/file.sh`.

Record:
- `LINES` — `wc -l` of the target file
- `IS_SOURCED` — heuristic: file is sourced if it lives under
  `shell-common/functions/`, `bash/`, `zsh/`, or contains
  `case $- in *i*)` near the top. Otherwise treat as an executable script.

## Step 2: Run 10 Quality Checks

Read `references/checks.md` for the full criteria. Each check returns one of:

- **PASS** — meets the bar
- **WARN** — partial / minor issue
- **FAIL** — missing or violates rule
- **N/A** — not applicable for this file class (e.g. interactive guard on
  an executable script, ZSH guard on a bash-only script)

The 10 checks are split into two groups:

**Structure (1–5)**
1. Shebang + POSIX Hygiene
2. Interactive Guard
3. Section Anatomy
4. Naming Convention
5. ZSH Compat Guard

**UX Quality (6–10)**
6. Help Flag
7. UX Lib Usage
8. Input Validation
9. Verdict Output
10. Next-action Hint

Each check definition lists the concrete grep patterns / structural cues to
look for. Treat `git_worktree.sh` as the canonical example — when the
target file uses the same pattern, that check passes.

## Step 3: Output the Report

Read `references/report-template.md` for the exact format. The report has:

- File path + line count
- Two tables (Structure 1–5, UX 6–10) with PASS/WARN/FAIL/N/A + notes
- Score line: `X/10 checks passed (Y warnings, Z N/A)`
- **Verdict** — single-line classification: `EXCELLENT` / `GOOD` /
  `NEEDS WORK` / `POOR`. Computed from Score per the table in
  `references/report-template.md`.
- **Next Actions** — one bullet per WARN/FAIL with a concrete fix command
  or code snippet. Each bullet is anchored by `[<LEVEL> #N]` so the user
  can map back to the table.

Do NOT recommend changes for PASS or N/A rows. Do NOT add filler "looks
great!" prose — the table and Verdict speak for themselves.

## Constraints

- Read-only audit — never edit the target file.
- Quote actual file lines when describing problems in Next Actions.
- If a check needs a tool the environment lacks (e.g. no `grep`), report
  N/A with an explanatory note rather than failing silently.
- The canonical reference is `shell-common/functions/git_worktree.sh`. When
  in doubt about whether a pattern is "the right way", compare to it.
