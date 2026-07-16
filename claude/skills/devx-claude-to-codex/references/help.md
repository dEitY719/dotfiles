# devx:claude-to-codex — Help

## Usage

This skill has no CLI flags — it triggers on natural-language requests
that name reference document(s) plus a target phase document, e.g.:

```
docs/ai/architecture.md, docs/ai/backend.md, docs/ai/phases/phase-02-x.md를
참조해서 phase-02-x 문서를 codex에서 작업하기 최적화된 설계문서로 변경해줘

phase-03 문서를 codex용으로 재구성해줘

이 phase 문서를 codex-friendly task 문서로 필요하면 분할해서 만들어줘
```

## What it does

1. Reads the named reference document(s), then the target phase document.
2. Decides single vs. multi-document Codex output — see
   `references/output-and-split.md`.
3. Writes `docs/ai/phases/codex/<base>-codex-NN.md` (zero-padded from
   `01`; additional `-codex-02`, `-codex-03`, ... only appear when split).
4. Rewrites prose into imperative Codex instructions — see
   `references/rewrite-rules.md` and `references/document-template.md`.
5. Creates or updates `AGENTS.md` with `@CLAUDE.md` per
   `references/agents-md-handling.md`. Never rewrites `CLAUDE.md` itself.

## Output

Reports the created Codex document path(s), whether the phase stayed
single or was split, and whether `AGENTS.md` was created / updated /
left unchanged.
