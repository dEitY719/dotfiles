# Structure Refactor: --op Flag Rules

Under `--op` (`--recommended`), R1-R5 fixes are applied in addition to the
mandatory M1-M10 (which includes the M7 source injection and M10 plugin.json
prune — both run under `--mp` too). R6-R8 are audit-only WARN items:
`$schema` / `description` / `homepage` / README-URL fixes are **not**
auto-applied; a developer fills those. Specific behaviors when
`--apply --op` is active:

## R1 — per-skill guide generation

Delegate to `/devx:visualize <SKILL.md>` → `docs/skill-guides/<skill>.html`.
Skip when the file already exists (idempotent). Never call
`/devx:excalidraw-diagram` here.

## R2 — usage sample stubs

Create `docs/skill-output/<skill>-usage.html` as a placeholder stub containing
a TODO comment pointing at `/devx:visualize`. These remain stubs — they are
never auto-populated with real content.

## R4 — naming correction

Correct directory↔frontmatter mismatches: directory `claude-plugin-foo-bar`
↔ frontmatter `name: claude-plugin:foo-bar` (hyphen directory form ↔
colon-namespace frontmatter form). Mismatch → rename the directory with
`git mv` (or `mv` outside a git repo).

## R5 — README link backfill

For each discovered skill `<s>`, ensure `README.md` contains both:
- a link to `skill-guides/<s>.html`, and
- a link to `skill-output/<s>-usage.{html,md}`.

Backfill uses the GitHub Pages absolute URL (derived from
`git remote get-url origin`):

| Host | Pages base | Full guide URL |
|------|------------|----------------|
| `github.com` | `https://<owner>.github.io/<repo>` | `…/skill-guides/<s>.html` |
| GHE (e.g. `github.samsungds.net`) | `https://<host>/pages/<owner>/<repo>` | `…/skill-guides/<s>.html` |

## GitHub Pages activation

Auto-activate GitHub Pages when inactive (github.com + GHE). This is a
soft-fail step: a missing token scope or unreachable host warns and continues
— it never aborts the run.

Full apply sequence and Pages host/URL derivation:
see `references/plan-and-report-templates.md` → "Apply rules" and
"Pages host & URL derivation (`--op`)".
