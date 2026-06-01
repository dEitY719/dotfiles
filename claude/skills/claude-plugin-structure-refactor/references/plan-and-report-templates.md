# claude-plugin:structure-refactor — Plan & Report Templates

## Plan template (dry-run AND the pre-amble of --apply)

```
claude-plugin structure refactor — <repo-path>   (scope: mandatory|recommended)
  plugins: <p1> / <p2>   skills: <count>   (git: yes|no, tree: clean|dirty)

계획 (현재 → 목표):
  [M1] create  .claude-plugin/marketplace.json   (skeleton, 1 plugin)
  [M3] create  plugins/visuals/.claude-plugin/plugin.json (skeleton)
  [M4] git mv  visualize/SKILL.md → plugins/visuals/skills/visualize/SKILL.md
  [M5] mkdir   docs/skill-guides/, docs/skill-output/
  [R1] visualize docs/skill-guides/visualize.html   (→ /devx:visualize, --op only)
  [R2] stub    docs/skill-output/visualize-usage.md  (--op only)
  [Pages] enable GitHub Pages (branch=main, path=/docs) (--op only)
  [R4] rename  name: 교정 → claude-plugin:visualize     (--op only)
  [R5] link    README.md ← visualize guide Pages URL 링크 추가 (--op only)

총 <n> 변경  (필수 <m>, 권장 <r>)
```

- One line per change: `[<ID>] <verb>  <path / detail>`.
- Verbs: `create` (new file), `mkdir` (new dir), `git mv` / `mv` (move),
  `visualize` (generate an R1 guide by delegating to `/devx:visualize`),
  `stub` (empty placeholder), `pages` (activate GitHub Pages),
  `rename` (frontmatter/dir naming fix),
  `link` (append a per-skill Pages-URL guide link into README — R5).
- Items already correct produce **no line** (idempotent — proof there is
  nothing to do is an empty plan + `총 0 변경`).
- R1-R5 lines appear only when scope is `--op` / `--recommended`.

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
     { "name": "<p>", "version": "0.0.0", "skills": ["./skills/<s>"] }
     ```
   Fill arrays from the dynamically discovered plugin/skill names. Do not
   clobber a JSON that already parses — only create when missing.
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
6. **`--op` only — GitHub Pages activation**: derive `<host>/<owner>/<repo>`
   per "Pages host & URL derivation" below. Query the current state:
   ```bash
   gh api --hostname <host> repos/<owner>/<repo>/pages
   ```
   If it 404s (Pages inactive), activate it:
   ```bash
   gh api --hostname <host> repos/<owner>/<repo>/pages -X POST \
     --input - <<< '{"source":{"branch":"main","path":"/docs"}}'
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
   Pages-URL format from "Pages host & URL derivation" below; the usage
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
Mode: dry-run | apply
Scope: mandatory | recommended

Planned: <n>   Applied: <n>   Skipped (already correct): <n>

<the plan block above, with applied lines marked ✓>

[OK] refactor complete   |   [FAIL] <reason>
applied=<n> moved=<n> created=<n> visualized=<n> stubbed=<n> pages=<activated|active|skip|n/a> linked=<n> mode=<dry-run|apply> scope=<mp|op>
```

End with the next-action hint:

- after a dry-run: `Next: /claude-plugin:structure-refactor <path> --apply [--op]`
- after `--apply`: `Next: /claude-plugin:structure-check <path>`

A no-op run (nothing to change) still reports `[OK] refactor complete` with
`applied=0` and the verify hint.
