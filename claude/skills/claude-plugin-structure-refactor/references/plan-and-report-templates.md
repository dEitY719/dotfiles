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
  [R1] stub    docs/skill-guides/visualize.html        (--op only)
  [R4] rename  name: 교정 → claude-plugin:visualize     (--op only)

총 <n> 변경  (필수 <m>, 권장 <r>)
```

- One line per change: `[<ID>] <verb>  <path / detail>`.
- Verbs: `create` (new file), `mkdir` (new dir), `git mv` / `mv` (move),
  `stub` (empty placeholder), `rename` (frontmatter/dir naming fix).
- Items already correct produce **no line** (idempotent — proof there is
  nothing to do is an empty plan + `총 0 변경`).
- R1-R4 lines appear only when scope is `--op` / `--recommended`.

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
4. **`--op` only — R1/R2 stubs**: empty placeholder files with a TODO
   header. Example `docs/skill-guides/<skill>.html`:
   ```html
   <!-- TODO: claude-plugin guide for <skill> -->
   <!-- 이 가이드는 /devx:visualize 로 채우세요 (placeholder stub). -->
   ```
   `docs/skill-output/<skill>-usage.md`:
   ```markdown
   <!-- TODO: <skill> usage sample — fill with /devx:visualize -->
   ```
5. **`--op` only — R4 naming**: when a SKILL.md `name:` colon-namespace ↔
   directory hyphen form disagree, correct the directory name (prefer
   `git mv`) so it matches the `name:`; never silently rewrite a correct
   `name:`.

Skeleton/stub writes never touch a file that already exists — the skill is
idempotent.

## Completion report template

```
## claude-plugin:structure-refactor Report
Repo: <repo-path>
Mode: dry-run | apply
Scope: mandatory | recommended

Planned: <n>   Applied: <n>   Skipped (already correct): <n>

<the plan block above, with applied lines marked ✓>

[OK] refactor complete   |   [FAIL] <reason>
applied=<n> moved=<n> created=<n> stubbed=<n> mode=<dry-run|apply> scope=<mp|op>
```

End with the next-action hint:

- after a dry-run: `Next: /claude-plugin:structure-refactor <path> --apply [--op]`
- after `--apply`: `Next: /claude-plugin:structure-check <path>`

A no-op run (nothing to change) still reports `[OK] refactor complete` with
`applied=0` and the verify hint.
