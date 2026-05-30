# claude-plugin Standard Structure — spec SSOT (embedded copy)

Standard directory layout for a **claude-plugin marketplace repo** (e.g.
`claude-plugin-visuals`). This file is an intentional copy of the design
SSOT (`docs/feature/superpowers-specs/2026-05-30-claude-plugin-structure-skills-design.md`)
so each skill installs independently. Keep both copies in sync when the
spec changes.

`structure-check` evaluates against it (read-only). `structure-refactor`
edits a repo toward it (dry-run / `--apply`). Plugins and skills are
discovered **dynamically** by directory scan — the spec is abstract, never
repo-specific.

## Golden layout

```
.
├── .claude-plugin/marketplace.json      # exists + valid JSON       (M1)
├── plugins/<plugin>/
│   ├── .claude-plugin/plugin.json       # exists + valid JSON       (M3)
│   └── skills/<skill>/SKILL.md          # exists + name/description (M4)
├── docs/skill-guides/                   # directory exists          (M5)
├── docs/skill-output/                   # directory exists          (M5)
└── README.md                            # exists                    (M6)
```

Dynamic discovery order:
1. `plugins/*/` → each is a plugin.
2. `plugins/*/skills/*/` → each is a skill of that plugin.

## Mandatory items (FAIL when missing)

| ID | Item | FAIL condition |
|----|------|----------------|
| M1 | `.claude-plugin/marketplace.json` | missing or invalid JSON |
| M2 | `plugins/` dir with ≥1 plugin | missing or 0 plugins |
| M3 | each `plugins/<p>/.claude-plugin/plugin.json` | missing or invalid JSON |
| M4 | each `plugins/<p>/skills/<s>/SKILL.md` | missing or frontmatter lacks `name`/`description` |
| M5 | `docs/skill-guides/` AND `docs/skill-output/` | either directory missing |
| M6 | `README.md` | missing |

## Recommended items (WARN when missing)

| ID | Item | WARN condition |
|----|------|----------------|
| R1 | per-skill `docs/skill-guides/<skill>.html` | that file missing |
| R2 | per-skill `docs/skill-output/<skill>-usage.{html,md}` | both missing |
| R3 | README is "Simple" | heuristic violated (below) |
| R4 | naming consistency | SKILL.md `name:` colon-namespace ↔ directory hyphen mismatch |

**R3 README "Simple" heuristic** — PASS only if all hold; any miss → WARN:
- at least one link into a `docs/` sub-document (evidence of progressive split);
- body not excessively long (guide: ≤ ~200 lines excluding code blocks);
- a skill-description section exists (mentions `plugins`/`skills`).

**R4 naming rule** — directory `claude-plugin-structure-check` ↔ frontmatter
`name: claude-plugin:structure-check`: the colon-namespace form maps to the
hyphen directory form. Mismatch → WARN (same rule as `devx:ai-context`
→ `devx-ai-context`).

## N/A rule

When the subject of a check does not exist, the check is **N/A**, not FAIL.
Examples: a plugin with 0 skills → R1/R2 are N/A for that plugin; with no
plugins at all M3 is N/A and with no skills anywhere M4 is N/A — M2 still
carries the single "no plugins" FAIL, so the absent subject is never
double-counted as a second FAIL.

## Summary verdict

- any FAIL → **FAIL**
- no FAIL, any WARN → **WARN**
- all PASS/N/A → **PASS**
