# Generated Doc Template

The output `docs/guide/plugins/<plugin>.md` is Korean and has exactly 3 fixed
sections. Model it on `docs/guide/plugins/ponytail.md` (the canonical example).
Fill the placeholders `<...>` from the plugin's `plugins.json` /
`marketplaces.json` entries and its cached `SKILL.md` files.

## Skeleton

```markdown
# <plugin> 플러그인 가이드

<1-2줄 한국어 개요 — 이 플러그인이 무엇을 하는지. 각 SKILL.md description 을
종합해 한국어로 요약. 영어 원문 복붙 금지.>

- Marketplace: [`<owner/repo>`](https://github.com/<owner/repo>)
- 이 dotfiles 저장소 SSOT: `claude/plugin/plugins.json` (`<plugin>@<marketplace>`), `claude/plugin/marketplaces.json`

## 1. 설치 방법

​```
/plugin marketplace add <owner/repo>
/plugin install <plugin>@<marketplace>
/reload-plugins
​```

`claude/plugin/plugins.json`·`marketplaces.json`은 `plugin-sync.sh` / `plugin-sync-session.sh` hook이
세션 종료 시 자동으로 동기화한다 (`claude/AGENTS.md` → "Plugin Manifest" 참조) — 수동으로 SSOT 파일을
편집할 필요 없음. 신규 PC에는 `./claude/plugin/restore.sh`로 일괄 복원된다.

## 2. 스킬 설명

| 스킬 | 성격 | 하는 일 |
|------|------|---------|
| `<skill-name>` | <일회성/지속 모드 등 한 단어 성격> | <SKILL.md description + 핵심 규칙 1줄 한국어 요약> |
| ... | ... | ... |

<스킬이 여러 개면 공통 규칙/해제 방법 등을 한 줄로 덧붙일 수 있음 (선택).>

## 3. 사용법 예제

**<대표 사용 시나리오 1>**
​```
/<skill-name>
"<사용자 요청 예시>"
→ <기대 출력 스케치>
​```

<스킬 수만큼 반복하되, 스킬이 많으면 대표 2-4개만. 각 예제는 실제 호출 형태 +
기대 출력 한 줄.>
```

## Building the 스킬 설명 table (Step 3 extraction)

For each `SKILL.md`:
- **스킬** = frontmatter `name` (colon form as-is, e.g. `ponytail-review`).
- **성격** = one Korean word/phrase inferred from the body: is it a persistent
  mode, a one-shot report, a read-only audit, a file-writing action? Keep it to
  a few words.
- **하는 일** = 1 line. Compress the `description` + the single most important
  body rule into Korean. Do not translate the whole SKILL.md — one line.

Single-skill plugins (e.g. `andrej-karpathy-skills`) still get the full 3
sections; the table just has one row and 사용법 has one example.

## Optional closing section

If the plugin has misc config/notes worth surfacing (env vars, config file
location, related commands), add a `## 참고` section like ponytail.md's. Skip it
if there is nothing natural to say — do not pad.

## Note on the code fences above

The `​` before the triple-backtick fences in the skeleton is a zero-width space
so this template renders inside a markdown code block. Strip it when you write
the real doc — the generated file uses plain ` ``` ` fences.
