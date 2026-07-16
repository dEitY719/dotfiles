# devx:claude-to-codex — Output location, naming, and split policy

## Output location and naming

Write generated files under:
`docs/ai/phases/codex/`

For an input phase file like:
`docs/ai/phases/phase-01-scaffold.md`

Generate:
- `docs/ai/phases/codex/phase-01-scaffold-codex-01.md`

If splitting is needed, continue numbering:
- `docs/ai/phases/codex/phase-01-scaffold-codex-02.md`
- `docs/ai/phases/codex/phase-01-scaffold-codex-03.md`

Always preserve the original base filename and append `-codex-XX`.
Use zero-padded numbering starting from `01`.

## Split policy

Do not split by default.

Generate only one Codex document when the source phase document is
already narrow, deterministic, and suitable for a single Codex
implementation pass.

Split into multiple Codex documents only when one or more of the
following are true:

- The scope spans multiple distinct responsibility domains (e.g.
  backend/frontend/shared, infra/UX, staged implementation slices) or
  would require Codex to touch many unrelated files or too many distinct
  concerns in one reliable pass.
- The phase depends on uncertain or unverified external interfaces.

When splitting, prefer coherent implementation boundaries over mechanical
equal sizing. Good split axes include:

- backend / frontend / shared
- transport / state / UI
- infrastructure / integration / UX refinement
- deterministic implementation first, uncertain integration later

Avoid unnecessary fragmentation. Prefer the minimum number of Codex
documents needed for reliable execution.
