# TRD: <component name>

> **상태**: Draft v1 (YYYY-MM-DD)
> **책임 PRD 항목**: F-# · D-# · NF-# (PRD 링크)
> **소유자**: @<github-handle>
> **인접 TRD**: (있으면 링크)

본 문서는 큰 `feat` 의 컴포넌트별 기술 설계 또는 별도 TRD 문서를
작성할 때 사용하는 범용 골격이다. 분할 단위는 **per-component** —
PRD 1개 ↔ TRD N개. 단일 mega-TRD 금지. PRD 의 D-# 횡단 결정은 여러
TRD 에 *전제로 인용*. 인스턴스 파일명은 `docs/requirement/trd-<component-slug>.md`.

## 1. Overview

<컴포넌트의 역할·범위·책임 1~2 단락.>

## 2. Goals / Non-Goals

### Goals

-

### Non-Goals

-

## 3. Architecture

> ASCII 또는 mermaid. 인접 컴포넌트와의 경계·데이터 흐름.

```
+----------+      +----------+
|  caller  | ---> |   this   | ---> ...
+----------+      +----------+
```

## 4. Components and Interfaces

> 함수 시그니처·HTTP endpoint·이벤트. 코드 경로 `src/.../` 인라인.

| 인터페이스 | 시그니처/엔드포인트 | 책임 |
|-----------|---------------------|------|
|  |  |  |

## 5. Data Models

> 스키마·DDL·타입·식별자·마이그레이션 방향. 외부 계약(파일/HTTP/이벤트
> payload) 도 포함.

```python
class Foo(BaseModel):
    id: str
    ...
```

## 6. Error Handling

> 에러 분류 (사용자 입력 / 외부 의존 / 내부 invariant 위반) 와 각
> 분류별 응답·로깅·재시도 정책.

## 7. Testing Strategy

> 단위·통합·E2E 의 경계와 분담. 회귀 방지 포인트.

## 8. Alternatives Considered

| 대안 | 거절 사유 |
|------|----------|
|  |  |

## References

- 짝 PRD 문서·인접 TRD
- 외부 표준·라이브러리 docs
- 관련 이슈/PR/커밋
