# Step 1..6 detailed instructions

The workflow has 6 sequential steps. Each step MUST complete with `[OK]`
before the next runs. On any `[FAIL]`, the chain stops — do not skip
forward, do not retry silently.

## Step 1 — Gather (always)

Analyze the conversation to extract:

1. **Problem Statement**: What failed? When? How discovered?
2. **Error Messages**: Exact errors, error codes, symptoms.
3. **Root Cause**: Why did it happen? (technical depth)
4. **Solution Applied**: What fixed it? Step by step.
5. **Learning Insights**: Key principles, patterns, anti-patterns.
6. **Prevention**: How to avoid in future?
7. **Related Issues**: Similar problems / edge cases.

Output: a short summary of the extracted elements before proceeding to
Step 2. If any of (1), (3), (4) cannot be extracted, stop with
`[FAIL] write-rca — Step 1: missing <problem|root-cause|solution>`.

Pre-flight checklist run inside Step 1:

1. **Analyze conversation** — extract problem, solution, learning.
2. **Identify audiences** — which of the four will benefit most?
3. **Define scope** — single issue vs broader pattern?
4. **Generate slug** — date + descriptive term
   (e.g. `2026-05-11-mapfile-compatibility`).
5. **Plan structure** — which sections are most critical?

## Step 2 — Draft (always)

Create `${RCA_REPO_PATH:-~/para/archive/rca-knowledge}/docs/analysis/YYYY-MM-DD-{slug}.md`
with the YAML frontmatter + 9 sections defined in
`references/document-template.md`.

Conditional media: place images / diagrams in
`${RCA_REPO_PATH}/_assets/{slug}-{purpose}.{ext}` and reference them via the
relative path `![alt](_assets/{slug}-diagram.png)`.

If the conversation lacks critical info for a section:

- Mark the section as `[TODO]`.
- Add clarifying questions in an HTML comment.
- Proceed with available context — do not block the whole document.

If root cause is ambiguous:

- Propose the most likely cause as primary.
- List alternative hypotheses below.
- Recommend further investigation.

## Step 3 — Validate (always)

Run three check passes against the drafted file. Each pass produces an
`[OK]` or `[FAIL]` line. Any `[FAIL]` halts the chain.

### Structure checks

- All 9 core sections present (or explicitly justified skips for §6).
- Executive Summary < 100 words.
- Markdown syntax valid.
- No undefined terminology.
- Code examples specify a language.

### Content checks

- Root Cause clearly stated.
- Solution reproducible (step-by-step).
- All four audiences addressed.
- YAML frontmatter parses.
- No confidential / sensitive info (unless `--private`).
- No emojis anywhere — status uses `[OK]` / `[FAIL]` or `yes` / `no`.

### Quality checks

- Tone consistent (professional yet accessible).
- Examples concrete, not generic.
- Prevention measures actionable.
- Links / references valid.
- Total length 1500–2500 words (flexible).

## Step 4 — Audience apply (always)

Apply the audience preset from `--audience` (default: all four). See
`references/audience-policies.md` for the rules per audience. Common
operations:

- **blog** — enhance narrative flow, add conclusion + CTA.
- **private** — redact secrets / hostnames / customer names; flag in
  frontmatter as `target_audiences: ["postmortem"]` only.
- **internal** — keep links to internal tooling intact.

## Step 5 — Commit (conditional on `--commit`)

If `--commit` was passed:

```bash
git -C "${RCA_REPO_PATH:-$HOME/para/archive/rca-knowledge}" add \
    "docs/analysis/YYYY-MM-DD-{slug}.md" "_assets/{slug}-"*
git -C "${RCA_REPO_PATH:-$HOME/para/archive/rca-knowledge}" commit \
    -m "docs(rca): {slug}"
```

If the repo path is not a git working tree, stop with
`[FAIL] write-rca — Step 5: $RCA_REPO_PATH is not a git repo`.

Do NOT push unless `RCA_AUTO_PUBLISH=true`. The user runs `git push` (or
sets `RCA_AUTO_PUBLISH=true` in their shell profile to opt in to automatic
publishing as part of Step 5).

## Step 6 — Report (always)

Read the success verdict block defined in `../SKILL.md` → `## Output`. Include:

- Output file path.
- Word count.
- Section completeness (`9/9` or `8/9 (§6 skipped)`).
- Audience applied.
- Next-action hint with concrete commands.
