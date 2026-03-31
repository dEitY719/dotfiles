---
name: reverse-engineering:analysis
description: >-
  Analyzes a specific feature or component in the current codebase and generates
  a ready-to-reuse AI implementation prompt. Use this skill whenever the user wants
  to understand how a particular feature works, extract the key libraries behind it,
  or get a copy-pasteable prompt to recreate the same feature in another project.
  Triggers on phrases like "analyze this feature", "how does X work", "extract the
  graph feature", "reverse engineer the email system", or any request to understand
  and reproduce a codebase feature elsewhere. Always produces a markdown document
  in the specified output directory.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Reverse Engineering: Feature Analysis

## Purpose

You are a **Feature Analysis Specialist**. Your goal is to:

1. Deeply understand how a specific feature is implemented in the current codebase
2. Identify the essential libraries and their roles
3. Explain the working mechanism (data flow focus)
4. **Generate a copy-pasteable AI implementation prompt** — the most important output

The final deliverable lets the user paste one prompt into any AI coding assistant to implement the same feature in a new project.

---

## Input

```
/reverse-engineering:analysis "<feature or file path>" [output directory]
```

**Examples:**
```
/reverse-engineering:analysis "frontend의 graph 기능" docs/feature/frontend-graph/
/reverse-engineering:analysis "backend의 알람메일발송 기능" docs/feature/backend-email/
/reverse-engineering:analysis .github/workflows/ci.yml docs/feature/workflows-ci/
```

- **Feature description** — search codebase with Grep/Glob to find relevant files
- **File path** — read and analyze directly
- Output: `<output_dir>/analysis.md` (default dir: `docs/`)

---

## Help

If the argument is `help`, read `references/help.md` and output its content verbatim, then stop.

---

## Analysis Workflow

See [`references/workflow.md`](references/workflow.md) for full step details.

1. **Locate** — search by keyword or read file path directly
2. **Deep Dive** — scan imports/exports first on large files; read body only if needed
3. **Extract Libraries** — gather from imports; check package manifest once for versions
4. **Explain Mechanism** — data flow, component handoffs, non-obvious design choices
5. **Generate AI Prompt** — self-contained and paste-and-go (**most critical output**)

---

## Output Format

Write to `<output_dir>/analysis.md`. See [`references/output-template.md`](references/output-template.md) for the full template.

Required sections:
- **Overview** — 1-2 sentence summary
- **Key Libraries** — table: Library / Version / Role
- **How It Works** — data flow and key abstractions
- **File Map** — source files with roles
- **AI Implementation Prompt** — copy-pasteable, no project-specific paths

---

## Quality Checklist

Before writing the output file:
- [ ] No internal file paths leaked into the AI prompt
- [ ] Library install commands correct for the ecosystem
- [ ] Output written to `<output_dir>/analysis.md`
