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

## Layout modes

The official plugin spec allows two valid layouts. **`single` is the more
common one** in the wild (Superpowers, most OSS/personal plugins); `mono` is
the team standard (`anthropics/claude-code` bundles 13 plugins this way).

| | `mono` | `single` |
|---|---|---|
| marketplace `source` | `"./plugins/<name>"` | `"./"` |
| plugin roots | each `plugins/<p>/` | repo root `./` (exactly 1) |
| skill path | `plugins/<p>/skills/<s>/` | `skills/<s>/` |

A **plugin root** is the directory holding the plugin manifest
(`.claude-plugin/plugin.json`) and `skills/`. Defining M3/M4/R1/R2/R4/R5
over the *plugin-root set* makes them mode-agnostic — only "how the
plugin-root set is computed" differs between modes (Approach C, #914).

### Golden layout — mono

```
.
├── .claude-plugin/marketplace.json      # exists + valid JSON       (M1)
├── plugins/<plugin>/                     # plugin root
│   ├── .claude-plugin/plugin.json       # exists + valid JSON       (M3)
│   └── skills/<skill>/SKILL.md          # exists + name/description (M4)
├── docs/skill-guides/                   # directory exists          (M5)
├── docs/skill-output/                   # directory exists          (M5)
└── README.md                            # exists                    (M6)
```

### Golden layout — single

```
.                                         # repo root IS the plugin root
├── .claude-plugin/
│   ├── marketplace.json                 # exists + valid JSON, source "./" (M1)
│   └── plugin.json                      # exists + valid JSON       (M3)
├── skills/<skill>/SKILL.md              # exists + name/description (M4)
├── docs/skill-guides/                   # directory exists          (M5)
├── docs/skill-output/                   # directory exists          (M5)
└── README.md                            # exists                    (M6)
```

## Mode detection (priority order — first match wins)

1. **`--single` / `--mono` flag** → forced override (highest authority).
2. **`marketplace.json` `plugins[].source`** → `"./"` (or `"."`) ⇒ single,
   `"./plugins/.."` (or bare `"plugins/.."`) ⇒ mono — the leading `./` is
   optional, matched leniently (most authoritative *signal* when unflagged).
3. **Filesystem fallback** → `plugins/*/` exists ⇒ mono; root
   `.claude-plugin/plugin.json` exists ⇒ single.
4. **Still ambiguous** → default `mono`, header notes `(mode: mono, 추정)`.

A forced override is honored even when wrong — it means "score *as* this
mode". An invalid combo (e.g. `--mono` with no `plugins/`) then yields a
normal M2 FAIL, never a silent skip.

## Mandatory items by mode (FAIL when missing)

IDs, counts, and validation logic are identical across modes — only the
checked **path** changes (M5/M6 are mode-independent).

| ID | Item | mono path | single path |
|----|------|-----------|-------------|
| M1 | marketplace.json valid | `.claude-plugin/marketplace.json` | **same** |
| M2 | ≥1 plugin root | `plugins/` has ≥1 plugin | root `.claude-plugin/plugin.json` exists (=1 root) |
| M3 | each plugin.json valid | `plugins/<p>/.claude-plugin/plugin.json` | root `.claude-plugin/plugin.json` |
| M4 | each SKILL.md valid | `plugins/<p>/skills/<s>/SKILL.md` | `skills/<s>/SKILL.md` |
| M5 | docs dirs exist | `docs/skill-guides/` AND `docs/skill-output/` | **same** |
| M6 | README.md | `README.md` | **same** |

FAIL conditions: M1/M3 → missing or invalid JSON; M2 → 0 plugin roots;
M4 → missing or frontmatter lacks `name`/`description`; M5 → either dir
missing; M6 → missing.

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
**plugin roots** M3 is N/A and with no skills anywhere M4 **and R5** are N/A —
M2 still carries the single "no plugin root" FAIL, so the absent subject is
never double-counted as a second FAIL. This holds per mode: in `single` a
missing root `.claude-plugin/plugin.json` means 0 plugin roots, so M2 FAILs
and M3/M4 are N/A — exactly mirroring mono's "0 plugins" case. R5 is
per-skill: with no skills there is no link to require, so it is N/A (never
FAIL).

## Summary verdict

- any FAIL → **FAIL**
- no FAIL, any WARN → **WARN**
- all PASS/N/A → **PASS**
