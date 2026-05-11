# Templates — devx:ai-context create

The `create` action picks one of these templates based on `--kind` and the
size discovered during `Phase 0`.

## agents (AGENTS.md)

| Size   | Heuristic                              | Template            |
|--------|----------------------------------------|---------------------|
| small  | < 20 files, single tech stack          | `agents-small.md`   |
| medium | 20–100 files, 2–3 tech domains         | `agents-medium.md`  |
| large  | 100+ files, multiple services          | `agents-large.md`   |

## claude (CLAUDE.md, orchestrator)

| Size     | Heuristic                  | Template             |
|----------|----------------------------|----------------------|
| simple   | 1–2 agents, single domain  | `claude-simple.md`   |
| standard | 3–6 agents, multi-domain   | `claude-standard.md` |
| large    | 7+ agents, enterprise      | `claude-large.md`    |

## gemini (GEMINI.md)

No native template yet. Use `agents-{size}.md` and adapt the front matter
to Gemini's hierarchy / import / `.geminiignore` model — see
`../industry-baseline.md` for the deltas.

When a Gemini-native template lands, add a `gemini-{size}.md` file here
and update this README.

---

These templates were lifted verbatim from the legacy skills
`agents-md:create` and `claude-md-create` so existing users see the same
output. Updates land here first; legacy locations stay frozen for the
shim period.
