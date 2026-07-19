# devx:plugin-guide — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<plugin-name>` or `-h`/`--help`/`help` | — | `<plugin>@<marketplace>` or `<plugin>` alone (required unless help) |
| 2 | `--force` | off | Regenerate the doc even if it already exists |

## Usage

- `/devx-plugin-guide ponytail@ponytail` — generate `docs/guide/plugins/ponytail.md`
- `/devx-plugin-guide andrej-karpathy-skills` — marketplace inferred from `plugins.json`
- `/devx-plugin-guide ponytail --force` — overwrite an existing doc
- `/devx-plugin-guide -h` / `--help` / `help` — print this help

## What the skill does

1. Confirms the plugin is in `claude/plugin/plugins.json` (SSOT). If not
   installed, prints the 설치 안내 below and stops — never installs for you.
2. Finds every `skills/*/SKILL.md` under the plugin's cache dir
   (`$CLAUDE_CONFIG_DIR/plugins/cache/<marketplace>/<plugin>/<version>/`),
   picking the highest version. Zero skills → reports "스킬 없음" and stops.
3. Extracts each skill's `name` / `description` + one core rule.
4. Writes `docs/guide/plugins/<plugin>.md` in Korean with 3 fixed sections:
   설치 방법 / 스킬 설명 / 사용법 예제.
5. Adds an idempotent index line to `docs/guide/plugins/README.md`.
6. Existing doc + no `--force` → skips (safe re-run). `--force` overwrites.

## What the skill will NOT do

- Install plugins, run `/plugin install`, or add marketplaces (Non-Goal).
- Commit or open a PR — it stops after writing the doc.
- Smoke-test the skills — out of scope.
- Merge/diff sections into an existing doc — it either skips or overwrites.

## 설치 안내 (not-installed error case, filled per plugin)

```
플러그인 <plugin>@<marketplace> 이 plugins.json 에 없습니다. 설치 후 재실행하세요:

/plugin marketplace add <owner/repo>
/plugin install <plugin>@<marketplace>
/reload-plugins
```

`<owner/repo>` comes from `claude/plugin/marketplaces.json[<marketplace>]`.

## 출력 형식 (final report)

```
[OK] docs/guide/plugins/<plugin>.md 생성 (스킬 N개)
- docs/guide/plugins/README.md 인덱스 갱신
Next: 문서 검토 후 /gh-commit 으로 커밋 (이 스킬은 커밋하지 않음)
```

Skip case:
```
[SKIP] docs/guide/plugins/<plugin>.md 이미 존재 — 재생성하려면 --force
```
