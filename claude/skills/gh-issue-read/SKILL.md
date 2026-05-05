---
name: gh:issue-read
description: >-
  Fetch a GitHub issue by number and print a structured, human-readable
  summary without modifying it. Use when the user runs /gh:issue-read,
  /gh-issue-read, or asks "이슈 #N 읽고 정리해줘", "issue 42 뭐하는 거야",
  "#16 요약", "이 이슈 내용 파악". Preserves body and comments verbatim
  so the output can be reused as context for implementation work. Accepts
  `<issue-number> [remote]`; defaults remote to `origin`. Accepts
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:issue-read — Issue Summary

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Fetch a single GitHub issue and print a structured summary. Read-only —
never mutate the issue. Preserve body + comments verbatim so the output
feeds downstream skills (like `gh:issue-implement`).

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Positional args: `<issue-number> [remote]`.

- `issue-number` — required, positive integer. Missing/invalid → print
  usage pointer (`Run /gh-issue-read -h for usage.`) and stop.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` via
  `git remote get-url <remote>`. Missing remote → list `git remote -v`
  and stop.

Substeps and error templates in `references/repo-resolution.md`.

## Step 2: Fetch Issue

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,author,labels,state,stateReason,\
  comments,assignees,createdAt,updatedAt,url
```

On error (issue not found, auth failure), print `gh` stderr verbatim
and stop — do not attempt fallback.

## Step 3: Format Output

Assemble the output per `references/output-format.md`. Sections:
Header → Summary → Body → Discussion → Meta → Checklist.

- **Body** and **Discussion** are verbatim. Do NOT compress, do NOT
  rewrap, do NOT translate.
- **Summary** is your 2-4 line extraction of the ask.
- **Checklist** pulls every `- [ ]` / `- [x]` line from body + comments.
- Match the user's conversation language for section headers
  (`Summary` vs `요약` etc.) but keep content verbatim.

## Step 4: Report

Print the formatted output directly. No preamble ("Here's the issue..."),
no trailing summary ("Let me know if you want..."). The output IS the
deliverable.

After the formatted output, append the ai-metrics line (stdout only —
this skill never mutates GitHub):

```
[ai-metrics:gh-issue-read] 🤖 ~{ELAPSED} min (read-only — not written to GitHub)
```

Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))` just before printing.

## Constraints

- Read-only — never call `gh issue edit`, `close`, or `comment`.
- Never fall back to `origin` when a non-existent remote is passed.
- Never truncate or paraphrase body/comments — the point is preservation.
- Never assume English; match the issue's language in body/comments and
  the user's conversation language for section headers.
