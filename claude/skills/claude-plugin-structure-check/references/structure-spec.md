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

**M7 — each `plugins[]` element resolves to a source.**
- A bare **string** element (`"./plugins/foo"`, `"./"`) **is** the source
  (shorthand) → satisfied.
- An **object** element MUST carry its own `source` key → missing it is the
  #61 shape → **FAIL**.

**M8 — each resolved source has a valid shape** (mono/single common). Valid:
- local path string: `"."` / `"./"` / `"plugins/<name>"` / `"./plugins/<name>"`;
- git-URL object: `{ "source": "url", "url": "<non-empty ….git>" }`.

  Any other shape (e.g. an object whose `source` is a raw `https://…` URL with
  no `url` field) → **FAIL**. Elements with no resolvable source are M7's
  concern and are skipped here (never a double FAIL). The mode-shape combination
  itself is **not** a FAIL — a mono repo may legitimately use remote URL sources
  — so M8 never re-flags a valid remote setup (#63 misdiagnosis guard).

**M9 — mono only: each declared local plugin dir exists.** For every source of
the form `./plugins/<name>` (or `plugins/<name>`), `plugins/<name>/` must exist
on disk. A declared-but-absent directory (typo/misconfig) → **FAIL**. Remote
(url-type) sources have nothing local to verify and are skipped; a mono repo
whose sources are all remote → **N/A**. In `single` mode M9 is **N/A** (no
`plugins/` layout).

## plugin.json known fields (M10, #1084)

M7-M9 catch marketplace-level source problems; **M10 catches the plugin.json
level.** A third real case (claude-plugin-jira#65) installed cleanly but Claude
Code rejected the manifest at **load** — `/plugin` Errors tab showed
*"Plugin … has an invalid manifest … Validation errors: skills: Invalid
input"* — so none of the plugin's skills loaded despite `enabledPlugins` being
true. Cause: a custom `skills` array in `plugin.json`. The runtime auto-scans
`skills/`, so the field is unnecessary **and** schema-invalid; lenient plugins
(`aws-login`, `ds-skills`) omit it entirely.

**M10 — every plugin.json top-level key is in the known-field whitelist.**
Known fields (Claude Code manifest schema, **2.1.x**):

```
name (required), version (required), description, author,
homepage, repository, license, keywords
```

Any key outside this set → **FAIL** (e.g. the `skills` array above). `skills`
is the classic trap: it looks supported because it matches the auto-scanned
folder name, so authors add it by hand. Evaluated per plugin root over the same
root set as M3; a missing/invalid plugin.json is M3's concern (skipped here),
and no plugin root with a valid manifest → **N/A**. The whitelist is the SSOT
`_CPS_PLUGIN_JSON_KNOWN_FIELDS` in the bats fixture — bump it (with a version
note) on each Claude Code manifest-schema release.

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
`"$schema"` (e.g. `https://anthropic.com/claude-code/marketplace.schema.json`)
so editors/LSP can validate and autocomplete it. Missing → **WARN** only (no
runtime impact). **N/A** when the marketplace is unreadable (M1 owns that).

**R7 listing-metadata rule** — a top-level `description` and, for each
**object** plugin, a `homepage` improve marketplace-UI listing quality.
Missing description, or any object plugin lacking a non-empty `homepage`,
→ **WARN**. String-form plugin elements have nowhere to carry `homepage`, so
they are exempt. **N/A** when the marketplace is unreadable.

**R8 add-URL hint** — when `README.md` contains a `/plugin marketplace add
<URL>` example, prefer the raw `.claude-plugin/marketplace.json` URL (no local
clone needed — the #61 success pattern) over a `.git` clone URL. A `.git`
example → **WARN**; a raw-`marketplace.json` (or other) URL → **PASS**; no
add example, or no README → **N/A** (both forms are valid — this is a nudge,
not a hard rule).

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
