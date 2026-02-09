# JIRA Agent Service - Phase 1 요구사항 정의 (v2)

> AI(LLM) 기반 자동 JIRA Task 생성 서비스
> 240명 규모 신규 팀의 JIRA 생성 자동화로 개발 생산성 향상
>
> ✅ Claude 초안 + ChatGPT UX 원칙 + Gemini 고급 기능 통합

---

## 1. 개요

### 배경 및 문제 정의

- **타겟 팀**: 240명 규모 신규 팀
- **핵심 문제**: 개발자들이 JIRA 생성 프로세스를 **복잡하고 귀찮다**고 인식
  - 회의 후 회의록 정리 → JIRA 작성 (평균 5분 소요)
  - 긴급 상황에서 빠른 추적 어려움
  - JIRA 형식 표준화 부족 → 품질 편차 큼

- **솔루션**: LLM 기반 자동화로 JIRA 생성 **5분 → 1분 이하**로 단축

### 핵심 목표

1. JIRA 생성 프로세스 자동화로 개발자 생산성 향상
2. 회의록/메모에서 자동으로 Action Items 추출 및 Task 생성
3. 팀 규칙에 맞는 **일관된 품질**의 JIRA Task 생성
4. 사용자 검토를 통한 최종 책임 보장 (Preview 필수)

---

## 2. 주요 사용자 (Personas)

### P-1: 개발자 (Contributor)

**특징**: 회의에서 정해진 일을 티켓화하는 시간을 아까워함

**니즈**:
- 빠른 생성 (1분 이내)
- 최소 수정으로 JIRA 생성 가능
- 예시: "회의에서 결정된 일 → 버튼 2-3번 클릭 → Task 생성"

**시나리오**: 스프린트 회의 후 할당받은 Task를 빠르게 JIRA에 등록하고 싶음

---

### P-2: Tech Lead / PM (Organizer)

**특징**: 회의록에서 "누가/무엇을/언제까지"를 명확히 기록하고 싶음

**니즈**:
- 회의록 기반 Task 생성 시 맥락(배경/결정사항) 포함
- 담당자/기한 자동 추출 및 제안
- 여러 건의 Task 한 번에 생성 가능
- 예시: "회의록 붙여넣기 → 2~3개 Task 자동 생성 → 담당자 확인 후 일괄 생성"

**시나리오**: 회의 내용이 정확하게 Task로 남아 추적 가능해야 함

---

### P-3: 온콜/긴급 대응 담당자 (Responder)

**특징**: 긴급 상황을 빠르게 추적하고 싶음

**니즈**:
- 정보가 부족하더라도 초안 생성 (부족한 부분은 질문)
- Priority 자동 판정 (Critical/High/Medium)
- 예상 근본원인 및 조치 순서 제시
- 예시: "문제 설명 한 줄 → Task 생성 후 팀 알림"

**시나리오**: 프로덕션 장애 → 즉시 Task 생성 → 담당자 할당 → 추적

---

## 3. 기본 UX 원칙 (Core Principles)

### 4단계 Happy Path

```
입력 (Input) → 제안 (Proposal) → 검토/편집 (Review) → 생성 (Create)
```

1. **입력**: 회의록, 메모, 채팅 로그 등 자유 형식 텍스트 입력
2. **제안**: AI가 Action Items 2~3개 + Task 초안 생성
3. **검토/편집**: Preview에서 제목/설명/담당자 등 확인 후 수정
4. **생성**: JIRA에 Task + Sub-task 생성

### 핵심 UX 원칙

| 원칙 | 설명 |
|------|------|
| **최소 인지부하** | 입력 → 생성 전까지 3-4번 클릭 이내 |
| **초안 신뢰도** | AI 초안은 기본이고, **최종 책임은 사용자** (Preview 필수 보기) |
| **효율적 편집** | JIRA 폼을 그대로 복제하기보다, **자주 고치는 필드만** 제공 |
| **안전한 실패** | 생성 실패 시 원본 입력/AI 초안이 **사라지지 않음** (재시도/복사 가능) |
| **명확한 기준** | AI가 어떤 기준으로 우선순위/담당자를 정했는지 **투명하게** 표시 |

---

## 4. Phase 1 범위

### In Scope (필수 포함)

✅ 웹 기반 Frontend에서 텍스트 입력 → Task 생성
✅ 회의록/메모/채팅 로그 등 다양한 입력 포맷 지원
✅ Action Items 2~3개 중심 Task 생성
✅ Sub-task 자동 분해 (선택/옵션)
✅ Preview 제공 (필드 편집 가능)
✅ 기본적인 오류 처리 및 재시도 UX
✅ 사용자 인증 (SSO + JIRA OAuth2)

### Out of Scope (Phase 2+)

❌ Epic/Story 읽고 자동 연결
❌ JIRA comment 기반 메일 알림
❌ Confluence MCP 연동
❌ 다국어 지원 (한국어만 Phase 1)
❌ 모바일 앱 (웹만)

---

## 5. 핵심 사용자 여정 (Happy Path)

```
1. 사용자가 웹 화면에 회의록/메모 붙여넣음
   ↓
2. (선택) 프로젝트/이슈 타입/기본 메타 선택
   ↓
3. "요약/초안 생성" 클릭 (AI 분석 시작)
   ↓
4. AI가 Action Items 2~3개 + Task 초안 생성
   (제목, 설명, 담당자 후보, 우선순위)
   ↓
5. 사용자는 Preview에서 내용 검토 및 필요시 수정
   (제목, 설명, 담당자, 기한, A/I 추가/삭제 등)
   ↓
6. "JIRA 생성" 클릭 → Task + Sub-task 자동 생성
   ↓
7. 생성된 Task 링크 + ID 반환 및 확인
```

**목표 시간**: 입력부터 생성까지 **1분 이내**

---

## 6. 입력 유형별 상세 Use Cases

### UC-1: 회의록 → 단일 Task 생성 (A/I 2~3개)

**상황**: 스프린트/설계/리뷰 회의가 끝나고 회의록이 있음

**입력 예시**:
```text
[성능 최적화 회의]
참석: Backend Lead, Frontend Lead, Infra Lead

토론 사항:
- 지난주 캐싱 구현 덕에 API 응답 시간 30% 개선 ✓
- 현재 Redis 활용도가 너무 낮음 (평균 15%)
- 프론트엔드 번들 크기 여전히 2.5MB로 크다
- 이미지 최적화와 CDN 설정도 필요

결정:
- Redis 캐싱 전략 전면 재검토 (Infra Lead 주도)
- FE 번들 크기 1.5MB 목표 설정

Action Items:
- (Infra) Redis 활용도 분석 및 개선안 수립 - 다음주 목
- (FE) 번들 분석 및 최적화 계획 - 다음주 금
- (Data) 성능 모니터링 대시보드 구축 - 2주
```

**AI 분석 결과**:

| 필드 | 값 |
|------|-----|
| **제목** | [성능 최적화] Redis 캐싱 전략 재검토 |
| **설명** | 배경: Redis 활용도 15%로 낮음 <br> 결정: 캐싱 전략 전면 재검토 <br> 목표: API 응답시간 추가 20% 개선 |
| **A/I-1** | Redis 활용도 분석 및 개선안 수립 |
| **A/I-2** | 캐싱 정책 구현 및 성능 검증 |
| **A/I-3** | 성능 모니터링 대시보드 구축 |
| **담당자** | @Infra Lead |
| **우선순위** | High |
| **기한** | 2주 |

**성공 기준**:
- 사용자가 1분 내 Preview에서 약간 수정 후 생성 가능

---

### UC-2: 회의록 → Task + Sub-task 세분화 생성

**상황**: 회의에서 나온 작업이 여러 단계로 나뉘며 담당도 다름

**입력 예시**:
```text
[프로젝트 X 킥오프 회의]

큰 목표: 새로운 결제 수단(Crypto) 지원

기술 요구:
1. 백엔드: 결제 API 연동 (3~5일)
2. 프론트엔드: 결제 UI 개발 (2~3일)
3. QA: 테스트 및 검증 (1~2일)

예상 일정: 2주

담당:
- Backend Lead: 결제 API
- Frontend Lead: 결제 UI
- QA Lead: 테스트
```

**AI 분석 결과** (부모 Task + 5개 Sub-task):

```
[상위 Task] 새로운 결제 수단(Crypto) 지원

Sub-task 1: 결제 API 명세 정의 및 설계
  - Assignee: @Backend Lead
  - Est: 2일
  - DoD: API 명세서 작성 완료

Sub-task 2: 결제 API 구현 및 테스트
  - Assignee: @Backend Lead
  - Est: 3일
  - DoD: 환경별 테스트 완료

Sub-task 3: 결제 UI 개발
  - Assignee: @Frontend Lead
  - Est: 3일
  - DoD: 프로토타입 완성, 리뷰 완료

Sub-task 4: 통합 테스트 및 버그 수정
  - Assignee: @QA Lead
  - Est: 2일
  - DoD: 주요 시나리오 테스트 통과

Sub-task 5: 프로덕션 배포 및 모니터링
  - Assignee: @DevOps
  - Est: 1일
  - DoD: 배포 완료, 모니터링 확인
```

**성공 기준**:
- Sub-task 3~5개 자동 생성
- 각 Sub-task 예상 기간 1~3일
- 의존성 관계 표기
- 사용자가 sub-task 삭제/병합해도 빠르게 생성 가능

---

### UC-3: 긴급 업무 메모 → Task 생성 (A/I 2~3개)

**상황**: "긴급 업무"를 전화/메신저로 받았고, 정리되지 않은 메모만 있음

**입력 예시**:
```text
iOS 결제 플로우에서 구매 버튼 클릭 시 앱 크래시
- 발생 시간: 2024-02-10 14:30 (30분 지속)
- 영향: 약 30% iOS 사용자 영향
- 프로덕션 환경
- 임시 대응: Android 웹 경로로 우회

필요한 조치:
1. 에러 로그 수집 및 원인 파악
2. Hotfix 배포 (긴급)
3. 근본 원인 해결 및 재배포
```

**AI 분석 결과**:

| 필드 | 값 |
|------|-----|
| **우선순위** | **CRITICAL** |
| **제목** | [P0] iOS 결제 플로우 크래시 - 긴급 대응 |
| **설명** | 현상: 결제 버튼 클릭 시 앱 크래시 <br> 영향: 프로덕션 30% iOS 사용자 <br> 임시대응: Android 웹 경로 우회 <br> 발생: 2024-02-10 14:30~ |
| **예상 근본원인** | 최근 결제 모듈 업데이트에서 메모리 누수 또는 예외 처리 누락 |
| **A/I-1 (IMMEDIATE)** | 에러 로그 수집 및 근본 원인 파악 (0.5시간) |
| **A/I-2 (URGENT)** | Hotfix 배포 (결제 버튼 비활성화 또는 우회) (1시간) |
| **A/I-3 (FOLLOW-UP)** | 근본 원인 해결 및 정식 배포 (2~3시간) |

**성공 기준**:
- 정보 부족해도 초안 생성 가능
- Priority 자동 판정 (Critical/High/Medium)
- 긴급 Task 라벨 자동 추가
- 담당자 자동 제안 (선택 가능)

---

### UC-4: 여러 안건이 섞인 회의록 → 이슈 2~N개로 분리 생성

**상황**: 하나의 회의록에 서로 다른 주제(문서, 버그, 성능, 운영)가 섞여 있음

**입력 예시**:
```text
[주간 회의록]

1) 문서 작업: API 문서 outdated 상태 → 정리 필요
2) 버그: 로그인 토큰 갱신 경합 이슈 재현됨 → 수정 필요
3) 성능: 대시보드 로딩 느림 → 캐싱 및 최적화 필요
4) 운영: 모니터링 알람 임계값 조정 필요
```

**AI 분석 결과** (기본: 1개 대표 Task + 옵션: 4개로 분리):

**Option A (단일 Task)**:
```
제목: [주간] 기술 개선 및 유지보수 작업
A/I:
  - API 문서 정리 (문서)
  - 로그인 토큰 갱신 이슈 해결 (버그)
  - 대시보드 성능 최적화 (성능)
```

**Option B (4개 분리 Task - 사용자 선택)**:
```
Task 1: API 문서 정리
Task 2: [BUG] 로그인 토큰 갱신 경합 해결
Task 3: [성능] 대시보드 로딩 최적화
Task 4: [운영] 모니터링 알람 임계값 조정
```

**UX**: Preview에서 탭/체크박스로 분리 여부 선택 → 선택된 Task만 생성

---

### UC-5: 채팅 로그 (Slack/Teams) → 결정/액션만 추출해 Task 생성

**상황**: 비동기 논의가 길게 이어졌고, 마지막에 결정과 액션이 있음

**입력 예시**:
```text
[#backend-team Slack 대화]

09:10 @alice: 요즘 DB 쿼리 성능이 너무 떨어져서..
09:15 @bob: 맞아. 특히 user_profile 조인이 문제 같아
09:20 @alice: 캐싱으로 해결될까?
09:30 @charlie: Redis 추가하면 좋겠는데, 비용 고려하면서
10:00 @alice: 좋아. 다음처럼 하자:
  1. Bob이 쿼리 분석하고 로그 남겨
  2. Charlie가 Redis 옵션 비용 계산해
  3. 내일 오전 결정하자

승인됨 ✓
```

**AI 분석 결과**:

| 필드 | 값 |
|------|-----|
| **제목** | DB 성능 최적화 전략 수립 (Redis 검토) |
| **설명** | 배경: user_profile 조인 쿼리 성능 저하 <br> 결정: 쿼리 분석 + Redis 비용 검토 후 결정 <br> 참고: @alice, @bob, @charlie 논의 |
| **A/I-1** | user_profile 쿼리 분석 및 병목 지점 파악 |
| **A/I-2** | Redis 도입 시 비용/성능 트레이드오프 분석 |
| **담당자** | @bob (쿼리), @charlie (비용) |
| **기한** | 내일 오전 (결정 회의) |

**성공 기준**:
- Slack 메시지에서 결정(Decision)과 액션(Action) 자동 추출
- 누가 말했는지에서 담당 후보 추출
- 불필요한 대화 제거 (잡음 최소화)

---

### UC-6: 개인 작업 메모 (불릿/체크리스트) → Task로 정돈

**상황**: 사용자가 TODO를 대충 적어두었고, 티켓화가 귀찮음

**입력 예시**:
```text
- 프로필 이미지 업로드 기능
- 패스워드 리셋
- 프로필 이미지 최적화
- 이미지 업로드 검증(파일 크기, 포맷)
- 프로필 페이지 UI 개선
- 패스워드 찾기 메일 발송
```

**AI 분석 결과**:

```
제목: 사용자 프로필 관리 기능 개선

A/I-1: 프로필 이미지 업로드 기능 (검증 포함)
  - 파일 크기/포맷 검증
  - 이미지 최적화 (CDN 업로드)
  - UI 개발

A/I-2: 패스워드 리셋/찾기 기능
  - 패스워드 찾기 메일 발송
  - 리셋 플로우 구현
  - 보안 검증

A/I-3: UI 개선 및 통합 테스트
  - 프로필 페이지 UI 개선
  - 기능 통합 테스트
  - 배포
```

**성공 기준**:
- 중복/유사 항목을 병합해서 A/I 2~3개로 재구성
- 필요시 Sub-task 제안 (사용자 선택)

---

### UC-7: 지나치게 짧은 입력 → 질문/보완을 통해 생성

**상황**: 입력이 "로그인 버그 처리" 정도로 지나치게 짧음

**입력 예시**: `로그인 버그 처리`

**AI 분석 결과** (초안 생성 + 질문):

| 필드 | 값 | 상태 |
|------|-----|------|
| **제목** | 로그인 버그 처리 | ⚠️ 모호함 |
| **설명** | - | ❌ 필수 정보 누락 |
| **필수 확인 사항** | | |
| - | 버그 영향 범위? (로그인 불가 / 일부 케이스 실패) | ❓ |
| - | 재현 방법? | ❓ |
| - | 완료 기준? | ❓ |
| **권장 정보** | | |
| - | 우선순위? (Critical / High / Medium) | ⓘ |
| - | 담당자? | ⓘ |
| - | 기한? | ⓘ |

**UX**: Preview에서 사용자가 위 질문들을 답변하면 Description/A/I에 자동 반영

**성공 기준**:
- 초안은 생성하되 Preview에서 필수/권장 항목 표시
- 사용자 답변 입력 시 Task 내용 자동 업데이트

---

### UC-8: 사용자가 A/I 개수를 조정 (2~3개 기본, 필요시 변경)

**상황**: 팀 규칙은 2~3개가 이상적이나, 예외적으로 더 필요함

**기본 Flow**:
```
AI가 2~3개 A/I 생성 (기본값)
  ↓
Preview에서 "A/I 더 보기" 클릭
  ↓
4~6개 후보 추가 제시 (중복/의존성 표기)
  ↓
사용자가 최종 포함 항목 선택 (체크박스)
  ↓
선택된 A/I만 Task에 포함되어 생성
```

**예시**:
```
원본 (2~3개):
✓ A/I-1: 백엔드 구현
✓ A/I-2: 프론트엔드 개발
✓ A/I-3: QA 테스트

"더 보기" 클릭 후 (4~6개):
✓ A/I-1: 백엔드 구현
  ✓ A/I-1a: API 명세 정의 (A/I-1에 의존)
✓ A/I-2: 프론트엔드 개발
  ✓ A/I-2a: 디자인 시스템 검토 (A/I-2에 의존)
✓ A/I-3: QA 테스트
✓ A/I-4: 배포 및 모니터링 (NEW)
```

**성공 기준**:
- 기본 2~3개 제시
- "더 보기" 선택 시 추가 4~6개 후보 제시
- 의존성 명시
- 사용자 선택 후 반영

---

### UC-9: 기존 JIRA 이슈에 Sub-task만 추가 생성

**상황**: 상위 Task는 이미 존재하고, 회의/메모에서 나온 실행 항목만 sub-task로 추가하고 싶음

**입력 예시**:
```text
Parent Issue: PROJ-123 (기존 Task: "새로운 결제 수단 지원")

새 회의에서 추가 Action Items:
1. 보안 검수 (PCI DSS 준수 확인)
2. 성능 테스트 (트래픽 증가 시뮬레이션)
3. 고객사 통지 (새 수단 가이드 문서 작성)
```

**AI 분석 결과**:

```
Parent: PROJ-123 (기존 유지)

새 Sub-task:
- Sub-1: PCI DSS 보안 검수
- Sub-2: 성능 테스트 (트래픽 증가 시뮬레이션)
- Sub-3: 고객사 가이드 문서 작성 및 배포
```

**UX**: 기존 Task 수정 없이 Sub-task만 생성 + Parent 관계 자동 설정

**성공 기준**:
- Parent 이슈 키 입력/선택 (자동 검증)
- A/I 추출해서 Sub-task 2~5개 생성
- 기존 Task 수정 없음

---

### UC-10: 민감정보/개인정보 포함 입력 → 경고 및 마스킹 제안

**상황**: 회의록/메모에 전화번호, 계정정보, 고객식별자 등 민감정보가 섞일 수 있음

**입력 예시**:
```text
고객 A의 결제 문제:
- 고객 번호: CS-12345678
- 연락처: 010-1234-5678
- 계정: user@company.com
- 문제: 결제 실패 (에러 코드 5001)
```

**AI 분석 결과** (Preview 화면):

```
⚠️ 민감정보 감지됨
┌─────────────────────────────────┐
│ 고객 A의 결제 문제:              │
│ - 고객 번호: [고객_ID]          │ ← 마스킹됨
│ - 연락처: [휴대폰_번호]         │ ← 마스킹됨
│ - 계정: [이메일]               │ ← 마스킹됨
│ - 문제: 결제 실패 (에러 코드 5001) │
│                                 │
│ ☐ 마스킹 유지                  │ (기본)
│ ☐ 마스킹 해제 (원본 사용)      │
│ ☐ 해당 부분 삭제               │
└─────────────────────────────────┘
```

**AI 분석 결과** (Task 생성):

```
제목: 고객 A 결제 실패 문제 해결

설명:
고객 [고객_ID]의 결제 실패 이슈
에러 코드: 5001
```

**성공 기준**:
- 생성 전 Preview에서 민감정보 하이라이트
- 자동 마스킹 제안
- 사용자가 마스킹/해제/삭제 선택 가능
- JIRA로 전송되는 최종 내용은 Preview의 편집 결과 사용

---

### UC-11 (추가): 중복 탐지 - 유사 Task 존재 여부 확인

**상황**: 비슷한 내용의 Task가 이미 존재할 수 있음

**AI 분석 결과** (Preview 상단):

```
⚠️ 유사한 기존 Task를 찾았습니다:

[추천] 기존 PROJ-102: "결제 수단 최적화"
 - 작성: 2주 전
 - 상태: In Progress
 - 담당: @Backend Lead

이 Task를 업데이트하시겠어요? 아니면 새로 생성하시겠어요?
[ 기존 Task 업데이트 ] [ 새로 생성 ] [ 무시하기 ]
```

**성공 기준**:
- 최근 JIRA 이슈 검색 (Vector/Keyword 기반)
- 유사도 점수 표시
- 사용자 선택 (업데이트 vs 신규 생성)

---

### UC-12 (추가): 보안 이슈 자동 플래그 - Priority Escalation

**상황**: 보안/법적 민감 이슈가 감지되면 자동 플래그

**입력 예시**: `발견된 unauthenticated API endpoint가 사용자 이메일을 유출`

**AI 분석 결과**:

```
⚠️ 보안 이슈 감지됨

키워드: "unauthenticated", "leaks", "emails"
권장 Priority: 🔴 BLOCKER (자동 상향)
자동 라벨:
  ✓ security-vulnerability
  ✓ urgent
  ✓ requires-security-review

제목 제안: 🔴 [SECURITY] Unauthenticated API 엔드포인트 - 사용자 이메일 유출

Description:
발견: Unauthenticated API endpoint 존재
영향: 사용자 이메일 유출
심각도: Critical
권장: 즉시 비활성화 후 보안팀 검수

담당자 제안: @Security Lead (자동 지정)
```

**성공 기준**:
- 보안 키워드 감지 (unauthenticated, leak, vulnerability, sql-injection 등)
- Priority 자동 상향 (High → Blocker)
- 보안팀 자동 지정/알림

---

### UC-13 (추가): 다중 담당자 Task 생성 - Multi-Assignee Cloning

**상황**: 여러 사람이 동일한 Task를 처리해야 함

**입력 예시**:
```text
모든 개발자는 필수 보안 교육을 완료해야 함
(마감: 이번 달 말)
```

**AI 분석 결과** (Preview):

```
제목: [필수] 2024년 보안 교육 완료

이것은 팀 전체 대상 Task입니다.

담당자 선택 (복수 선택):
☑ @dev-1
☑ @dev-2
☑ @dev-3
☑ @dev-4
☑ @dev-5
... (팀 인원 수만큼)

생성 방식:
○ 1개 Task에 여러 담당자 지정 (JIRA Assignee는 첫 번째만)
● 담당자별 5개 동일 Task 생성 (권장)
  → 각자 Task ID: PROJ-201, PROJ-202, ..., PROJ-205
```

**성공 기준**:
- 다중 선택 UI 제공
- 1개 Task vs N개 Task 옵션 제공
- N개 생성 시 각각 독립 Task ID 할당

---

## 7. Preview & 편집 요구사항

### 필수 편집 필드 (항상 표시)

| 필드 | 설명 | 예시 |
|------|------|------|
| **Project** | JIRA Project 선택 | PROJ, MOBILE, DATA |
| **Issue Type** | Task (기본) | Task, Bug, Story |
| **Summary** | Task 제목 | "Redis 캐싱 전략 재검토" |
| **Description** | Task 본문 (배경/목표) | "배경: ... 결정: ..." |
| **Action Items** | 체크리스트 형태 | "[ ] A/I-1 ...", "[ ] A/I-2 ..." |

### 선택 편집 필드 (팀 설정에 따라)

| 필드 | 설명 | 옵션 |
|------|------|------|
| **Assignee** | 담당자 | 조직도 검색 |
| **Due Date** | 마감 기한 | Date Picker |
| **Priority** | 우선순위 | Critical, High, Medium, Low |
| **Labels** | 라벨 | 태그 자동완성 |
| **Components** | 컴포넌트 | 프로젝트별 사전정의 |
| **Sprint** | 스프린트 | 활성 스프린트 목록 |

### Sub-task 편집 (있을 때만)

```
Parent Task 편집 필드
  ↓
각 Sub-task 편집:
  - Summary (제목)
  - Description (본문)
  - Assignee (담당자)
    ☐ 상속 옵션 (Parent 값 상속 후 개별 수정)
  - Due Date (기한)
    ☐ 상속 옵션
```

### Preview 화면 레이아웃

```
┌─────────────────────────────────────────┐
│ JIRA Task Preview                       │
├─────────────────────────────────────────┤
│                                         │
│ [Project] [Issue Type]                  │
│                                         │
│ Summary (제목)                          │
│ ┌─────────────────────────────────────┐ │
│ │ [입력 필드 - 수정 가능]             │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Description (설명)                      │
│ ┌─────────────────────────────────────┐ │
│ │ [Textarea - 수정 가능]              │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Action Items                            │
│ ┌─────────────────────────────────────┐ │
│ │ ☐ A/I-1: ...  [×] [↑] [↓]          │ │
│ │ ☐ A/I-2: ...  [×] [↑] [↓]          │ │
│ │ ☐ A/I-3: ...  [×] [↑] [↓]          │ │
│ │ [+ 항목 추가]                       │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Assignee: [@담당자 검색]                │
│ Due Date: [Date Picker]                 │
│ Priority: [High ▼]                      │
│                                         │
│ [← 수정] [JIRA 생성 →]                 │
│                                         │
└─────────────────────────────────────────┘
```

---

## 8. 오류 & 예외 UX (Exception Handling)

### E-1: JIRA 권한/인증 실패

```
❌ JIRA 인증 실패

원인: 토큰 만료 또는 접근 권한 없음

해결 방법:
[ JIRA 다시 연결 ] → OAuth 재인증
[ 계속 (초안 저장) ] → Task 초안을 로컬 저장 후 나중에 생성

⚠️ Task 초안은 안전하게 보관되어 있습니다.
```

### E-2: 필수 필드 누락/검증 오류

```
❌ 필드 검증 실패

Project: ✓
Summary: ✗ 필수 필드입니다

구체적 오류:
"Summary (제목)가 비어있습니다.
 최소 5글자 이상 필요합니다."

[← Summary로 이동] [수정 후 재시도]
```

### E-3: JIRA API 실패/타임아웃

```
❌ JIRA 생성 중 오류 발생

원인: 네트워크 연결 끊김 또는 JIRA 서버 응답 없음

옵션:
[ 재시도 (자동) ] → 3초 후 재시도
[ 초안 복사 ] → 클립보드에 복사해 수동 생성
[ 로컬 저장 ] → 브라우저에 임시 저장 (나중에 재시도)

진행 상황: [████░░░░░] 50% 완료 (3초 후 재시도)
```

### E-4: LLM 응답 실패

```
❌ AI 분석 실패

원인: LLM API 타임아웃 또는 과부하

옵션:
[ 간단 모드로 생성 ] → 템플릿 기반 최소 Task 생성
  (제목/본문만으로 Task 생성, A/I는 수동 추가)

[ 5초 후 재시도 ]

또는 수동으로 다시 시작:
[ 입력 초기화 ] → 처음부터 새로 입력
```

---

## 9. 품질 기준 (Quality Standards)

생성되는 Task는 최소한 아래를 만족해야 함:

### Q-1: 명확성 (Clarity)
- ✅ 제목이 모호하지 않음 (주체/행동 명확)
- ✅ 대상/대상층이 드러남
- ❌ 예: "작업 처리" → "로그인 토큰 갱신 경합 이슈 해결"

### Q-2: 내용 충실도 (Content Completeness)
- ✅ Description에 배경/목표/완료 조건 중 2개 이상 포함
- ✅ "왜 필요한가", "언제까지인가", "어떻게 완료되는가" 명확
- ❌ 빈 설명 또는 한 문장만 있는 경우

### Q-3: 실행 가능성 (Actionability)
- ✅ A/I가 실행 가능하고 측정 가능
- ✅ 산출물/검증 기준 포함 (Definition of Done)
- ❌ 예: "성능 개선" → "Redis 캐싱 구현 → LightHouse 점수 80 이상 확인"

### Q-4: 완료 조건 (Definition of Done)
- ✅ 각 Sub-task에 명확한 완료 조건 포함
- ✅ 검증 방법 명시
- ❌ "완료되면 끝" vs "테스트 통과 + PR 리뷰 + 배포"

---

## 10. 기술 요구사항 (Technical Requirements)

### Frontend (REQ-F)

#### REQ-F-UI-1: 메인 Dashboard

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-UI-1** | 3가지 Task 생성 방식을 선택할 수 있는 메인 대시보드 UI | **H** |

- 회의록 입력 카드
- 긴급 Task 생성 버튼
- 템플릿/양식 선택
- 최근 생성 Task 목록 (5개)

#### REQ-F-UI-2: 텍스트 입력 & AI 분석 페이지

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-UI-2** | 텍스트 입력 후 AI 분석을 트리거하고 Action Items를 표시 | **H** |

- Textarea (500자 이상 시 버튼 활성화)
- "AI 분석" 버튼 (로딩 상태)
- Action Items 목록 (2~3개, 인라인 편집 가능)
- 다음 단계로 이동 버튼

#### REQ-F-UI-3: Preview & 편집 페이지

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-UI-3** | AI 생성 내용을 Preview하고 모든 필드를 편집할 수 있는 UI | **H** |

- 좌측: Preview (최종 모습)
- 우측: 편집 필드 (Project, Summary, Description, A/I, Assignee 등)
- 실시간 Preview 업데이트
- "JIRA 생성" / "뒤로가기" 버튼

#### REQ-F-UI-4: 에러 & 예외 처리 UI

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-UI-4** | 각 단계별 실패 상황에 대한 명확한 오류 메시지와 복구 옵션 제공 | **H** |

- 권한 오류: "JIRA 재연결" 옵션
- 필드 오류: 해당 필드로 포커스 이동
- API 오류: "재시도" + "초안 복사" 옵션
- LLM 실패: "간단 모드" 폴백

### Backend (REQ-B)

#### REQ-B-LLM-1: Action Items 추출 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-LLM-1** | 텍스트에서 자동으로 2~3개 Action Items를 추출하는 API | **H** |

**Endpoint**: `POST /api/v1/jira-agent/extract-action-items`

**Request**:
```json
{
  "content": "회의록/메모 텍스트",
  "content_type": "meeting|urgent|chat|note|email",
  "project_key": "PROJ",
  "context": {
    "team": "backend-team",
    "timestamp": "2024-02-10T10:00:00Z"
  }
}
```

**Response**:
```json
{
  "status": "success",
  "action_items": [
    {
      "id": "ai-001",
      "title": "Redis 캐싱 전략 재검토",
      "description": "...",
      "priority": "high",
      "estimated_days": 10,
      "suggested_assignee": "infra-lead",
      "reasoning": "이전 논의에서 Redis 활용도가 낮다고 언급됨"
    }
  ],
  "processing_time_ms": 2500
}
```

**SLA**: < 5초 (대부분 2~3초)
**지원 LLM**: Claude 3.5 Sonnet, GPT-4o (fallback)

#### REQ-B-JIRA-1: Task 생성 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-JIRA-1** | 생성된 Task를 JIRA에 자동 생성 | **H** |

**Endpoint**: `POST /api/v1/jira-agent/create-task`

**Request**:
```json
{
  "jira_instance": "company.atlassian.net",
  "project_key": "PROJ",
  "issue_type": "Task",
  "summary": "Redis 캐싱 전략 재검토",
  "description": "...",
  "assignee": "user@company.com",
  "priority": "High",
  "due_date": "2024-02-20",
  "labels": ["performance", "backend"],
  "action_items": [
    {
      "title": "A/I-1",
      "description": "..."
    }
  ],
  "subtasks": [...]
}
```

**Response**:
```json
{
  "status": "success",
  "task_id": "PROJ-123",
  "task_url": "https://company.atlassian.net/browse/PROJ-123",
  "subtask_ids": ["PROJ-124", "PROJ-125"],
  "created_at": "2024-02-10T10:05:00Z"
}
```

**SLA**: < 3초
**인증**: OAuth2 (JIRA Personal Access Token)

#### REQ-B-DupDetection-1: 중복 탐지 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-DupDetection-1** | 기존 Task와의 중복 여부를 감지하고 제안 | **M** |

**Endpoint**: `POST /api/v1/jira-agent/detect-duplicates`

**Request**:
```json
{
  "project_key": "PROJ",
  "summary": "Redis 캐싱 전략 재검토",
  "description": "...",
  "similarity_threshold": 0.7
}
```

**Response**:
```json
{
  "status": "success",
  "similar_tasks": [
    {
      "task_id": "PROJ-102",
      "summary": "성능 최적화 - 캐싱 전략",
      "similarity_score": 0.82,
      "status": "In Progress",
      "assignee": "infra-lead"
    }
  ]
}
```

#### REQ-B-Auth-1: SSO & JIRA OAuth2 인증

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-Auth-1** | 회사 SSO + JIRA OAuth2 연동 | **H** |

- SSO (LDAP/Okta/Azure AD)
- JIRA OAuth2 (권한 확인)
- JWT 토큰 세션 (24시간 유효)
- Token 갱신 엔드포인트

---

## 11. Phase 1 완료 기준 (Definition of Done)

### 기능 완료

- ✅ UC-1~10 (13개 Use Case 모두 지원)
- ✅ Action Items 추출 (2~3개)
- ✅ Sub-task 자동 분해
- ✅ Preview & 편집
- ✅ JIRA 생성 (Task + Sub-task)
- ✅ 중복 탐지
- ✅ 보안 이슈 플래그
- ✅ 민감정보 마스킹

### 품질

- ✅ 생성 Task 품질 기준 Q-1~Q-4 충족
- ✅ 성능: LLM 응답 < 5초, JIRA 생성 < 3초
- ✅ 가용성: > 99.9%

### 테스트

- ✅ 단위 테스트 (LLM, JIRA API)
- ✅ 통합 테스트 (End-to-End)
- ✅ 사용자 테스트 (베타 그룹 5명, NPS 70+)

### 문서

- ✅ 사용자 가이드 (온보딩)
- ✅ 기술 문서 (API 명세)
- ✅ 팀 가이드라인 (JIRA Task 표준)

---

## 12. 성공 지표 (Metrics)

### 사용자 측면

| 지표 | 목표 | 기간 | 측정 방법 |
|------|------|------|---------|
| **Task 생성 시간 단축** | 5분 → 1분 이하 (80% 감소) | 4주 | 사용자 설문 |
| **사용률** | 240명 중 80% 이상 | 8주 | DAU/MAU 추적 |
| **만족도 (NPS)** | 70 이상 | 8주 | NPS 조사 |

### 기술 측면

| 지표 | 목표 | 기간 | 측정 방법 |
|------|------|------|---------|
| **LLM 응답 시간** | < 5초 (평균 2~3초) | 4주 | 로그 분석 |
| **JIRA 생성 성공률** | > 99% | 4주 | 에러율 추적 |
| **서비스 가용성** | > 99.9% | 8주 | Uptime 모니터링 |

---

## 13. 위험 요소 및 완화 전략

| 위험 | 영향 | 확률 | 완화 전략 |
|------|------|------|---------|
| LLM API 과부하 | 응답 지연 (5초 → 30초+) | 중 | Rate limiting, Queue, 요금제 상향 |
| JIRA API 호출 제한 | Task 생성 실패 | 낮음 | Batch 처리, 재시도 로직 |
| 부정확한 AI 추출 | 사용자 불만 | 중 | 사용자 피드백 기반 학습 (Phase 2) |
| JIRA 토큰 유출 | 계정 탈취 위험 | 낮음 | 암호화, 토큰 만료, 감시 |
| 사용자 기대치 불일치 | 채택률 저하 | 중 | 명확한 온보딩 + 단계적 롤아웃 |

---

## 14. Phase 2 로드맵 (Future Enhancements)

### Phase 2 예상 기능

1. **Epic/Story 자동 연결** (UC-2의 연장)
   - Task 생성 시 상위 Epic/Story 자동 감지
   - 프로젝트 구조 학습

2. **JIRA Comment → 메일 알림** (Assigner 중심)
   - Comment 생성/업데이트 시 Assigner에게 이메일
   - 스레드 기반 추적

3. **Confluence MCP 연동**
   - 회의록 자동 연동
   - 노션/문서와 Task 링크

4. **팀별 Template 커스터마이징**
   - 팀별 JIRA 표준 자동 학습
   - 재사용 Template 저장

5. **AI 학습 (Phase 2+)**
   - 사용자 피드백 기반 프롬프트 개선
   - 팀별 패턴 학습

---

## 부록

### A. 기술 스택

| 계층 | 기술 | 선택 이유 |
|------|------|---------|
| **Frontend** | React 18 + TypeScript | 모던, 타입 안전 |
| **UI Framework** | Mantine / TailwindCSS | 빠른 개발, 반응형 |
| **State Management** | Zustand / Jotai | 경량, 간단함 |
| **Backend** | FastAPI (Python 3.11+) | 빠름, 비동기 지원 |
| **LLM API** | Claude 3.5 Sonnet, GPT-4o | 품질, Fallback |
| **JIRA Integration** | JIRA REST API v3 | 공식 지원 |
| **Database** | PostgreSQL | 안정성, 트랜잭션 |
| **Cache** | Redis | 성능, 세션 관리 |
| **Queue** | Celery + RabbitMQ | 비동기 작업 (LLM 요청) |
| **Monitoring** | Prometheus + Grafana | 가시성 |

### B. JIRA Priority 매핑

| AI Priority | JIRA Priority | SLA |
|-------------|---------------|-----|
| Critical | Blocker | 1시간 내 시작 |
| High | High | 4시간 내 시작 |
| Medium | Medium | 1일 내 시작 |
| Low | Low | 1주 내 시작 |

### C. 샘플 LLM Prompt

```
Role: JIRA Task 분석 및 생성 전문가

Task: 다음 회의록/메모에서 2~3개의 구체적인 Action Items를 추출하세요.

Content:
[USER_INPUT]

Requirements:
1. 각 Action Item은 구체적이고 실행 가능해야 함
2. 우선순위는 비즈니스 영향도와 긴급도 반영
3. 예상 작업 기간: 1~10일 범위
4. 담당 팀/역할 명시
5. Definition of Done 포함

Output Format:
{
  "task_title": "...",
  "task_description": "배경: ...\n결정: ...",
  "action_items": [
    {
      "title": "...",
      "description": "...",
      "priority": "high|medium|low",
      "assignee_team": "...",
      "estimated_days": 3,
      "definition_of_done": ["...", "...", "..."]
    }
  ]
}
```

### D. 조직도 예시 (자동완성용)

```
Platform Team (PT)
├── Backend Team (PT-BE)
│   ├── Backend Lead (user001)
│   ├── Senior BE Engineer (user002)
│   └── BE Engineer (user003)
├── Frontend Team (PT-FE)
│   ├── Frontend Lead (user004)
│   ├── Senior FE Engineer (user005)
│   └── FE Engineer (user006)
└── Infra Team (PT-INFRA)
    ├── Infra Lead (user007)
    └── Infra Engineer (user008)
```

---

## 15. 문서 버전 관리

| 버전 | 작성자 | 날짜 | 변경사항 |
|------|--------|------|---------|
| v1.0 | Claude | 2024-02-10 | 초안 (3개 Primary UC + 기술 명세) |
| v2.0 | Claude (통합) | 2024-02-10 | **CX의 10개 UC + Gemini 기능 통합** |
| | | | - Personas 3가지 추가 |
| | | | - UX 원칙 (4단계 Happy Path) |
| | | | - UC 13개 (기존 3+3 → 13개로 확대) |
| | | | - 중복 탐지 + 보안 플래그 + 다중 담당자 |
| | | | - 오류/예외 UX 상세화 |
| | | | - 기술 스택 명시 |
| v2.1 | - | - | Phase 2 로드맵 추가 예정 |

---

## 요약

JIRA Agent Phase 1은 **"회의록/메모 → 2~3 Action Items → JIRA Task"** 자동화 서비스입니다.

### 핵심 가치

✅ **개발자 생산성**: Task 생성 시간 5분 → 1분으로 단축
✅ **품질 일관성**: AI 기반 표준화된 Task 생성
✅ **빠른 대응**: 긴급 상황 즉시 추적
✅ **사용자 신뢰**: Preview를 통한 최종 검증

### 차별점

- **13가지 다양한 Use Case** (회의록, 채팅, 메모, 긴급 등)
- **3가지 Persona 중심** (개발자, Lead, 온콜)
- **고급 기능** (중복 탐지, 보안 플래그, 다중 담당자)
- **견고한 예외 처리** (오류 시 초안 유지, 복구 옵션)

### 성공을 위한 필수 조건

1. **사용자 온보딩** 철저 (처음 사용할 때 명확한 가이드)
2. **점진적 롤아웃** (베타 그룹 5명 → 팀 전체)
3. **지속적인 피드백** 수집 (UI/UX 개선)
4. **팀 표준 가이드** 수립 (JIRA Task 작성 규칙)

