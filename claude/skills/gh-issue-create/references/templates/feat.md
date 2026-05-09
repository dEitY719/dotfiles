# feat — 본문 템플릿

신규 기능 / 개선 / 확장 이슈에 사용한다. 큰 건은 본문 안에 PRD-lite +
TRD-lite 를 배치하거나, `references/samples/prd-sample.md` /
`references/samples/trd-sample.md` 형식의 외부 문서로 분리한다.

## 타이틀

```
feat[(<scope>)]: <한 줄 요약>
```

예) `feat(gh-issue-create): conventional-commit prefix 기반 템플릿 분기`

## 본문 골격

```markdown
## TL;DR
<1~3줄 — 무엇을 만들고 왜>

## 배경 (Why / Context)
<사용자 문제·현재 고통점·동기>

## Goals / Non-Goals
### Goals
-
### Non-Goals
-

## 요구사항 (Requirements)
<F-#·NF-# 식별자 권장. 큰 건은 외부 PRD 링크>
- F-1 ...
- NF-1 ...

## 설계 개요 (Design — TRD-lite)
<Architecture·Components·Data Models 핵심만. 큰 건은 외부 TRD 링크>

## 대안 (Alternatives Considered)
| 대안 | 거절 사유 |
|---|---|
|  |  |

## 영향 범위 (Impact)
<수정 대상 파일·인접 시스템·마이그레이션 영향>

## Dependencies
<선행 작업·외부 시스템·라이브러리·다른 이슈 (`Depends on #N`)>
-

## 수용 기준 (Acceptance Criteria)
<관찰 가능·검증 가능한 조건만. 구현 디테일 X>
- [ ] ...

## Error Cases
<예상되는 실패 모드와 대응. `<조건> → <응답>` 형식 권장>
- <조건> → <응답>

## Open Questions
-

## References
- 관련 파일·이슈·PR
- PRD: (있으면) <PRD 경로 또는 링크>
- TRD: (있으면) <TRD 경로 또는 링크>
```

> 위 본문 골격의 PRD/TRD 항목은 **placeholder** 다 — 실제 이슈에서는
> 작성한 PRD/TRD 문서 경로로 치환한다. 표준 골격은
> `references/samples/{prd,trd}-sample.md` 를 따른다 (본 파일 자체에
> 인용하지 말 것).

## 대형 feat 가이드

다음 셋 중 둘 이상이면 본문에 PRD-lite + TRD-lite 섹션을 inline 으로
포함하거나, `docs/requirement/prd-<slug>.md` /
`docs/requirement/trd-<slug>.md` 로 외부 분리하고 본문은 링크만 둔다.

1. 영향 컴포넌트 ≥ 3
2. NF (성능·보안 등) 요구가 명시됨
3. 다수의 의사결정(D-#)이 누적

외부 분리 시 표준 골격은 `samples/{prd,trd}-sample.md` 를 따른다.
