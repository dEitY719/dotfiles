# JIRA Agent Service - Phase 1 요구사항 정의

> AI(LLM) 기반 자동 JIRA Task 생성 서비스
> 240명 규모 신규 팀의 JIRA 생성 자동화로 개발 생산성 향상

## 개요

### 배경
- **타겟 팀**: 240명 규모 신규 팀
- **주요 불편점**: 개발자들이 JIRA 생성 프로세스를 복잡하고 귀찮다고 인식
- **해결 방안**: LLM 기반 자동화로 JIRA 생성 시간 단축 및 일관성 강화

### 핵심 목표
1. JIRA 생성 프로세스 자동화로 개발자 생산성 향상
2. 회의록/문서에서 자동으로 Action Items 추출 및 JIRA Task 생성
3. 사용자 친화적인 웹 UI를 통한 간편한 JIRA 생성

---

## Phase 1: Core Features

### Primary Use Cases (3가지)

#### UC-1: 회의록 기반 Task 자동 생성

**시나리오**:
회의 후 회의록을 서비스에 입력하면, AI가 Action Items(2~3개)를 자동으로 추출하여 JIRA Task로 변환

**상세 Flow**:
1. 사용자가 웹 UI에서 회의록 텍스트 입력
2. AI가 회의록 분석:
   - 핵심 Action Items 추출
   - 각 AI에 대한 담당자/우선순위 파악
   - 예상 작업 기간 산정
3. 추출된 AI 목록 표시 (수정 가능)
4. 사용자 확인 후 JIRA Task 자동 생성
5. 생성 완료 알림 (Task ID, 링크 제공)

**입력 예시**:
```
[회의록: Q1 성능 최적화 회의]
참석자: 개발팀, 인프라팀
내용:
- 지난 데이터베이스 쿼리 최적화로 응답 시간 30% 개선 달성
- 현재 캐싱 전략 재검토 필요 (Redis 활용도 낮음)
- 프론트엔드 번들 크기 감소 추진 (현재 2.5MB)
- 이미지 최적화 및 CDN 활용도 개선 필요
- 다음달 성능 모니터링 대시보드 구축 필수
```

**생성되는 Action Items**:
```
1. [High] Redis 캐싱 전략 재검토 및 구현 - @인프라팀 리더
   Subtasks:
   - Redis 활용도 분석 및 최적화 안 수립
   - 캐싱 정책 구현 및 테스트

2. [High] 프론트엔드 번들 크기 감소 (2.5MB → 1.5MB) - @프론트엔드팀 리더
   Subtasks:
   - 번들 분석 및 불필요 라이브러리 제거
   - 코드 스플리팅 구현

3. [Medium] 성능 모니터링 대시보드 구축 - @데이터팀
   Subtasks:
   - 모니터링 메트릭 정의
   - 대시보드 개발 및 배포
```

**Expected Output**:
```json
{
  "meeting_summary": "Q1 성능 최적화 회의",
  "action_items": [
    {
      "id": "AI-001",
      "title": "Redis 캐싱 전략 재검토 및 구현",
      "priority": "High",
      "assignee_suggestion": "인프라팀 리더",
      "estimated_days": 10,
      "description": "현재 낮은 Redis 활용도를 개선하기 위한 캐싱 전략 재검토 및 구현"
    },
    {
      "id": "AI-002",
      "title": "프론트엔드 번들 크기 감소",
      "priority": "High",
      "assignee_suggestion": "프론트엔드팀 리더",
      "estimated_days": 7,
      "description": "번들 크기를 2.5MB에서 1.5MB로 감소"
    },
    {
      "id": "AI-003",
      "title": "성능 모니터링 대시보드 구축",
      "priority": "Medium",
      "assignee_suggestion": "데이터팀",
      "estimated_days": 8,
      "description": "월별 성능 지표를 추적하고 모니터링할 수 있는 대시보드 개발"
    }
  ],
  "jira_creation_ready": true
}
```

**Acceptance Criteria**:
- [ ] 회의록 입력 form 제공
- [ ] AI가 자동으로 2~3개 Action Items 추출
- [ ] 각 AI에 대해 제목, 설명, 우선순위, 담당자 제안
- [ ] 사용자가 AI 내용 수정 가능
- [ ] 수정된 AI를 JIRA Task로 생성
- [ ] 생성된 Task 링크 반환

---

#### UC-2: 세부 Task 자동 Sub-task 분해

**시나리오**:
생성된 Task가 너무 크거나 복잡할 경우, 자동으로 Sub-task로 분해

**상세 Flow**:
1. 사용자가 Task 생성 후 "Sub-task 생성" 옵션 선택
2. AI가 Task를 3~5개의 구체적인 Sub-task로 분해:
   - 개별 Sub-task는 1~3일 정도의 작업량
   - 각 Sub-task는 명확한 완료 기준 제시
   - 의존성 순서 반영 (선행 Task 표기)
3. 분해된 Sub-task 목록 표시 및 수정 가능
4. 확인 후 JIRA에 Sub-task 자동 생성

**입력 예시** (UC-1에서 생성된 Task):
```
Task: "프론트엔드 번들 크기 감소 (2.5MB → 1.5MB)"
Description: "번들 크기를 2.5MB에서 1.5MB로 감소"
```

**생성되는 Sub-tasks**:
```
1. 번들 분석 및 불필요 라이브러리 제거
   - webpack-bundle-analyzer로 번들 구성 분석
   - 미사용 라이브러리/의존성 제거
   - 예상 기간: 2일

2. 동적 코드 스플리팅 구현
   - React lazy loading 적용
   - Route-based code splitting 구현
   - 예상 기간: 3일

3. 이미지 최적화 및 lazy loading
   - 이미지 포맷 최적화 (WebP 등)
   - 이미지 lazy loading 구현
   - 예상 기간: 2일

4. 타사 라이브러리 최적화
   - Tree-shaking 최적화
   - Moment.js → date-fns 마이그레이션 (필요시)
   - 예상 기간: 2일

5. 성능 테스트 및 검증
   - LightHouse 점수 재측정
   - 실제 번들 크기 감소 확인
   - 성능 회귀 테스트
   - 예상 기간: 1일
```

**Expected Output**:
```json
{
  "parent_task": "프론트엔드 번들 크기 감소",
  "sub_tasks": [
    {
      "order": 1,
      "title": "번들 분석 및 불필요 라이브러리 제거",
      "estimated_days": 2,
      "dependencies": [],
      "checklist": [
        "webpack-bundle-analyzer 설치 및 분석",
        "미사용 라이브러리 식별",
        "의존성 제거 및 테스트"
      ]
    },
    {
      "order": 2,
      "title": "동적 코드 스플리팅 구현",
      "estimated_days": 3,
      "dependencies": ["Sub-task-1"],
      "checklist": [
        "React lazy 적용",
        "Route-based splitting 구현",
        "성능 검증"
      ]
    },
    // ... 나머지 Sub-tasks
  ]
}
```

**Acceptance Criteria**:
- [ ] Task 상세 페이지에서 "Sub-task 생성" 버튼 제공
- [ ] AI가 Task를 3~5개 Sub-task로 자동 분해
- [ ] 각 Sub-task는 1~3일 예상 기간
- [ ] 의존성 관계 표기
- [ ] Sub-task별 체크리스트 제공
- [ ] 사용자 수정 후 JIRA에 Sub-task 생성
- [ ] Parent-Child 관계 자동 설정

---

#### UC-3: 긴급 업무 기반 Task 생성

**시나리오**:
긴급 이슈/버그/요청이 발생했을 때, 간단한 설명만으로 즉시 JIRA Task 생성

**상세 Flow**:
1. 사용자가 웹 UI "긴급 Task 생성" 모드 선택
2. 간단한 형식으로 입력:
   - 현상 (What): "앱 크래시 발생"
   - 영향도 (Impact): "프로덕션, 약 50% 사용자 영향"
   - 임시 대응 (Workaround): "앱 재시작"
3. AI가 자동으로 분석:
   - 우선순위 판정 (Critical/High/Medium)
   - 예상 근본 원인 제시
   - 필요한 조치 사항 2~3개 제시
4. 사용자 검토 후 Task 생성

**입력 예시 1 - 긴급 버그**:
```
현상: "iOS 앱 구매 플로우에서 결제 버튼 클릭 시 앱 크래시 발생"
영향도: "프로덕션, 약 30% iOS 사용자 영향"
임시 대응: "Android 경로로 웹 결제 페이지 제공"
시작 시간: "2024-02-10 14:30"
```

**생성되는 Task**:
```
Priority: CRITICAL
Title: "[P0] iOS 앱 구매 플로우 크래시 - 긴급 대응"

Description:
iOS 앱 구매 플로우의 결제 버튼 클릭 시 앱이 크래시되는 긴급 이슈
- 영향도: 프로덕션 30% iOS 사용자
- 시작: 2024-02-10 14:30

Action Items:
1. [IMMEDIATE] 에러 로그 수집 및 근본 원인 파악
   - Crash 스택 트레이스 분석
   - 최근 배포 변경사항 검토
   - 회귀 버그 여부 확인

2. [URGENT] 임시 Hotfix 배포
   - 결제 버튼 비활성화 또는 웹 경로로 리다이렉트
   - 긴급 배포 진행

3. [FOLLOW-UP] 근본 원인 해결
   - 정확한 버그 원인 파악 후 수정
   - QA 검증
   - 정식 배포
```

**입력 예시 2 - 고객 긴급 요청**:
```
현상: "대형 고객사 A가 새로운 결제 수단 추가를 긴급으로 요청"
영향도: "예상 매출 50억, 이번달 말 계약 갱신 필요"
임시 대응: "영업팀이 수동 처리 중"
시작 시간: "2024-02-10 09:00"
```

**생성되는 Task**:
```
Priority: HIGH
Title: "[긴급] 새로운 결제 수단 추가 - 고객 A"

Description:
대형 고객사 A의 긴급 결제 수단 추가 요청
- 매출 규모: 약 50억 원
- 계약 갱신: 이번달 말
- 현재 영업팀이 수동 처리 중

Action Items:
1. [URGENT] 기술 요구사항 정의
   - 새 결제 수단 종류 파악
   - 예상 개발 일정 산정
   - 필요 리소스 파악

2. [THIS WEEK] 개발 계획 수립
   - 백엔드: 결제 API 연동 (3~5일)
   - 프론트엔드: UI 개발 (2~3일)
   - QA: 테스트 (1~2일)

3. [FOLLOW-UP] 개발 및 배포
   - 1차 구현 및 고객 테스트
   - 피드백 반영
   - 프로덕션 배포
```

**Expected Output**:
```json
{
  "emergency_type": "production_bug",
  "priority": "CRITICAL",
  "title": "[P0] iOS 앱 구매 플로우 크래시 - 긴급 대응",
  "impact_assessment": {
    "severity": "critical",
    "affected_users": "30% iOS users",
    "estimated_revenue_loss": "~50M KRW/hour"
  },
  "action_items": [
    {
      "sequence": 1,
      "timeline": "IMMEDIATE (next 30 mins)",
      "title": "에러 로그 수집 및 근본 원인 파악",
      "tasks": [...]
    },
    {
      "sequence": 2,
      "timeline": "URGENT (next 2 hours)",
      "title": "임시 Hotfix 배포",
      "tasks": [...]
    },
    {
      "sequence": 3,
      "timeline": "FOLLOW-UP (next 24 hours)",
      "title": "근본 원인 해결",
      "tasks": [...]
    }
  ]
}
```

**Acceptance Criteria**:
- [ ] "긴급 Task 생성" 모드 UI 제공
- [ ] 현상/영향도/임시대응 입력 필드
- [ ] AI가 자동으로 Priority 판정 (Critical/High/Medium)
- [ ] 예상 근본 원인 및 조치사항 2~3개 제시
- [ ] 사용자 검토 후 JIRA Task 생성
- [ ] 긴급 Task 라벨/태그 자동 추가
- [ ] 담당자 자동 할당 (선택 가능)

---

## Secondary Use Cases (확장 기능)

### UC-4: 이메일/Slack 메시지 기반 Task 생성

**시나리오**:
이메일 또는 Slack 메시지를 복사-붙여넣기하면 자동으로 JIRA Task 생성

**예시**:
```
Slack 메시지:
"@dev-lead 지금 API 응답 시간이 갑자기 3배 늘어났어.
뭔가 DB 쿼리가 느린 것 같은데 지금 급하게 봐줄 수 있을까?
쿼리 로그도 보내줄게"

→ Task 생성:
Priority: HIGH
Title: "[URGENT] API 응답 시간 급증 (3배) - DB 쿼리 최적화"
Description: Slack 메시지 내용 정리
Action Items: 자동 추출
```

**Acceptance Criteria**:
- [ ] 이메일 헤더 정보 추출 (제목, 발신자, 시간)
- [ ] Slack 메시지 포맷 자동 인식
- [ ] 텍스트에서 Action Items 자동 추출
- [ ] 발신자/언급된 사람 → 담당자 제안

---

### UC-5: Template 기반 빠른 Task 생성

**시나리오**:
자주 생성되는 Task 패턴을 Template로 저장해서 재사용

**예시 Templates**:
```
- "정기 배포": 배포 전 체크리스트, QA 검증, 배포 후 모니터링
- "성능 최적화": 성능 측정, 병목 분석, 최적화, 재검증
- "기술 부채 처리": 기술 검토, 개선안 수립, 구현, 테스트
- "고객 이슈": 이슈 파악, 임시 대응, 근본 원인 해결, 고객 연락
```

**사용 방식**:
```
사용자: "성능 최적화 Template 사용"
→ AI가 Template 로드 후 구체적인 항목 제안
→ 사용자가 추가 정보 입력 (타겟 지표, 팀 등)
→ Task + Sub-tasks 자동 생성
```

**Acceptance Criteria**:
- [ ] 5~10개 기본 Template 제공
- [ ] Template 커스터마이징 가능
- [ ] 팀별 Template 저장 가능
- [ ] Template 재사용 시간 50% 단축

---

### UC-6: 구조화된 양식 기반 Task 생성

**시나리오**:
정해진 양식을 채우면 자동으로 Task 생성

**예시 양식**:
```
= 버그 리포팅 양식 =
[버그 제목] _______________
[재현 방법]
  1. ___
  2. ___
  3. ___
[기대 동작] _______________
[실제 동작] _______________
[우선순위] (Critical / High / Medium / Low)
[환경] (OS, Browser, App Version)
[스크린샷/로그] (파일 첨부 가능)

→ Task 자동 생성:
- Title: 버그 제목
- Description: 양식 내용 정리
- Reproduction Steps: 구조화
- Priority: 자동 판정
- Attachments: 첨부 파일 자동 추가
```

**Acceptance Criteria**:
- [ ] 3~5개 기본 양식 제공 (버그, 기능 요청, 개선, 긴급 이슈, 고객 요청)
- [ ] 양식 자동 검증 (필수 필드 확인)
- [ ] 양식별로 다른 Task 템플릿 적용
- [ ] 파일 첨부 지원

---

## 기술 요구사항

### Frontend Requirements (REQ-F)

#### REQ-F-MainUI-1: 메인 Dashboard 페이지

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-MainUI-1** | 사용자가 3가지 Task 생성 방식을 선택할 수 있는 메인 대시보드 UI 제공 | **H** |

**Description**:
- 회의록 입력
- 긴급 Task 생성
- 템플릿 선택

**기대 출력**:
```
[메인 대시보드]
┌─────────────────────────────────┐
│  JIRA Agent - Task 생성 도우미  │
├─────────────────────────────────┤
│                                 │
│  ┌─────────────┐  ┌──────────┐  │
│  │ 📝 회의록   │  │ 🚨 긴급  │  │
│  │ Task 생성   │  │ Task    │  │
│  └─────────────┘  └──────────┘  │
│                                 │
│  ┌──────────────────────────┐   │
│  │ 📋 Template 선택        │   │
│  └──────────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

**Acceptance Criteria**:
- [ ] 3가지 입력 방식의 버튼/카드 제공
- [ ] 각 버튼 클릭 시 해당 페이지로 라우팅
- [ ] 최근 생성된 Task 목록 표시 (5개)
- [ ] 생성 완료 알림 (Toast/Modal)

---

#### REQ-F-MeetingInput-1: 회의록 입력 페이지

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-MeetingInput-1** | 사용자가 회의록을 입력하고 자동으로 Action Items를 확인할 수 있는 페이지 | **H** |

**Description**:
- 텍스트 입력 에어리어 (회의록)
- 실시간 AI 분석
- Action Items 목록 표시 및 수정 기능
- 생성 버튼

**사용 예**:
```
[입력]
회의록 텍스트 입력 → AI 분석 클릭

[출력]
1. Action Item 1 (편집 가능)
2. Action Item 2 (편집 가능)
3. Action Item 3 (편집 가능)

[생성 버튼] → JIRA Task 생성
```

**Acceptance Criteria**:
- [ ] Textarea에 회의록 입력 가능
- [ ] 500자 이상 자동 활성화되는 "AI 분석" 버튼
- [ ] 분석 결과 2~3개 Action Items 표시
- [ ] 각 Item 수정 가능 (인라인 에디팅)
- [ ] "JIRA 생성" 버튼 클릭 시 Task 생성
- [ ] 생성 완료 후 Task 링크 표시

---

#### REQ-F-EmergencyInput-1: 긴급 Task 생성 페이지

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-EmergencyInput-1** | 긴급 상황을 빠르게 입력하고 즉시 Task를 생성할 수 있는 페이지 | **H** |

**Description**:
- 구조화된 양식 (현상/영향도/임시대응)
- AI 우선순위 자동 판정
- 빠른 생성 버튼

**사용 예**:
```
[입력 양식]
현상: [텍스트 입력]
영향도: [드롭다운: 프로덕션/스테이징/개발]
임시대응: [텍스트 입력]

[AI 분석]
Priority: CRITICAL / HIGH / MEDIUM
예상 근본원인: ...
조치사항 3개: ...

[긴급 생성 버튼]
```

**Acceptance Criteria**:
- [ ] 현상, 영향도, 임시대응 입력 필드
- [ ] AI가 자동으로 Priority 판정
- [ ] Priority 색상으로 시각화 (Critical=red, High=orange)
- [ ] "지금 생성" 버튼 (1초 내 생성 완료)
- [ ] 생성 완료 후 Task 링크 + 할당 옵션

---

#### REQ-F-ActionItemEditor-1: Action Items 상세 편집 UI

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-F-ActionItemEditor-1** | 추출된 Action Items를 상세하게 편집할 수 있는 인터페이스 | **H** |

**Description**:
- 제목, 설명, 우선순위, 담당자 등 필드 편집
- 타사 정보와의 자동 연동 (팀 구조에서 담당자 자동 제안)
- 유효성 검사

**사용 예**:
```
[Action Item 편집 Panel]

제목: [입력 필드 - 자동 완성 가능]
설명: [Textarea]
우선순위: [High] ◀ ▶ [드롭다운]
담당자: [@프론트엔드팀] ◀ 자동 제안
예상 기간: [3일] ◀ 드롭다운
레이블: [성능최적화] [프론트엔드] ◀ 다중 선택

[저장] [취소]
```

**Acceptance Criteria**:
- [ ] 필드별 입력/수정 가능
- [ ] 담당자 자동 완성 (조직도 기반)
- [ ] Priority 색상 표시
- [ ] 필드 유효성 검사 (필수 필드 등)
- [ ] 실시간 미리보기

---

### Backend Requirements (REQ-B)

#### REQ-B-LLMIntegration-1: LLM 기반 Action Items 추출 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-LLMIntegration-1** | 입력된 텍스트에서 LLM을 이용해 자동으로 2~3개의 Action Items를 추출하는 API | **H** |

**Description**:
- Claude/GPT API 연동
- 회의록/이메일/긴급 상황별 프롬프트 최적화
- 추출된 AI 구조화 (제목, 설명, 우선순위, 예상기간)
- 응답 시간 < 5초

**사용 예**:
```bash
POST /api/jira-agent/extract-action-items
Content-Type: application/json

{
  "content": "회의록 텍스트...",
  "type": "meeting|emergency|email",
  "context": {
    "team": "platform-team",
    "project": "performance-optimization"
  }
}

Response:
{
  "status": "success",
  "action_items": [
    {
      "id": "ai-001",
      "title": "Redis 캐싱 전략 재검토",
      "description": "...",
      "priority": "high",
      "estimated_days": 10
    },
    // ... 2~3개 items
  ],
  "processing_time_ms": 2500
}
```

**에러 케이스**:
- Content 길이 < 100자 → 400 Bad Request
- LLM API 타임아웃 → 504 Gateway Timeout (재시도 로직 필요)
- 예정된 점검 시간 → 503 Service Unavailable

**Acceptance Criteria**:
- [ ] POST /api/jira-agent/extract-action-items 엔드포인트
- [ ] Claude/GPT 두 가지 LLM 지원 (fallback 로직)
- [ ] 응답 시간 < 5초 (대부분 2~3초)
- [ ] 추출된 AI 유효성 검사 (필수 필드 확인)
- [ ] Rate limiting (사용자당 요청 제한)
- [ ] 처리 시간 로깅

---

#### REQ-B-SubtaskGeneration-1: Sub-task 자동 분해 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-SubtaskGeneration-1** | 생성된 Task를 3~5개의 구체적인 Sub-task로 자동 분해하는 API | **H** |

**Description**:
- Task 정보 수신 (제목, 설명, 예상기간)
- LLM을 이용해 Sub-task 자동 분해
- 각 Sub-task에 대한 체크리스트, 의존성 정보 포함
- 예상 기간 재분배 (총 기간 유지)

**사용 예**:
```bash
POST /api/jira-agent/generate-subtasks

{
  "task_id": "PROJ-123",
  "title": "프론트엔드 번들 크기 감소",
  "description": "2.5MB → 1.5MB 감소",
  "estimated_days": 10,
  "context": {
    "project_key": "PROJ",
    "team": "frontend"
  }
}

Response:
{
  "status": "success",
  "subtasks": [
    {
      "order": 1,
      "title": "번들 분석 및 불필요 라이브러리 제거",
      "estimated_days": 2,
      "dependencies": [],
      "checklist": [
        "webpack-bundle-analyzer 설치",
        "번들 구성 분석",
        "미사용 라이브러리 제거"
      ]
    },
    // ... 3~5개 subtasks
  ]
}
```

**Acceptance Criteria**:
- [ ] POST /api/jira-agent/generate-subtasks 엔드포인트
- [ ] 3~5개 Sub-task 자동 생성
- [ ] 각 Sub-task 예상 기간 (1~3일)
- [ ] 의존성 관계 명시 (선행 Task)
- [ ] 각 Sub-task별 체크리스트 (3~5개 항목)
- [ ] 총 기간 재계산 및 검증

---

#### REQ-B-JIRAIntegration-1: JIRA Task 자동 생성 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-JIRAIntegration-1** | 생성된 Action Items를 JIRA Task로 자동 생성하는 API | **H** |

**Description**:
- JIRA REST API 연동
- 사용자 JIRA 계정 인증 (OAuth2)
- Task 생성 + Sub-task 계층 구조 자동 설정
- 생성된 Task ID 반환

**사용 예**:
```bash
POST /api/jira-agent/create-jira-tasks

{
  "jira_instance": "company.atlassian.net",
  "project_key": "PROJ",
  "action_items": [
    {
      "title": "Redis 캐싱 전략 재검토",
      "description": "...",
      "priority": "High",
      "assignee": "user123",
      "estimated_days": 10,
      "subtasks": [...]
    }
  ]
}

Response:
{
  "status": "success",
  "created_tasks": [
    {
      "task_id": "PROJ-123",
      "title": "Redis 캐싱 전략 재검토",
      "subtasks": [
        "PROJ-124",
        "PROJ-125"
      ],
      "jira_url": "https://company.atlassian.net/browse/PROJ-123"
    }
  ]
}
```

**에러 케이스**:
- JIRA 인증 실패 → 401 Unauthorized
- Project 없음 → 404 Not Found
- JIRA API 오류 → 500 Internal Server Error (재시도)

**Acceptance Criteria**:
- [ ] POST /api/jira-agent/create-jira-tasks 엔드포인트
- [ ] JIRA OAuth2 인증 (토큰 만료 시 갱신)
- [ ] Task + Sub-task 계층 구조 설정
- [ ] 모든 Task 필드 매핑 (Priority, Assignee, Labels 등)
- [ ] 생성 실패 시 롤백 (부분 생성 방지)
- [ ] Task ID 및 URL 반환

---

#### REQ-B-Authentication-1: 사용자 인증 및 세션 관리

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-Authentication-1** | 사용자가 로그인하고 세션을 관리할 수 있는 인증 시스템 | **H** |

**Description**:
- 회사 SSO (LDAP/Okta/Azure AD) 연동
- JIRA 계정 연동 (OAuth2)
- 세션 토큰 관리 (JWT)
- 권한 확인 (특정 Project에 대한 접근 권한)

**Acceptance Criteria**:
- [ ] SSO 로그인 지원 (회사 디렉토리)
- [ ] JIRA OAuth2 연동
- [ ] JWT 토큰 기반 세션 (24시간 유효)
- [ ] Token 갱신 엔드포인트
- [ ] 로그아웃 기능

---

#### REQ-B-TaskHistory-1: 생성된 Task 히스토리 조회 API

| REQ ID | 요구사항 | 우선순위 |
|--------|---------|---------|
| **REQ-B-TaskHistory-1** | 사용자가 본인이 생성한 Task 목록을 조회하고 관리할 수 있는 API | **M** |

**Description**:
- 사용자별 생성 Task 목록 조회 (최신순, 필터링 가능)
- 각 Task의 상태 (대기중/생성됨/실패)
- 재생성 기능 (기존 설정으로 다시 생성)

**사용 예**:
```bash
GET /api/jira-agent/task-history?limit=20&status=created

Response:
{
  "total": 145,
  "tasks": [
    {
      "id": "history-001",
      "source": "meeting",
      "created_at": "2024-02-10T14:30:00Z",
      "jira_task_id": "PROJ-123",
      "jira_task_title": "Redis 캐싱 전략 재검토",
      "status": "created",
      "action_items_count": 3
    }
  ]
}
```

**Acceptance Criteria**:
- [ ] GET /api/jira-agent/task-history 엔드포인트
- [ ] Pagination 지원 (limit, offset)
- [ ] 필터링 (status, source, date range)
- [ ] 정렬 (최신순, 오래된순, 우선순위)
- [ ] 각 항목에 JIRA Task 링크 포함

---

## Phase 1 구현 범위

### 필수 요소 (MVP)
1. ✅ UC-1: 회의록 기반 Task 자동 생성
2. ✅ UC-2: 세부 Task 자동 Sub-task 분해
3. ✅ UC-3: 긴급 업무 기반 Task 생성
4. ✅ 메인 Dashboard UI
5. ✅ 회의록 입력 페이지
6. ✅ 긴급 Task 생성 페이지
7. ✅ LLM 통합 (Action Items 추출)
8. ✅ JIRA 연동 (Task 생성)
9. ✅ 사용자 인증

### 선택 요소 (Phase 1+)
- UC-4: 이메일/Slack 메시지 기반 생성 (나중에)
- UC-5: Template 기반 생성 (나중에)
- UC-6: 구조화된 양식 생성 (나중에)
- 팀별 Template 저장 (나중에)
- Task 히스토리 조회 (나중에)

---

## 성공 지표 (Metrics)

### 사용자 측면
| 지표 | 목표 | 기간 |
|------|------|------|
| Task 생성 시간 단축 | 기존 5분 → 1분 이하 | 4주 |
| 사용률 | 240명 중 80% 이상 | 8주 |
| 만족도 | NPS 70 이상 | 8주 |

### 기술 측면
| 지표 | 목표 | 기간 |
|------|------|------|
| LLM 응답 시간 | < 5초 (평균 2~3초) | 4주 |
| JIRA 생성 성공률 | > 99% | 4주 |
| 서비스 가용성 | > 99.9% | 8주 |

---

## 위험 요소 및 완화 전략

| 위험 | 영향 | 확률 | 완화 전략 |
|------|------|------|---------|
| LLM API 과부하 | 응답 시간 지연 | 중간 | Rate limiting, Queue 시스템 도입 |
| JIRA API 호출 제한 | Task 생성 실패 | 낮음 | Batch 처리, 재시도 로직 |
| 부정확한 AI 추출 | 사용자 불만 | 중간 | 사용자 피드백 기반 학습 |
| 보안: JIRA 토큰 유출 | 계정 탈취 위험 | 낮음 | 암호화, 만료 설정, 감시 |

---

## 다음 단계

### Phase 1 완료 후 (8주 후)
1. **사용자 피드백 수집**
   - NPS 조사
   - 가장 많이 사용되는 Use Case
   - 개선 아이디어

2. **Phase 2 계획** (요구사항 문서 별도)
   - Epic/Story 자동 연결
   - JIRA comment → 메일 알림
   - Confluence 연동

3. **확장 기능**
   - 팀별 Template 커스터마이징
   - 고급 필터링 및 검색
   - 모바일 앱

---

## 부록

### A. 조직도 예시 (담당자 자동 제안용)

```
Platform Team
├── Backend Lead (user001)
│   ├── BE Engineer 1
│   └── BE Engineer 2
├── Frontend Lead (user002)
│   ├── FE Engineer 1
│   └── FE Engineer 2
└── Infra Lead (user003)
```

### B. JIRA Priority 매핑

| AI Priority | JIRA Priority | SLA |
|-------------|---------------|-----|
| Critical | Blocker | 1시간 내 시작 |
| High | High | 4시간 내 시작 |
| Medium | Medium | 1일 내 시작 |
| Low | Low | 1주 내 시작 |

### C. LLM Prompt 예시

```
Role: JIRA Task 분석 전문가

Task: 다음 회의록에서 2~3개의 구체적인 Action Items를 추출하세요.

회의록:
[USER_CONTENT]

Requirements:
1. 각 Action Item은 구체적이고 실행 가능해야 합니다
2. 우선순위는 비즈니스 영향도와 긴급도를 반영하세요
3. 예상 작업 기간은 1~10일 범위로 산정하세요
4. 담당 팀/역할을 명시하세요

Output format:
{
  "action_items": [
    {
      "title": "...",
      "description": "...",
      "priority": "high|medium|low",
      "assignee_team": "...",
      "estimated_days": 1-10,
      "subtasks": ["...", "...", "..."]
    }
  ]
}
```

---

## 문서 버전 관리

| 버전 | 작성자 | 날짜 | 변경사항 |
|------|--------|------|---------|
| v1.0 | Claude | 2024-02-10 | 초안 작성 (UC-1~3, 기본 요구사항) |
| v1.1 | - | - | UC-4~6 추가 (확장 기능) |
| v1.2 | - | - | 기술 요구사항 상세화 |

