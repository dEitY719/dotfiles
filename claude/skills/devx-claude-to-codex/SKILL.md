---
name: devx:claude-to-codex
description: >-
  Transform detailed phase implementation documents authored with Claude
  Opus into Codex-optimized implementation documents. Use when the user
  provides one or more reference documents plus a phase document and asks
  to convert, split, rewrite, or optimize that phase document for Codex
  execution inside a real project — e.g. "docs/ai/architecture.md,
  docs/ai/backend.md, docs/ai/phases/phase-02-x.md를 참조해서
  phase-02-x 문서를 codex에서 작업하기 최적화된 설계문서로 변경해줘",
  "phase-03 문서를 codex용으로 재구성해줘", "이 phase 문서를 codex-friendly
  task 문서로 필요하면 분할해서 만들어줘". Also use when the user wants
  codex-ready task documents, imperative implementation specs, or derived
  Codex documents under docs/ai/phases/codex/.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "phase-doc → imperative Codex-doc rewrite; split-boundary judgment; structured reasoning, no direct code execution"
    claude: prefer
    non_claude: advisory-only
---

# Purpose

Convert Claude-authored phase implementation documents into Codex-friendly,
imperative implementation documents. Preserve the original phase document —
never edit it. Generate derived documents under `docs/ai/phases/codex/`.
Treat `CLAUDE.md` as the source of truth and `AGENTS.md` as a thin bridge
for Codex. Never rewrite `CLAUDE.md` itself unless the user explicitly asks.

## Help

If the user asks for help/usage, read `references/help.md` and output its
content verbatim, then stop. No API calls, no file mutation.

## Step 1: Read Inputs

Read every reference document the user listed, then the target phase
document. Scan repo structure (`AGENTS.md`, `CLAUDE.md`) for context the
transformed document should preserve.

## Step 2: Decide Single vs Split

Evaluate whether the phase document is already narrow and deterministic
enough for one Codex pass. Default to a single output document — do not
split by default. Split into multiple numbered documents only when a
trigger condition in `references/output-and-split.md` is met; follow that
file's split-axis guidance (backend/frontend/shared,
transport/state/UI, infrastructure/integration/UX, deterministic-first/
uncertain-later) and prefer the minimum number of documents needed.

## Step 3: Write the Output File(s)

Naming and path rules (zero-padded `-codex-NN` suffix, base filename
preservation, `docs/ai/phases/codex/` target dir): see
`references/output-and-split.md`. Rewrite descriptive prose into imperative
instructions and strip vague/deferred wording per
`references/rewrite-rules.md`. Structure each generated document — Title,
Goal, Inputs/References, Scope, Out of scope, Files to create or modify,
Implementation instructions, Constraints, Assumptions/Notes, Completion
checklist, and the closing Codex prompt block (plus the multi-slice notice
when splitting) — exactly per `references/document-template.md`.

## Step 4: Sync AGENTS.md

Apply the three-way branch (missing / has `@CLAUDE.md` / missing
`@CLAUDE.md`) in `references/agents-md-handling.md`. Do not add extra
Codex policy text to `AGENTS.md` unless the user explicitly requests it.

## Quality bar

- Codex can execute from the generated document alone, without the
  original long phase spec open at all times.
- Implementation scope and the file list are unambiguous; mixed
  responsibilities are separated only when it genuinely helps reliability.
- Output stays faithful to the original Claude-authored intent — these are
  practical implementation documents, not summaries.

## Step 5: Report

Print a concise verdict, then keep any remaining chat response short:

```
[OK] devx:claude-to-codex — <n> Codex document(s) written
  docs/ai/phases/codex/<base>-codex-01.md (single|slice 1/<n>)
  ...
  AGENTS.md: created | updated (@CLAUDE.md added) | unchanged
```

Next: hand the printed Codex prompt block(s) to Codex.
