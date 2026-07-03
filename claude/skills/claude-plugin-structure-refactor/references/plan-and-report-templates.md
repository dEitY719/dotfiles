# claude-plugin:structure-refactor — Plan & Report Templates

## Plan template (dry-run AND the pre-amble of --apply)

```
claude-plugin structure refactor — <repo-path>   (mode: mono|single[, 추정]  scope: mandatory|recommended)
  plugin roots: <p1> / <p2>   skills: <count>   (git: yes|no, tree: clean|dirty)

계획 (현재 → 목표):
  [M1] create  .claude-plugin/marketplace.json   (skeleton, 1 plugin)
  [M7] source  plugins[].source 주입 (visuals ← ./plugins/visuals | git URL)
  [M3] create  plugins/visuals/.claude-plugin/plugin.json (skeleton)
  [M10] prune  plugins/visuals/.claude-plugin/plugin.json ← 미지원 필드(skills) 제거 (.bak 백업)
  [M4] git mv  visualize/SKILL.md → plugins/visuals/skills/visualize/SKILL.md
  [M5] mkdir   docs/skill-guides/, docs/skill-output/
  [R1] visualize docs/skill-guides/visualize.html   (→ /devx:visualize, --op only)
  [R2] stub    docs/skill-output/visualize-usage.md  (--op only)
  [Pages] enable GitHub Pages (branch=main, path=/docs) (--op only)
  [R4] rename  name: 교정 → claude-plugin:visualize     (--op only)
  [R5] link    README.md ← visualize guide Pages URL 링크 추가 (--op only)

총 <n> 변경  (필수 <m>, 권장 <r>)
```

- The header `mode:` is the detected (or forced) layout — `mono` /
  `single`, with `, 추정` appended when detection was ambiguous (spec
  priority 4). For `single` the action paths are root-relative (`skills/<s>/`,
  root `.claude-plugin/plugin.json`) and **no `plugins/` directory is
  created**; for `mono` they are `plugins/<p>/…` as shown above.
- One line per change: `[<ID>] <verb>  <path / detail>`.
- Verbs: `create` (new file), `mkdir` (new dir), `git mv` / `mv` (move),
  `source` (inject a missing `plugins[].source` into an existing marketplace — M7),
  `prune` (strip unknown top-level fields from an existing `plugin.json`, `.bak` kept — M10),
  `visualize` (generate an R1 guide by delegating to `/devx:visualize`),
  `stub` (empty placeholder), `pages` (activate GitHub Pages),
  `rename` (frontmatter/dir naming fix),
  `link` (append a per-skill Pages-URL guide link into README — R5).
- Items already correct produce **no line** (idempotent — proof there is
  nothing to do is an empty plan + `총 0 변경`).
- R1-R8 lines appear only when scope is `--op` / `--recommended`.

### Layout-conversion warning (forced mode ≠ detected mode)

When `--single`/`--mono` forces a **target** mode that differs from the
detected **current** layout, refactor does **not** convert (single↔mono is a
whole-plugin relocation + manifest rewrite — out of scope). The plan shows a
single warning line **in place of** any fix lines, and `--apply` stops
without writing:

```
claude-plugin structure refactor — <repo-path>   (mode: single→mono  scope: mandatory)
  plugin roots: . (single)   skills: <count>   (git: yes, tree: clean)

  [convert] 레이아웃 변환 필요 (single → mono) — 현재 미지원, 변경 없음.
            single↔mono 변환은 후속 작업(structure-convert)으로 분리됨.

총 0 변경  (변환 미수행)
```

## Apply rules

Execute the plan in this order so later steps see earlier results:

1. **mkdir** missing dirs: `.claude-plugin/`, `docs/skill-guides/`,
   `docs/skill-output/`, `plugins/<p>/skills/`.
2. **move** misplaced files: `git mv <src> <dst>` inside a git repo;
   `mv <src> <dst>` otherwise. Never overwrite an existing destination.
3. **skeleton** for a missing JSON:
   - `marketplace.json`:
     ```json
     { "name": "<repo-basename>", "plugins": ["./plugins/<p>"] }
     ```
   - `plugins/<p>/.claude-plugin/plugin.json`:
     ```json
     { "name": "<p>", "version": "0.0.0" }
     ```
   Fill `marketplace.json`'s plugins array from the dynamically discovered
   plugin names. Do not clobber a JSON that already parses — only create when
   missing. **plugin.json carries no `skills` array** — the runtime auto-scans
   `skills/`, and a `skills` field fails manifest validation (M10, #1084); the
   skeleton stays schema-clean so it satisfies M10 on creation.

   New skeletons are written source-clean: the `marketplace.json` above uses
   `"plugins": ["./plugins/<p>"]` (string = source shorthand) for mono and
   `[{ "source": "./" }]` for single, so a freshly-created skeleton already
   satisfies M7/M8.
3b. **M7 source injection (mandatory — runs under both `--mp` and `--op`)**:
   when a marketplace.json **already exists** and a `plugins[]` **object**
   element lacks its own `source`, inject one (the claude-plugin-jira#61
   install-fail shape). Derivation order per element:
   - if the element has a `homepage`/`repository` ending in `.git` →
     `{ "source": "url", "url": "<that>" }` (remote fetch);
   - else the local path of the detected mode — mono `./plugins/<name>`
     (from the element's `name`), single `"./"`.
   Idempotent: a no-op when every element already carries a source, and never
   touches string-form elements (they are already a source).
3c. **M10 unknown-field prune (mandatory — runs under both `--mp` and `--op`)**:
   for each existing, valid `plugin.json`, drop every top-level key outside the
   known-field whitelist (`name`, `version`, `description`, `author`,
   `homepage`, `repository`, `license`, `keywords`) — the claude-plugin-jira#65
   `skills`-array case that fails manifest validation at load. Copy the file to
   `plugin.json.bak` first (recoverable removal), then rewrite with
   `jq 'with_entries(select(.key as $x | $known | index($x)))'`. Idempotent: a
   no-op (and no `.bak`) when the manifest already has only known fields.
4. **`--op` only — R1 guide (delegate to `/devx:visualize`)**: for each
   discovered skill `<s>`, if `docs/skill-guides/<s>.html` is **missing**,
   invoke `/devx:visualize <path-to-SKILL.md>` to generate the guide at
   `docs/skill-guides/<s>.html` — real content, not a stub. Skip when the
   file already exists (idempotent). If `/devx:visualize` is unavailable or
   fails, warn and fall back to the R1 stub below; never abort the run.
   Fallback stub `docs/skill-guides/<s>.html`:
   ```html
   <!-- TODO: claude-plugin guide for <s> -->
   <!-- 이 가이드는 /devx:visualize 로 채우세요 (placeholder stub). -->
   ```
5. **`--op` only — R2 usage stub**: empty placeholder
   `docs/skill-output/<s>-usage.md` with a TODO header (unchanged — usage
   samples stay stub level):
   ```markdown
   <!-- TODO: <s> usage sample — fill with /devx:visualize -->
   ```
6. **`--op` only — GitHub Pages activation**: derive `$HOST` / `$OWNER` /
   `$REPO` per "Pages host & URL derivation (`--op`)" below. Query the
   current state:
   ```bash
   gh api --hostname "$HOST" "repos/$OWNER/$REPO/pages"
   ```
   If it 404s (Pages inactive), activate it (pipe the JSON in via stdin — no
   bash-only here-string, so the snippet is `/bin/sh`-safe):
   ```bash
   echo '{"source":{"branch":"main","path":"/docs"}}' \
     | gh api --hostname "$HOST" "repos/$OWNER/$REPO/pages" -X POST --input -
   ```
   Skip when Pages already responds 200 (idempotent). Soft-fail: a missing
   token scope or unreachable host warns and continues.
7. **`--op` only — R4 naming**: when a SKILL.md `name:` colon-namespace ↔
   directory hyphen form disagree, correct the directory name (prefer
   `git mv`) so it matches the `name:`; never silently rewrite a correct
   `name:`.
8. **`--op` only — R5 README links**: for each skill `<s>` whose README is
   missing the guide or usage link, append into the README under that
   skill's section — **each missing link only** (check guide and usage
   independently, same as before). The **guide** link now uses the
   Pages-URL format from "Pages host & URL derivation (`--op`)" below; the usage
   link stays a relative path (usage is stub level):
   ```markdown
   - `<s>` ([visual guide ↗](<pages-base>/skill-guides/<s>.html))
   - `<s>` usage: [usage](docs/skill-output/<s>-usage.md)
   ```
   Append only the link(s) actually missing — if the guide is already linked
   (relative `skill-guides/<s>.html` or the Pages URL both count) and only
   the usage is absent, append the usage line alone. Never rewrite or
   reorder existing README content, and never duplicate a link already
   present (idempotent).

Skeleton/stub writes never touch a file that already exists, link backfill
never duplicates an existing link, and Pages activation is skipped when
already active — the skill is idempotent.

## Pages host & URL derivation (`--op`)

Parse `git remote get-url origin` for `<host>/<owner>/<repo>`
(host-independent — works for both `https://` and `git@` forms, and for any
GHE hostname, mirroring `claude-plugin:rename-repo`'s owner/repo parsing):

| Host | `gh api` target | Pages base (`<pages-base>`) |
|------|-----------------|------------------------------|
| `github.com` | `--hostname github.com` | `https://<owner>.github.io/<repo>` |
| GHE (e.g. `github.samsungds.net`) | `--hostname <host>` | `https://<host>/pages/<owner>/<repo>` |

The full R5 guide URL is therefore
`<pages-base>/skill-guides/<s>.html`, e.g.
`https://acme.github.io/claude-plugin-visuals/skill-guides/visualize.html`
(github.com) or
`https://github.samsungds.net/pages/<owner>/<repo>/skill-guides/visualize.html`
(GHE).

## Completion report template

```
## claude-plugin:structure-refactor Report
Repo: <repo-path>
Layout: mono | single  (detected | forced[, 추정])
Mode: dry-run | apply
Scope: mandatory | recommended

Planned: <n>   Applied: <n>   Skipped (already correct): <n>

<the plan block above, with applied lines marked ✓>

[OK] refactor complete   |   [FAIL] <reason>
applied=<n> moved=<n> created=<n> sourced=<n> pruned=<n> visualized=<n> stubbed=<n> pages=<activated|active|skip|n/a> linked=<n> layout=<mono|single> mode=<dry-run|apply> scope=<mp|op>
```

For a guarded layout-conversion (forced mode ≠ detected) the report is
`[OK] no conversion (out of scope)` with `applied=0 layout=<from>→<to>` and
the verify hint — never `[FAIL]` (refusing an out-of-scope move is a
safe no-op, not an error).

End with the next-action hint:

- after a dry-run: `Next: /claude-plugin:structure-refactor <path> --apply [--op]`
- after `--apply`: `Next: /claude-plugin:structure-check <path>`

A no-op run (nothing to change) still reports `[OK] refactor complete` with
`applied=0` and the verify hint.
