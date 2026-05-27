# Plan + Scaffold Format

Two artifacts live here:

1. The **dry-run plan** the skill writes to `--plan-out`.
2. The **TRD scaffold** rendered for each slug on `--apply`.

Both must round-trip — a plan written by this skill must be re-parsed
by this skill (Step 4), and a scaffold rendered from the plan must
parse back to the same frontmatter on a subsequent `--force` apply.

## Plan skeleton (dry-run output)

```markdown
# PRD-to-TRD Plan
Generated: <ISO 8601 local time>
Source PRD: <prd-path>
PRD directory: <dirname(prd-path)>
Mode: dry-run
Template: <_template.md path | references/template-fallback.md>

## Components

| Slug | 책임 F-# | 책임 D-# | NF-# (primary) | NF-# (cited) | 인접 TRD |
|------|----------|----------|----------------|--------------|----------|
| <slug-1> | F-1, F-2 | D-3 | NF-1 | NF-2 | <slug-2> |
| <slug-2> | F-3 | D-3 | NF-3 | NF-1 | <slug-1> |

## Suggested splits
<empty list, OR>
- <slug-X> — carries N items (>= 8), consider sub-splitting.

## Manual review
<empty list, OR>
- <slug-Y>-a / <slug-Y>-b — naming collision auto-resolved; review.
```

## Plan field rules

- **Slug column** — kebab-case, unique per plan.
- **책임 F-# / D-#** — comma-separated, no spaces around commas.
- **NF-# (primary)** — exactly one NF item owned by this TRD.
- **NF-# (cited)** — comma-separated, may be empty.
- **인접 TRD** — comma-separated slugs that share a contract. May be
  empty. References must point at slugs in the same plan.
- **Suggested splits** — rendered as `_no suggestions._` when empty.
- **Manual review** — rendered as `_none._` when empty.

## Round-trip invariant

- One row per slug in the **Components** table. Adding rows during
  `--apply` is forbidden; the user must edit the plan and re-run.
- Heading levels and ordering are stable: `## Components`,
  `## Suggested splits`, `## Manual review` in that order.
- Frontmatter block before `## Components` is line-stable
  (`Generated:` / `Source PRD:` / `PRD directory:` / `Mode:` /
  `Template:` in order).

## Scaffold layout (--apply output, per slug)

The skill writes `<prd-dir>/trd/<slug>.md` containing this skeleton.
The first eight `##` headings are mandatory — they are the
agent-toolbox 8-section standard (AI Spec-Driven 6 + Google Design
Doc 2). Body under each section is a blockquoted guidance prompt,
never AI-drafted content.

```markdown
# TRD: <Component Title> — <Project>

> **상태**: Draft v1 (<YYYY-MM-DD>)
> **책임 PRD 항목**: <F-#>, <D-#>, <NF-# primary> ([PRD](../<prd-basename>))
> **인용 NF**: <NF-# cited or "(none)">
> **소유자**: @<github-handle-placeholder>
> **인접 TRD**: <slug-A>, <slug-B> | (none)

## 1. Overview
> 1–2 문장. <Component> 가 무엇이고 책임 PRD 항목을 어떻게 충족하는지.

## 2. Goals / Non-Goals
### Goals
> 측정 가능한 목표를 bullet 으로 나열. 각 목표는 책임 F-# / NF-# 와
> 1:1 매핑되어야 함.
### Non-Goals
> 의도적으로 다루지 않는 범위를 명시 — 추후 분리될 TRD 후보.

## 3. Requirements
### Functional
> 책임 F-# 를 인용하고 본 TRD 가 구현할 단위로 재기술.
### Non-functional
> 책임 NF-# (primary) + 인용 NF-# 를 인용. 재정의 금지 — PRD §5 인용만.

## 4. Design
> "어떻게" 만 — 인터페이스 / 데이터 모델 / 시퀀스 / 에러 흐름. 본문 채우기
> 시 800줄 한계 환각 방지. 인접 TRD 와의 계약은 슬러그 링크로 기술.

## 5. Tasks / Validation
> 본 TRD 가 산출할 구현 단위. 단위 테스트 / 통합 테스트 / 수동 체크 항목.
> 각 task 는 devx:trd-to-issues 가 GitHub Issue 로 분해할 입력.

## 6. References
> 책임 PRD 항목 + 인접 TRD + 외부 spec / RFC 링크.

## 7. Alternatives Considered
> 이 디자인이 채택되지 않은 대안과 거절 사유를 표로.

## 8. Open Questions
> 결정 못 한 항목. 본 TRD 가 머지되기 전 해결 필요.
```

## Hard rules

- **Never AI-draft content under the 8 section headers.** Only the
  blockquoted guidance prompt is allowed. The human fills the body.
- **Frontmatter slot order is fixed.** 상태 / 책임 PRD 항목 / 인용
  NF / 소유자 / 인접 TRD — `--apply` writes them in this order so
  re-reads parse deterministically.
- **PRD link is relative.** Use `../<prd-basename>`; never an absolute
  path.
