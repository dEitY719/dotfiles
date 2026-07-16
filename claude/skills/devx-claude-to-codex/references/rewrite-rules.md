# devx:claude-to-codex — Rewrite rules

Rewrite the target phase document for Codex using imperative instructions.
Prefer explicit, operational wording over descriptive wording. The
generated Codex documents must reduce ambiguity and avoid high-level
narrative.

Preserve, unchanged, from the source phase document:
1. The original intent.
2. Important dependencies and preconditions.
3. File paths and architecture references.

For each generated Codex document:
- clearly state the goal
- define exact files to create or modify
- specify the implementation scope, scoped to the current Codex slice
  (not the full source checklist)
- exclude unrelated work
- provide ordered implementation steps
- pull hidden assumptions into an explicit "Assumptions / Notes" section
- if the source includes uncertain protocol details or unverified
  schemas, mark them clearly and instruct Codex to implement
  conservatively
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
