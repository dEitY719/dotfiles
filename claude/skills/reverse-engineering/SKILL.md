---
name: reverse-engineering
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
3. Explain the working mechanism clearly and concisely
4. **Generate a copy-pasteable AI implementation prompt** — the most important output

The final deliverable is a markdown document that lets the user walk into any new project and immediately ask an AI coding assistant to implement the same feature.

---

## Input Parsing

The user invokes this skill with:
```
/reverse-engineering:analysis "<feature description or file path>" [output directory]
```

**Examples:**
```
/reverse-engineering:analysis "frontend의 graph 기능" docs/feature/frontend-graph/
/reverse-engineering:analysis "backend의 알람메일발송 기능" docs/feature/backend-email/
/reverse-engineering:analysis .github/workflows/ci.yml docs/feature/workflows-ci/
```

### Input types

- **Feature description** (e.g., `"frontend의 graph 기능"`) — use codebase search to find relevant files
- **File path** (e.g., `.github/workflows/ci.yml`) — analyze the specified file directly

### Output directory

- Default: `docs/` if not specified
- Create the directory if it doesn't exist
- Output filename: `analysis.md` inside the output directory

---

## Analysis Workflow

### Step 1: Locate the Feature

If input is a **feature description**:
1. Search for relevant keywords across the codebase using Grep and Glob
2. Identify the core files: entry points, components, services, utilities
3. Prioritize files by relevance — focus on the heart of the feature, not peripheral code

If input is a **file path**:
1. Read the file directly
2. Identify what it does and what it depends on

### Step 2: Deep Dive

For each core file identified:
- Read its contents
- Note: what it does, what it imports/requires, how data flows through it
- Track which external libraries (not project-internal) are being used

For configuration files (package.json, pyproject.toml, requirements.txt, etc.):
- Cross-reference to confirm library versions and dependencies related to the feature

### Step 3: Extract Key Libraries

For each essential library identified:
- Its name and version (if discoverable)
- Why it's used for this feature (not just "it's a graph library" but "it's used because it supports SVG-based force layouts")
- Its role in the implementation (rendering, data transformation, state management, etc.)

### Step 4: Explain the Working Mechanism

Write a concise explanation (3–5 paragraphs or a numbered flow):
- What the feature does from the user's perspective
- How data flows from source to output
- Which components/modules interact and in what order
- Any non-obvious design choices worth noting

Keep this section digestible — it should help someone understand the feature in 5 minutes, not replace the source code.

### Step 5: Generate the AI Implementation Prompt

**This is the most critical section.** Write a self-contained prompt that another developer can paste directly into Claude Code, Cursor, Copilot, or any AI coding assistant to implement the same feature from scratch.

The prompt must:
- State the goal clearly (what feature to implement)
- List the exact libraries to use (with install commands)
- Describe the expected behavior and UI/UX
- Include data structure or API shape if relevant
- Mention key implementation patterns observed in the source
- Be phrased as a direct instruction to an AI assistant (imperative, specific)

The prompt should NOT:
- Reference the original project name or file paths (it must work in any new project)
- Be vague or leave implementation details to guesswork
- Require the user to fill in placeholders — it should be paste-and-go

---

## Output Format

Write the result to `<output_directory>/analysis.md` using this exact structure:

```markdown
# [Feature Name] — Feature Analysis

## Overview
[1-2 sentence summary of what this feature does]

## Key Libraries

| Library | Version | Role |
|---------|---------|------|
| library-name | x.x.x | What it does in this feature |
| ... | ... | ... |

## How It Works

[3–5 paragraph or numbered flow explanation of the implementation mechanism]

## File Map

Key files involved in this feature:
- `path/to/file.ts` — [what it does]
- `path/to/service.py` — [what it does]
- ...

## AI Implementation Prompt

> Copy and paste this prompt into your AI coding assistant to implement this feature in a new project.

---

[START OF PROMPT]

I want to implement [feature name] in my [tech stack] project.

**Goal:** [Clear description of what the feature should do]

**Required libraries:**
- [library]: [install command] — [why this library]
- ...

**Expected behavior:**
- [behavior point 1]
- [behavior point 2]
- ...

**Implementation approach:**
[Key patterns and architecture decisions to follow]

**Data structure / API:**
[If applicable — describe input/output shape]

Please implement this step by step, starting with [entry point].

[END OF PROMPT]

---

## Notes
[Any caveats, version-specific behaviors, or things that were tricky to figure out]
```

---

## Quality Checklist

Before writing the final markdown, verify:
- [ ] All key libraries are identified (check imports, not just package files)
- [ ] The explanation covers the full data flow, not just one file
- [ ] The AI prompt is self-contained — someone with no knowledge of the original project can use it
- [ ] Library install commands are correct (npm install, pip install, cargo add, etc.)
- [ ] The output file is written to the correct directory

---

## Tips for Better Analysis

- When searching for a feature, look beyond the obvious directory. A "graph feature" might have rendering code in `components/`, data fetching in `hooks/` or `services/`, and type definitions in `types/`.
- Check `package.json`, `requirements.txt`, `Cargo.toml`, or equivalent to confirm which version of a library is used.
- If a file is very long, read the imports section and the exported functions/classes to understand its role without reading everything.
- For config files (CI/CD, Docker, etc.), explain both what the config does AND what tool knowledge is needed to replicate it.
