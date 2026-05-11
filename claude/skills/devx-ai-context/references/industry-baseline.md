# AI Context Doc — Industry Baseline

This baseline is the source of truth for every adapter check in
`checks.md` that cites a tool-specific spec.

**Snapshot date:** 2026-05-11.
Refresh this file (and bump the snapshot date) whenever any of the linked
docs change material requirements.

---

## Source documents

| Tool         | Doc                                                                 |
|--------------|---------------------------------------------------------------------|
| OpenAI Codex | <https://developers.openai.com/codex/guides/agents-md>              |
| Claude Code  | <https://code.claude.com/docs/en/memory>                            |
| Gemini CLI   | <https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html>|

---

## Common ground (intersection)

All three tools agree on the following baseline behavior. These
properties are encoded as core checks `C1`–`C7`.

- A single canonical context file at the project root, plus an optional
  nested-file override mechanism scoped to subdirectories.
- The file is plain text / Markdown, loaded into the model context at
  session start.
- The file should remain small enough to fit comfortably within the system
  prompt budget (sub-section "Size / Context Budget").
- The file declares project purpose, operational commands, and constraints
  in named sections.
- Naming and file-organisation rules belong in this file when they are
  non-obvious.

---

## Tool-specific deltas

### OpenAI Codex (AGENTS.md)

- Discovery walks up from the working directory; first-match-wins per
  directory scope. Nested AGENTS.md overrides root for files inside that
  subtree.
- Codex publishes a payload cap on the merged AGENTS.md material; keep
  combined root + nested under it (see source).
- Codex prefers list-formatted Context Maps for directory routing. Tables
  hurt readability of routing entries.

Encoded as: `A-AG1` Discovery, `A-AG2` Override / fallback,
`A-AG3` Payload budget, `A-AG4` Context Map.

### Claude Code (CLAUDE.md)

- Pairs with `CLAUDE.local.md` (untracked) and `.claude/rules/` (rule
  files referenced from CLAUDE.md).
- Permission tiers and tool allow-lists belong here when the file
  orchestrates agents (vs. plain project context). The spec recommends
  classifying every action as `read-only`, `execute`, or
  `auto_after_approval` / `always_draft`.
- Recommends *thin orchestrator* — route, do not embed.

Encoded as: `A-CL1` Reference-by-path, `A-CL2` Permission Control,
`A-CL3` Thin Orchestrator, `A-CL4` Local + rules layout.

### Gemini CLI (GEMINI.md)

- Layered hierarchy: `~/.gemini/GEMINI.md` (global) + workspace +
  project. The CLI merges them in that order.
- `/memory` command is the supported edit path; the file may also import
  other files via Gemini's import directive.
- `.geminiignore` excludes paths from the session context.

Encoded as: `A-GE1` Hierarchy, `A-GE2` `/memory` & imports,
`A-GE3` `.geminiignore`.

---

## How to extend the baseline

When a fourth tool ships its own context-injection convention:

1. Add a row to *Source documents* with the official URL.
2. Add a *Tool-specific deltas* subsection summarising what is unique.
3. Add an `adapter <kind>` block to `checks.md` with the new checks
   prefixed `A-<KIND>N` (e.g. `A-CO1` for "copilot").
4. Bump the **Snapshot date** at the top of this file.

---

## Citation pattern

When a check report cites a baseline rule, use:

```
A-CL2 — Claude Code spec requires permission tiers covering external
side effects (industry-baseline.md, snapshot 2026-05-11).
```

This keeps the report auditable: the reader can re-derive the rule from
the cited snapshot of the official doc.
