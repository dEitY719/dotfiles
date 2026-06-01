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
| R5 | per-skill README guide+usage links | README missing the guide OR the usage link for a skill |

**R3 README "Simple" heuristic** — PASS only if all hold; any miss → WARN:
- at least one link into a `docs/` sub-document (evidence of progressive split);
- body not excessively long (guide: ≤ ~200 lines excluding code blocks);
- a skill-description section exists (mentions `plugins`/`skills`).

**R4 naming rule** — directory `claude-plugin-structure-check` ↔ frontmatter
`name: claude-plugin:structure-check`: the colon-namespace form maps to the
hyphen directory form. Mismatch → WARN (same rule as `devx:ai-context`
→ `devx-ai-context`).

**R5 per-skill README link rule** — for each discovered skill `<s>`,
`README.md` must contain **both**:
- a link to `skill-guides/<s>.html`, **and**
- a link to `skill-output/<s>-usage.{html,md}`.

Matching is by path-string presence in the README body — relative
(`skill-guides/<s>.html`) or Pages absolute URL both count. Any skill
missing either link → **WARN**. This pairs with R1/R2 (which check that
the files *exist*) to assert the files are *also actually surfaced* in the
README — completing the "standard" the developer relies on (see
`claude-plugin-visuals/README.md`). Reuses the Step 2 dynamic skill list,
so no extra scan. R3's "Simple" heuristic only requires *one* `docs/` link
anywhere, so it cannot catch a per-skill link gap — R5 does.

## N/A rule

When the subject of a check does not exist, the check is **N/A**, not FAIL.
Examples: a plugin with 0 skills → R1/R2/R5 are N/A for that plugin; with no
plugins at all M3 is N/A and with no skills anywhere M4 **and R5** are N/A —
M2 still carries the single "no plugins" FAIL, so the absent subject is never
double-counted as a second FAIL. R5 is per-skill: with no skills there is no
link to require, so it is N/A (never FAIL).

## Summary verdict

- any FAIL → **FAIL**
- no FAIL, any WARN → **WARN**
- all PASS/N/A → **PASS**
