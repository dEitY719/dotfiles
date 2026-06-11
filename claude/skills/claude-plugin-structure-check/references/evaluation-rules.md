# claude-plugin-structure-check: Evaluation Rules

Detailed mode detection and scoring logic.

## Mode Detection Algorithm

Detect the layout mode by the following priority order:

1. **CLI flag** — `--single` or `--mono` forces the mode; mutually exclusive
   (last wins if both given).
2. **`marketplace.json`** — inspect `plugins[].source` field:
   - `"./"` → `single`
   - `"./plugins/.."` → `mono`
3. **Filesystem fallback** — presence of a `plugins/` directory → `mono`;
   otherwise → `single`.
4. **Ambiguous** → defaults to `mono` (report header notes `(추정)`).

## Plugin Root + Skill Discovery

A **plugin root** is the directory holding `.claude-plugin/plugin.json` and `skills/`.

- `mono` mode → each `plugins/*/` directory is a plugin root.
- `single` mode → repo root `./` is the plugin root (exactly one).

**Skills** (both modes, dynamic — never hard-code names): `<root>/skills/*/`
→ each subdirectory is a skill of that plugin root.

Record the detected mode, plugin-root list, and skill list for the report
header and the per-skill recommended checks (R1/R2/R5).

## Evaluation Scoring Rules

For each item in `references/structure-spec.md`, assign exactly one of:

- **PASS** — present and valid.
- **WARN** — recommended item missing/violated (R1-R5 only).
- **FAIL** — mandatory item missing/invalid (M1-M6 only).
- **N/A** — the subject does not exist (e.g. a plugin with 0 skills → its
  R1/R2 are N/A, not FAIL).

## Per-Item Evaluation Details

### M1-M6 (Mandatory — FAIL if violated)

M2/M3/M4 check **paths** are mode-dependent (see the spec's per-mode M-grid);
IDs, counts, and validation logic are identical across modes. M5/M6 and
R1/R2/R5 are mode-independent — only the skill-discovery path is plugin-root
relative.

**JSON validity (M1, M3):** parse with `python3 -m json.tool` (or `jq`); a
parse error is FAIL, not WARN.

**Frontmatter validity (M4):** the SKILL.md must have both `name:` and
`description:` keys.

### R1-R5 (Recommended — WARN if violated)

**R3/R4/R5** use the heuristics defined in `references/structure-spec.md`.

**R5:** for each discovered skill `<s>`, grep `README.md` for both a
`skill-guides/<s>.html` and a `skill-output/<s>-usage.{html,md}` path string
(relative or Pages-absolute) — missing either → WARN; no skills → N/A.

## Summary Verdict Logic

- any FAIL → **FAIL**
- no FAIL but ≥1 WARN → **WARN**
- all PASS/N/A → **PASS**

Emit the next-action hint **only when** there is ≥1 FAIL or WARN.
