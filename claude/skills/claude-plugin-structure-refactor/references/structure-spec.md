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
`structure-refactor` generates its create/`git mv`/skeleton/stub actions
over the *same plugin-root set*, so a single repo is fixed toward the
**root** golden layout and a mono repo toward the **plugins/** layout — the
mode is chosen once, never converted mid-refactor (see "Mode override =
layout conversion" below).

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

A forced override is honored even when wrong — it means "refactor *toward*
this mode's golden layout". When the override names a mode **different from
the detected current layout** that is a single↔mono *conversion*, which is
out of scope — see "Mode override = layout conversion".

## Mode override = layout conversion (out of scope — safety guard)

`structure-refactor` fixes a repo toward the golden layout **of its current
detected mode**. It never silently converts single↔mono:

- When the forced `--single`/`--mono` equals the detected current mode (or
  no flag is given), refactor proceeds normally over that mode's plugin-root
  set.
- When the forced mode **differs** from the detected current layout, fixing
  toward it would require relocating the whole plugin (single→mono: `git mv`
  the root plugin into `plugins/<name>/`, move `skills/`, rewrite
  `marketplace.json` source; mono→single: the inverse). This is a large,
  high-risk move + manifest rewrite and is **not performed**:
  - the dry-run plan prints a `[convert]` warning line ("레이아웃 변환 필요
    — 현재 미지원"), and
  - `--apply` **stops without writing** (fail-safe — never a partial move).

Conversion support is deferred to a follow-up (`structure-convert` or a
refactor `--convert` flag). This guard exists precisely so refactor never
force-restructures a valid `single` repo (e.g. Superpowers) into `mono` and
breaks upstream compatibility.

## Mandatory items by mode (FAIL when missing)

IDs, counts, and validation logic are identical across modes — only the
checked **path** changes (M5/M6 are mode-independent). Refactor's fix action
for each item targets the same path.

| ID | Item | mono path | single path |
|----|------|-----------|-------------|
| M1 | marketplace.json valid | `.claude-plugin/marketplace.json` | **same** |
| M2 | ≥1 plugin root | `plugins/` has ≥1 plugin | root `.claude-plugin/plugin.json` exists (=1 root) |
| M3 | each plugin.json valid | `plugins/<p>/.claude-plugin/plugin.json` | root `.claude-plugin/plugin.json` |
| M4 | each SKILL.md valid | `plugins/<p>/skills/<s>/SKILL.md` | `skills/<s>/SKILL.md` |
| M5 | docs dirs exist | `docs/skill-guides/` AND `docs/skill-output/` | **same** |
| M6 | README.md | `README.md` | **same** |
| M7 | each `plugins[]` element resolves to a source | `.claude-plugin/marketplace.json` | **same** |
| M8 | each source has a valid shape | `.claude-plugin/marketplace.json` | **same** |
| M9 | declared mono plugin dirs exist on disk | `plugins/<name>/` per source | N/A (single) |
| M10 | plugin.json has only known top-level fields | `plugins/<p>/.claude-plugin/plugin.json` | root `.claude-plugin/plugin.json` |

FAIL conditions: M1/M3 → missing or invalid JSON; M2 → 0 plugin roots;
M4 → missing or frontmatter lacks `name`/`description`; M5 → either dir
missing; M6 → missing; M7-M9 → see "marketplace source integrity" below;
M10 → see "plugin.json known fields" below.

## marketplace `plugins[].source` integrity (M7-M9, #1084)

Claude Code (observed on 2.1.198) does **not** inherit a marketplace top-level
`source` into a plugin at install time — each `plugins[]` element must carry
its own source, or `/plugin install` fails with *"This plugin uses a source
type your Claude Code version does not support"* (claude-plugin-jira#61). A
structure audit that stopped at M6 passed such a repo, which then misled the
diagnosis (claude-plugin-jira#63). M7-M9 close that gap. They evaluate only
when M1 passes (marketplace parses) and ≥1 plugin is listed; otherwise **N/A**
(M1/M2 own those FAILs — never double-count).

**M7 — each `plugins[]` element resolves to a source.** A bare **string**
element (`"./plugins/foo"`, `"./"`) **is** the source; an **object** element
MUST carry its own `source` key (missing it is the #61 shape → **FAIL**).
Refactor's `--apply` repairs an M7 FAIL by injecting a `source` (see
`references/plan-and-report-templates.md` → "Apply rules" M7 step).

**M8 — each resolved source has a valid shape** (mono/single common). Valid:
local path string (`"."` / `"./"` / `"plugins/<name>"` / `"./plugins/<name>"`)
or git-URL object (`{ "source": "url", "url": "<non-empty ….git>" }`). Any
other shape → **FAIL**. Elements with no resolvable source are M7's concern
(skipped here). The mode-shape combination itself is never a FAIL — a mono repo
may legitimately use remote URL sources (#63 guard).

**M9 — mono only: each declared local plugin dir exists.** For every source of
the form `./plugins/<name>`, `plugins/<name>/` must exist. Absent → **FAIL**.
Remote (url-type) sources are skipped; a mono repo whose sources are all remote
→ **N/A**. In `single` mode M9 is **N/A**.

## plugin.json known fields (M10, #1084)

A third case (claude-plugin-jira#65) installed cleanly but Claude Code rejected
the manifest at **load** (*"Validation errors: skills: Invalid input"*), so no
skills loaded. Cause: a custom `skills` array in `plugin.json` — the runtime
auto-scans `skills/`, so the field is both unnecessary and schema-invalid.

**M10 — every plugin.json top-level key is in the known-field whitelist.**
Known fields (Claude Code manifest schema, **2.1.x**): `name` (required),
`version` (required), `description`, `author`, `homepage`, `repository`,
`license`, `keywords`. Any other key → **FAIL**. Evaluated per plugin root
(same set as M3); missing/invalid manifest is M3's concern, no valid manifest
→ **N/A**. Refactor's `--apply` strips the unknown fields (backup kept) — see
`references/plan-and-report-templates.md` → "Apply rules" M10 step. The
whitelist SSOT is `_CPS_PLUGIN_JSON_KNOWN_FIELDS` in the bats fixture; bump it
with a version note on each Claude Code manifest-schema release.

## Recommended items (WARN when missing)

| ID | Item | WARN condition |
|----|------|----------------|
| R1 | per-skill `docs/skill-guides/<skill>.html` | that file missing |
| R2 | per-skill `docs/skill-output/<skill>-usage.{html,md}` | both missing |
| R3 | README is "Simple" | heuristic violated (below) |
| R4 | naming consistency | SKILL.md `name:` colon-namespace ↔ directory hyphen mismatch |
| R5 | per-skill README guide+usage links | README missing the guide OR the usage link for a skill |
| R6 | marketplace `$schema` declared | `marketplace.json` lacks a top-level `$schema` |
| R7 | listing metadata | no top-level `description`, OR an object plugin lacks `homepage` |
| R8 | README add-URL hint | a `/plugin marketplace add` example uses a `.git` clone URL |

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

**R6 `$schema` rule** — `marketplace.json` should declare a top-level
`"$schema"` so editors/LSP can validate it. Missing → **WARN** (no runtime
impact). **N/A** when the marketplace is unreadable (M1 owns that).

**R7 listing-metadata rule** — a top-level `description` plus a `homepage` on
each **object** plugin improve marketplace-UI listing. Missing description, or
any object plugin lacking a non-empty `homepage`, → **WARN**. String-form
plugins are exempt (no field to carry `homepage`).

**R8 add-URL hint** — when `README.md` shows a `/plugin marketplace add <URL>`
example, prefer the raw `.claude-plugin/marketplace.json` URL over a `.git`
clone (raw avoids a local clone — the #61 success pattern). A `.git` example
→ **WARN**; raw/other URL → **PASS**; no example or no README → **N/A**.

**Pages URL patterns** — when `structure-refactor --op` backfills R5 guide
links it uses the GitHub Pages absolute URL, derived host-independently from
`git remote get-url origin`:

| Host | Pages base | Full guide URL |
|------|------------|----------------|
| `github.com` | `https://<owner>.github.io/<repo>` | `…/skill-guides/<s>.html` |
| GHE (e.g. `github.samsungds.net`) | `https://<host>/pages/<owner>/<repo>` | `…/skill-guides/<s>.html` |

`structure-check` (read-only) still accepts either the relative path or the
Pages absolute URL as a satisfied link — it never requires a specific form;
the Pages-URL form is the shape `--op` writes. Full apply rule and GitHub
Pages activation step: `references/plan-and-report-templates.md` → "Apply
rules" + "Pages host & URL derivation (`--op`)".

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
