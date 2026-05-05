# Issue Body Templates — DEPRECATED

> **DEPRECATED** — 본 파일은 더 이상 사용되지 않는다. 신규 위치는
> `references/templates/<prefix>.md` 이며, conventional-commit prefix
> 기준 8종으로 분리되었다. 다음 분기에 본 파일은 제거된다.

## 신규 위치

| 기존 카테고리 | 신규 prefix | 템플릿 파일 |
|--------------|-------------|--------------|
| feature | `feat` | `references/templates/feat.md` |
| bug | `fix` | `references/templates/fix.md` |
| misc | `misc` | `references/templates/misc.md` |
| (없음) | `refactor` | `references/templates/refactor.md` |
| (없음) | `perf` | `references/templates/perf.md` |
| (없음) | `docs` | `references/templates/docs.md` |
| (없음) | `test` | `references/templates/test.md` |
| (없음) | `chore` | `references/templates/chore.md` |

큰 `feat` 이슈를 위한 PRD/TRD 골격은 `references/samples/prd-sample.md`
및 `references/samples/trd-sample.md` 에 추가되었다.

## 마이그레이션

- 타이틀 형식이 conventional commit 으로 변경되었다 — 기존
  `[Feature]` / `[Bug]` / `[Misc]` 대괄호 형식은 폐기.
- 본문 분류 결정 트리는 `SKILL.md` Step 2 에서 SSOT 로 관리한다.

## 폐기 예정 콘텐츠 (참조용)

이전 3종 템플릿의 본문 골격은 신규 `templates/{feat,fix,misc}.md` 가
상위 호환으로 흡수했다. 본 파일에 별도로 보존하지 않는다.
