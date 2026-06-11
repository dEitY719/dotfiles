---
name: write:rca
description: >-
  장애, 버그, 반복 실수에 대한 Root Cause Analysis 보고서 작성. Auto-document
  incidents, bug fixes, and technical challenges as structured markdown with
  root cause analysis, prevention checklists, and learning resources. Produces
  Jekyll-compatible publication-ready markdown (YAML frontmatter + single .md
  files) for postmortem review, technical blogging, AI tool training, and
  junior engineer onboarding. Saves to
  ${RCA_REPO_PATH:-~/para/archive/rca-knowledge} with centralized media in
  _assets/. (재사용 패턴 문서화는 write:insight, 작업 로그는 write:task-history)
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
metadata:
  model_recommendation:
    tier: sonnet
    reason: "structured 9-section RCA generation with 4-audience policy branching, validation, and conditional commit"
    claude: prefer
    non_claude: advisory-only
---

# write:rca

## Help

If args is `-h` / `--help` / `help`, read `references/help.md` verbatim and stop.

## Role & purpose

Transform technical incidents, bug fixes, and problem-solving conversations
into publication-ready markdown at
`${RCA_REPO_PATH:-~/para/archive/rca-knowledge}/docs/analysis/YYYY-MM-DD-{slug}.md`,
following a fixed 9-section template. One document serves four audiences:
postmortem review, technical blog, AI tool training, junior engineer onboarding.

## Trigger scenarios

Use when the user wants to record, document, or summarize:

- Production incidents and postmortems.
- Bug fixes with non-obvious root cause.
- Technical "삽질" stories worth preserving.
- Pattern-level failures spanning multiple modules.
- Anti-patterns discovered during code review.

## Options

See `references/options.md` for the full flag matrix (`--commit`,
`--audience <blog|private|internal>`, `--private`) and the `RCA_REPO_PATH`
environment variable that is the SSOT for the repository path.

## Workflow (stop on first failure)

Any Step that reports `[FAIL]` halts the chain — no retries, no partial
commits. Detailed instructions for each step live in
`references/phases-detail.md`.

1. **Step 1 — Gather**: interview / read source material; extract problem,
   root cause, solution, prevention. See `phases-detail.md` → Step 1.
2. **Step 2 — Draft**: apply the 9-section template from
   `references/document-template.md`; write to
   `${RCA_REPO_PATH}/docs/analysis/YYYY-MM-DD-{slug}.md`.
3. **Step 3 — Validate**: structure / content / quality checks. No emojis,
   sections in order, frontmatter parses, all four audiences addressed.
4. **Step 4 — Audience apply**: redact or enhance per `--audience`. See
   `references/audience-policies.md`.
5. **Step 5 — Commit (conditional)**: if `--commit`,
   `git -C "$RCA_REPO_PATH" add && commit`. Never pushes unless
   `RCA_AUTO_PUBLISH=true`. Requires the path to be a git working tree.
6. **Step 6 — Report**: read the verdict block in `## Output` with concrete
   next-action commands.

## Output

Success:

```
[OK] write-rca — <slug>.md written
  path: ${RCA_REPO_PATH}/docs/analysis/<year>-<mm>-<dd>-<slug>.md
  words: <n>
  sections: 9/9
  audience: <all-four|blog|private|internal>

Next: cat ${RCA_REPO_PATH}/docs/analysis/<year>-<mm>-<dd>-<slug>.md
Then: git -C "${RCA_REPO_PATH}" push  (if --commit was used)
```

Failure:

```
[FAIL] write-rca — Step <n>: <reason>
```

## SSOT — repository path

`$RCA_REPO_PATH` (default: `~/para/archive/rca-knowledge`) is the single
source of truth for every output path in this skill. Set it once in your
shell profile to override; every reference here resolves through it.

## References

- `references/help.md` (verbatim usage) · `references/document-template.md` (9-section spec + frontmatter) · `references/phases-detail.md` (Step 1..6 detail).
- `references/options.md` (flag matrix + `RCA_REPO_PATH` env-var SSOT) · `references/audience-policies.md` (blog/private/internal redaction) · `references/examples.md` (small/medium/large sizing).
