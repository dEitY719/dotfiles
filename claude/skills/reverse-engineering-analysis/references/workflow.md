# Analysis Workflow — Detailed Steps

## Step 1: Locate the Feature

If input is a **feature description**:
1. Search for relevant keywords using Grep and Glob
2. Identify core files: entry points, components, services, utilities
3. Prioritize by relevance — focus on the heart of the feature, not peripheral code
   - A "graph feature" might span `components/`, `hooks/`, `services/`, and `types/`

If input is a **file path**:
1. Read the file directly
2. Identify what it does and what it depends on

## Step 2: Deep Dive

For each core file identified:
- For large files (>200 lines), read imports and exported symbols first — read the full body only if implementation details are unclear
- Note: what it does, how data flows through it, which components/modules it interacts with

## Step 3: Extract Key Libraries

Scan imports from Step 2 and identify all external (non-project) libraries:
- Name and version — check the package manifest (package.json, pyproject.toml, requirements.txt, Cargo.toml, etc.) **once here**, not per-file
- Why it's used specifically (e.g., "supports SVG-based force layouts" not just "it's a graph library")
- Its role: rendering, data transformation, state management, etc.

## Step 4: Explain the Working Mechanism

Write 3–5 paragraphs or a numbered flow focused on **data flow and key abstractions**:
- What the feature does from the user's perspective
- How data flows from source to output (input → transform → render/response)
- Which components/modules hand off to each other and in what order
- Non-obvious design choices (e.g., why a specific pattern was chosen)

Keep it digestible — someone should understand the feature in 5 minutes, not read source code.

## Step 5: Generate the AI Implementation Prompt

**Most critical output.** Write a prompt another developer can paste into Claude Code, Cursor, Copilot, or any AI assistant to implement the same feature from scratch.

The prompt must:
- State the goal clearly
- List exact libraries with install commands
- Describe expected behavior and UI/UX
- Include data structure or API shape if relevant
- Mention key implementation patterns from the source
- Be phrased as a direct instruction (imperative, specific)

The prompt must NOT:
- Reference the original project name or internal file paths — abstract them (e.g., "a data transformation module" not "src/lib/graph-data.ts")
- Be vague or leave details to guesswork
- Require the user to fill in placeholders — paste-and-go only
