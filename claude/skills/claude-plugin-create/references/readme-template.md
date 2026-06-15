# claude-plugin:create — README Template

Written in Step 5 at `<dest>/<plugin-name>/README.md`. Placeholders:
`<plugin-name>` = repo name, `<plugin>` = plugin key, `<owner>`/`<host>`
from the flags, `<skill>` rows from the discovered skill list.

This template is designed to satisfy `claude-plugin:structure-check`'s
recommended checks out of the box: R3 ("Simple" — at least one `docs/` link,
a skill section), and R5 (per-skill guide **and** usage links). The
`docs/skill-guides/<skill>.html` and `docs/skill-output/<skill>-usage.md`
files are placeholder stubs at create time — fill them later with
`/devx:visualize` (that satisfies R1/R2).

## Template

````markdown
# <plugin-name>

> Claude Code 스킬 마켓플레이스 플러그인. `<plugin>` 플러그인이 아래 스킬들을 번들합니다.

## 설치

```
/plugin marketplace add <owner>/<plugin-name>
/plugin install <plugin>@<plugin-name>
```

GHES(`<host>`)에서는 호스트 인증 후 동일하게 추가합니다.

## 스킬 목록

| 스킬 | 설명 | 가이드 / 사용 예시 |
|------|------|--------------------|
| `<skill>` | <SKILL.md description 첫 문장> | [guide](docs/skill-guides/<skill>.html) · [usage](docs/skill-output/<skill>-usage.md) |

> 표의 각 행은 스킬 1개에 대응합니다. 가이드/사용 예시 링크는
> `docs/skill-guides/`, `docs/skill-output/` 의 문서를 가리킵니다
> (생성 시 placeholder, 이후 `/devx:visualize` 로 채움).

## 구조

```
.
├── .claude-plugin/marketplace.json
├── plugins/<plugin>/
│   ├── .claude-plugin/plugin.json
│   └── skills/<skill>/SKILL.md
├── docs/skill-guides/
├── docs/skill-output/
└── README.md
```

## License

MIT © <year> <owner>
````

## Notes

- One table row per discovered skill — both the `skill-guides/<skill>.html`
  guide link and the `skill-output/<skill>-usage.md` usage link must be
  present (R5).
- Keep the body "Simple" (R3): it links into `docs/`, names the
  `plugins`/`skills`, and stays short.
