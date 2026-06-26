---
status: approved
---

# `adr/` — Architecture Decision Records

프로젝트 전체에 걸친 **굵직한 아키텍처 의사결정의 불변 로그**다.
한 번 작성된 ADR 은 사실상 수정하지 않는다 — 결정을 뒤집을 때는
새 ADR 을 작성하고 기존 ADR 의 `status:` 를 `deprecated` 로 바꾼 뒤
"Superseded by ADR-NNNN" 한 줄을 덧붙인다 (#1027).

## `adr/` vs `requirement/` D-섹션 경계 규칙

| 위치 | 담는 내용 |
|------|-----------|
| **`adr/NNNN-<kebab>.md`** | 프로젝트 전체 구조에 영향을 주는 굵직한 아키텍처 결정. 맥락·대안·근거·결과를 갖춘 불변 로그. |
| **`requirement/product-requirements.md` D-섹션** | 제품 요구사항 맥락 안의 **경량 inline 결정** (한 줄 표 항목). |

판단 기준: "이 결정이 여러 모듈/디렉토리 구조에 파급되는가?" → 그렇다면 ADR.
"제품 요구사항을 서술하다가 자연스럽게 따라오는 결정인가?" → D-섹션.

## 번호 규칙

- 파일명: `NNNN-<kebab-case-title>.md` (4자리 zero-pad, 예: `0001-hybrid-docs-policy.md`).
- 번호는 단조 증가하며 재사용하지 않는다. 결정이 폐기돼도 번호는 비워 두지 않는다.
- 파일명은 kebab-case 린터(`mise run lint-docs`)의 강제 검사 대상이다.

## front-matter `status:` 규칙

모든 ADR 은 YAML front-matter 로 시작한다:

```yaml
---
status: approved   # draft | review | approved | deprecated
---
```

- `draft` — 작성 중, 아직 합의 전.
- `review` — 리뷰/논의 진행 중.
- `approved` — 확정. 현재 유효한 SSOT.
- `deprecated` — 폐기됨. 본문 첫 줄에 "Superseded by ADR-NNNN" 명시.

## ADR 상호링크 규칙

`feature/` 문서에서 중대한 기술 전환이 일어나면 본문에 관련 ADR 번호를 링크한다:

```markdown
Ref: [ADR-0001](../../adr/0001-hybrid-docs-policy.md)
```

## 템플릿

```markdown
---
status: draft
---

# ADR-NNNN: <결정 제목>

- **일자**: YYYY-MM-DD
- **관련 이슈/PR**: #NNNN

## 맥락 (Context)

무엇이 이 결정을 필요하게 만들었는가.

## 결정 (Decision)

무엇을 하기로 했는가.

## 고려한 대안 (Alternatives)

채택하지 않은 선택지와 그 이유.

## 결과 (Consequences)

이 결정으로 생기는 긍정·부정 영향, 후속 작업.
```

## 인덱스

| ADR | 제목 | status |
|-----|------|--------|
| [0001](./0001-hybrid-docs-policy.md) | docs 문서 정책 하이브리드 확정 | approved |
