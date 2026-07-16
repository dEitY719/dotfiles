# devx:claude-to-codex — Codex optimization and transformation rules

## Codex optimization rules

Rewrite the target phase document for Codex using imperative instructions.
Prefer explicit, operational wording over descriptive wording. The
generated Codex documents must reduce ambiguity and avoid high-level
narrative.

For each generated Codex document:
- clearly state the goal
- define exact files to create or modify
- specify the implementation scope
- exclude unrelated work
- provide ordered implementation steps
- identify assumptions and risks
- provide a concrete completion checklist
- include a Codex execution prompt block at the bottom

Prefer wording like:
- "Create ..."
- "Modify ..."
- "Register ..."
- "Do not ..."
- "Stop after ..."
- "Return a short summary of changed files and unresolved risks."

Do not preserve vague wording such as:
- "could support"
- "might later be used"
- "optionally add" unless the option is intentionally deferred
- narrative architecture commentary that does not help immediate
  implementation

## Document transformation rules

When transforming a Claude-authored phase document into a Codex document:

1. Preserve the original intent.
2. Preserve important dependencies and preconditions.
3. Preserve file paths and architecture references.
4. Convert explanatory design prose into implementation instructions.
5. Pull hidden assumptions into an explicit "Assumptions / Notes" section.
6. Convert broad checklists into scoped completion criteria for the
   specific Codex slice.
7. Remove or defer work that is out of scope for the current generated
   Codex document.
8. If the source includes uncertain protocol details or unverified
   schemas, mark them clearly and instruct Codex to implement
   conservatively.
