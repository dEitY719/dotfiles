# TRD Scaffold — Built-in Fallback Template

The skill loads `<prd-dir>/trd/_template.md` first; if absent, it uses
the verbatim block below. This template is the **agent-toolbox
8-section standard** (AI Spec-Driven 6 sections — AWS Kiro / Spec Kit
/ Cursor — plus Google Design Doc 2 sections: Goals/Non-Goals,
Alternatives Considered).

Placeholders use `{{...}}` syntax. `--apply` substitutes them from the
plan's Components table before writing.

## Verbatim template

```markdown
# TRD: {{component-title}} — {{project-name}}

> **상태**: Draft v1 ({{iso-date}})
> **책임 PRD 항목**: {{responsible-prd-items}} ([PRD](../{{prd-basename}}))
> **인용 NF**: {{cited-nf-items}}
> **소유자**: @{{owner-placeholder}}
> **인접 TRD**: {{adjacent-trd-slugs}}

## 1. Overview
> 1–2 문장. {{component-title}} 가 무엇이고 책임 PRD 항목을 어떻게 충족하는지.
> "왜" / "무엇" 은 PRD 를 인용하고, 본 TRD 는 "어떻게" 만 다룬다.

## 2. Goals / Non-Goals
### Goals
> 측정 가능한 목표를 bullet 으로 나열. 각 목표는 책임 F-# / NF-# 와 1:1 매핑.
> 형태: "G-1: <목표> — 책임 F-#: <…>; 검증: <어떻게 측정/테스트>"

### Non-Goals
> 의도적으로 다루지 않는 범위. 추후 분리될 TRD 후보 / 다른 컴포넌트 소관.

## 3. Requirements
### Functional
> 책임 F-# 를 인용하고 본 TRD 가 구현할 단위로 재기술. PRD 의 F-# 는 What,
> 여기 R-F# 는 How 의 진입점이다. 형태: "R-F1: <기능> (PRD F-X)"

### Non-functional
> 책임 NF-# (primary) + 인용 NF-# 를 인용. **재정의 금지** — PRD §5 인용만.
> 형태: "R-NF1: <PRD NF-Y 인용>; 본 TRD 영향: <…>"

## 4. Design
> "어떻게" 만. 다음 하위 구조를 권장:
> - 인터페이스 (함수 시그니처 / API endpoint / 이벤트 토픽 / CLI flag)
> - 데이터 모델 (스키마 / 클래스 / 상태 머신)
> - 시퀀스 / 흐름 (정상 경로 + 주요 분기)
> - 에러 흐름 (예외 / 타임아웃 / 부분 실패 / 재시도 정책)
> - 인접 TRD 와의 계약 (참조 슬러그 + 인터페이스 한정)
>
> 본문 채우기 시 800줄 한계 / AI 환각 주의. 결정성 있는 부분만 기술하고,
> 미결정은 §8 Open Questions 로 이동.

## 5. Tasks / Validation
> 본 TRD 가 산출할 구현 단위. 각 task 는 devx:trd-to-issues 가 GitHub Issue
> 로 분해할 입력 — 따라서 다음 기준을 따라야 한다:
> - AC 1–3 개 / unit-testable / independently committable
> - Task 당 변경 파일 ≤ 5 / 신규 LOC ≤ 300 (pro-friendly), 초과 시 max-only
>
> 형태:
> - [ ] T-1: <Task title> — 책임 R-F#: <…>; AC: <1–3 개>

## 6. References
> - 책임 PRD 항목 anchored 링크 (PRD `#f-1` 등)
> - 인접 TRD 슬러그 링크
> - 외부 spec / RFC / 라이브러리 문서
> - 선행 결정 (ADR / discussion / 이전 PR)

## 7. Alternatives Considered
> 이 디자인이 채택되지 않은 대안과 거절 사유를 표로:
>
> | 대안 | 거절 사유 |
> |---|---|
> | <…> | <…> |

## 8. Open Questions
> 결정 못 한 항목. 본 TRD 가 머지 / 구현 시작 전 해결 필요.
> 형태: "OQ-1: <질문>; 차단되는 의사결정: <…>; 제안된 해결: <…>"
```

## Frontmatter field rules (outside the verbatim block)

The 5 frontmatter slots above (`상태` / `책임 PRD 항목` / `인용 NF`
/ `소유자` / `인접 TRD`) follow the same line-stability invariants as
`plan-format.md` → "Plan field rules":

- `책임 PRD 항목` carries `F-#` + `D-#` (both required) plus an
  optional `NF-#` primary (0 or 1 — never synthesize one to fill the
  slot; collides with `decomposition-rules.md` → "Never invent PRD
  items"). When omitted, only `F-#, D-#` appears.
- `인용 NF` is rendered as `(none)` when empty — never blank — so the
  round-trip parser distinguishes "no cites" from "missing slot".
- `인접 TRD` is rendered as `(none)` when no adjacent slug exists.

These notes live **outside** the verbatim template block on purpose:
the block must be copy-pasteable into a real TRD with no manual
cleanup of inline annotations (#778 review).

## Why this template is built-in

`<prd-dir>/trd/_template.md` is the **project-owned** template — it
should be the source of truth in any repo that has adopted the
agent-toolbox convention. This file is the **fallback** that lets
`devx:prd-to-trd` work in repos that haven't yet bootstrapped the
template. The two must stay structurally compatible: same 8 section
headings, same frontmatter slots in the same order.

If a project edits its `<prd-dir>/trd/_template.md` to add a 9th
section or reorder frontmatter, the plan's round-trip parser still
expects the 8-section layout — re-run with `--force` to overwrite
existing scaffolds, or update this fallback in lock-step.
