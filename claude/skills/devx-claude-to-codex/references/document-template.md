# devx:claude-to-codex — Generated document structure

Use this structure unless the user explicitly requests a different
layout.

## Title
Use the source phase title and add a Codex suffix.
Example:
`# Phase 03 — Session + Chat UI + SSE Streaming (Codex 01)`

## Goal
State the concrete implementation goal for this Codex document only.

## Inputs / References
List the documents that were used to derive this file. Include absolute
or repo-relative paths exactly as referenced by the user.

## Scope
List only the work included in this Codex document.

## Out of scope
List related work intentionally excluded from this Codex document.

## Files to create or modify
Use a flat bullet list of exact file paths. Mark each as `NEW` or
`MODIFY`.

## Implementation instructions
Provide an ordered list of imperative steps. Each step should be
actionable and implementation-oriented.

## Constraints
Include hard requirements and "do not do" rules. Examples:
- Do not refactor unrelated files.
- Do not implement speculative UX refinements.
- Do not invent missing API schema fields beyond safe placeholders.
- Stop after the listed files are updated.

## Assumptions / Notes
List uncertainties, especially around APIs, protocols, schemas, or
runtime behavior.

## Completion checklist
Use checkboxes and keep them specific to this Codex document.

## Codex prompt
At the very bottom, include a fenced text block containing a Codex-ready
execution prompt.

## Codex prompt block rules

Each generated document must end with:

```text
Implement this Codex task exactly as specified in this document.
Before making changes:
- Read AGENTS.md
- Read CLAUDE.md
- Read the referenced input documents listed above
Execution rules:
- Only modify the files listed in "Files to create or modify"
- Follow the implementation instructions in order
- Do not expand scope
- If an interface is uncertain, implement the safest minimal version and leave a clear note
- When finished, summarize changed files, key decisions, and unresolved risks
```

If the generated document is one slice of several, add:

```text
This is only one slice of the original phase. Do not implement work assigned to other codex documents.
```
