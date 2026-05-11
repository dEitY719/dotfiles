# gh:issue-create — Prefix Decision Table

Step 2 picks exactly one conventional-commit prefix as the dominant
intent. Each prefix has a body template under
`templates/<prefix>.md` that defines the title format and body skeleton.

| Prefix | When |
|--------|------|
| `feat` | 신규 기능 / 개선 / 확장 |
| `fix` | 에러 / 실패 / 의도와 다른 동작 |
| `refactor` | 동작 보존하며 구조 정리 |
| `perf` | 느림 / 자원 사용 과다 |
| `docs` | 문서 자체 변경 |
| `test` | 테스트 갭 / 추가 / 변경 |
| `chore` | 빌드·CI·도구·deps·스타일 (`build`/`ci`/`style`/`revert` 흡수) |
| `misc` | 위 어디에도 안 들어감 (fallback) |

## Disambiguation rules

- 모호하면 묻지 말고 가장 보수적인 `misc` 로 떨어진다.
- 대형 `feat` 휴리스틱 (영향 컴포넌트 ≥3 / NF 명시 / 결정 누적 — 둘
  이상 해당) 은 `templates/feat.md` "대형 feat 가이드" 를 따른다.

## Title formatting

- conventional commit 형식 `<type>[(<scope>)]: <한 줄 요약>`.
- `misc` 만 prefix 없이 한 줄 요약만 적는다.
- 기존 `[Feature]` / `[Bug]` / `[Misc]` 대괄호 형식은 폐기.
