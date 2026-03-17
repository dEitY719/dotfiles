# v1 Document Template

Use this template when generating initial scratch documents. Adapt sections based on the feature scope — not every section is required for every feature. Use your judgment.

```markdown
# <Feature Title>

**초안** | <tech stack if known> | <YYYY-MM-DD>

| Field | Value |
|-------|-------|
| **Document ID** | <feature-slug> |
| **Title** | <descriptive title> |
| **Type** | Feature Requirement Scratch |
| **Status** | Draft (v1) |
| **Author** | Claude |

---

## Executive Summary

<2-3 paragraphs: what this feature is, why it matters, key goals>

## 배경 (Background)

<Current state, pain points, motivation for this feature>

## 목표 (Goals)

<Bullet list of specific, measurable goals>

## 제안 설계 (Proposed Design)

### 핵심 구조

<Architecture, component breakdown, data flow — adapt depth to feature complexity>

### 주요 동작

<Key behaviors, user interactions, system responses>

## 기술 요구사항 (Technical Requirements)

<Implementation constraints, dependencies, compatibility needs>

## 에러 처리 및 엣지 케이스

<Known edge cases, error scenarios, fallback strategies>

## 범위 및 제약 (Scope & Constraints)

### In Scope
- <what this version covers>

### Out of Scope
- <what is deferred to future versions>

## 성공 지표 (Success Criteria)

| 지표 | 목표값 |
|------|--------|
| <metric> | <target> |

## 미결 사항 (Open Questions)

- [ ] <question needing resolution>
```

## Adaptation Notes

- For small features: Executive Summary + Goals + Proposed Design may suffice
- For large features: Include all sections with deep technical detail
- For urgent/hotfix features: Minimize to Executive Summary + Technical Requirements + Success Criteria
- Always include Executive Summary and Goals regardless of size
