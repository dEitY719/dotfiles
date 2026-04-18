# 파트 독립 영역 Structure — Paste-Ready JIRA Stories

AI Enable 파트의 **파트 Epic (PE-1)**, **파트 레벨 Story (P-1..P-5)**, **핵심제품 Story (K-1..K-4)**. PE-1 은 P-Story 들의 상위 Epic.

각 Epic/Story 는 `### Summary` / `### Parent / 팀 Epic 연결` / `### Description` 3부분 — JIRA 티켓 생성 시 각 섹션의 코드 블록을 통째로 복사.

---

## PE-1 파트 Epic — 임직원 AI 효용성 체감 및 시장 확산

> 파트 미션·비전을 담는 최상위 Epic. P-1~P-5 및 K-1~K-4 Story 의 **나침반(North Star)** 역할.

### Summary
```text
[AIE M&V] 임직원이 체감하는 AI 효용성 — 현업 수요 중심 AI 제품 라인업 구축
```

### Parent / 팀 Epic 연결
파트 독립 영역 최상위 Epic — 팀 Epic(E1~E4)과 병렬. 하위에 P-1~P-5, K-1~K-4 Story 배치.

### Description
```text
■ 미션 (Mission)
임직원들이 개발 업무에서 AI 의 효용성을 체감하는 것.

■ 비전 (Vision)
우리가 가진 기술과 능력이 세상의 빛을 보기 위해서는 고객을 찾아 시장으로 가야 한다.
창업자의 흔한 실수는 자신이 관심을 가지는 문제에만 중점을 두는 것이며,
그보다 중요한 것은 시장의 규모다.

■ 에픽 배경
- 공급자(개발자) 중심 사고에서 시장(임직원)·효용 중심 사고로 전환
- 단순 기술 과시형 프로젝트 지양, 수요(Market Demand)가 명확한 제품에 집중
- "고맙다"는 인사가 아닌, 데이터로 증명되는 체감·확산 지표(MAU, 절감 MM)로 성과 측정
- SSOT 기반 운영 — 모든 제품의 효용성 지표는 통합 관리, 중복·분산 금지

■ 핵심 전략
1. Customer-Centric — 개발자가 만들고 싶은 기능이 아닌, 현업이 고통받는 지점을 해결
2. Market-Size First — 소수용 툴보다 전사 임직원이 사용할 범용 가치에 우선순위
3. Measurable Impact — "체감"을 정성 평가가 아닌 정량 지표(MAU·세션·자동화 건수)로 증명
4. SSOT 운영 — 효용성 지표·KPI 를 통합 관리, 제품 간 중복·분산 금지

■ 하위 Story 구조
- P-1 조직목표달성 (50%) — OKR 기반 파트 핵심과제
  └ K-1 SLSI Agent App Store — 임직원 참여형 AI 앱 생태계
  └ K-2 SLSI Alpha Agent — 사내 시스템 연동 개인화 Agent
  └ K-3 SLSI Cowork — 비SW 직군 포함 문서 특화 범용 Agent
  └ K-4 MCP/Skill Hub — 고품질 Skill 공유 및 BP 전파
- P-2 혁신/개선업무 (20%) — 프로세스 개선 및 AI Tool 제작
- P-3 조직시너지 창출 (20%) — 타 조직 협업 및 파트 간 시너지
- P-4 부서원역량강화 (10%) — 파트원 역량 개발·SCI 관리·기술 지식 공유
- P-5 수명업무 (0%, Tracking-only) — 비계획 지시 업무 추적 버킷

■ 성공 기준 (North Star Metrics)
- 체감 지표 : 사용자 만족도(NPS), 재방문율, 평균 세션 시간
- 확산 지표 : MAU / DAU, 등록 앱·Skill 수, 연동 사내 시스템 수
- 가치 지표 : 업무 절감 MM, 자동화 건수, 사업부 기여도
- 품질 지표 : BP 확산률, Skill·MCP 재사용률

■ 자문 기준 (Guiding Questions)
- 우리는 지금 정말 시장(임직원)이 원하는 것을 만들고 있는가?
- 이 기능은 "개발자가 재미있는 문제"인가, "현업이 고통받는 문제"인가?
- 성공 여부를 "고맙다" 대신 어떤 숫자로 증명할 것인가?

■ 기간
2026.04 ~ 2026.10
```

---

## P-1 조직목표달성 (50%)

### Summary
```text
[AIE O-1] 2026 조직목표달성 - OKR 기반 핵심과제 달성
```

### Parent / 팀 Epic 연결
E4 (Avatar 7000명) → SWINNOTEAM-1274 (Document Agent) 하위에 배치

### Description
```text
■ 목적
AI Enable 파트의 2026년 핵심과제를 OKR 프레임워크로 정의하고,
팀 Epic [E4: Avatar 7000명 양성]의 달성에 기여한다.

■ 팀 과제 연결
- 팀 Story: SWINNOTEAM-1274 (Document Agent 개발, MAU ≥ 5,000명)
- 파트의 핵심과제는 위 팀 Story의 하위 Initiative로 연결

■ 파트 핵심 제품 라인업 (하위 Story로 관리)
- K-1: SLSI Agent App Store — 사내 AI 앱 스토어
- K-2: SLSI Alpha Agent — 개인화된 대화형 Agent
- K-3: SLSI Cowork — 문서 특화 범용 Agent
- K-4: MCP/Skill Hub — 사내 MCP 마켓플레이스

■ 평가 기준 (비중 50%)
- 핵심과제 3개 이하로 설정 (PL 기준)
- OKR 구성: Objective → Key Result → Initiative → KPI
- KPI는 측정 가능한 숫자로 정의
- OKR은 임원 승인 필수
- 최소 월 1회 1:1을 통한 진행상황 점검 및 피드백

■ 업무 권한 Level
- L3: 스스로 의사결정을 주도하며 주어진 목표 달성 (결과 부서장 보고)
- L2: 수립한 목표 또는 과제를 리딩하며 동료와 함께 목표 달성
- L1: 부서장/동료의 지시 또는 가이드를 받아 공동의 목표 달성
※ 본 Story 의 각 OKR/Initiative 별로 Level 지정

■ 운영 방식
- 4월: OKR 수립 및 임원 승인
- 매월: 1:1 feedback (진행률, 장애요인, 조정사항)
- 분기별: KPI 달성률 리뷰

■ 성과 측정
- KPI 달성률 (정량)
- 과제 영향도 — 사업부 기여도 (정성)
- 일정 준수 및 실행력

■ 기간
2026.04 ~ 2026.10
```

---

## P-2 혁신/개선업무 (20%)

### Summary
```text
[AIE O-2] 2026 혁신/개선업무 - 프로세스 개선 및 AI Tool 제작
```

### Parent / 팀 Epic 연결
E3 (SW개발/검증 생산성 향상 도구) 간접 연결 — 파트 독립 영역

### Description
```text
■ 목적
파트 내 공통 업무 프로세스를 개선하고,
업무 효율화를 위한 Tool/AI를 제작하여 팀에 기여한다.

■ 평가 기준 (비중 20%)
- 팀 내 공통 업무 개선
- Jira/Confluence 기반 업무 프로세스 개선
- AI Tool 및 자동화 시스템 개발
- Global PL 운영 개선 (해당 시)

■ 업무 권한 Level
- L3: 스스로 의사결정을 주도하며 주어진 목표 달성 (결과 부서장 보고)
- L2: 수립한 목표 또는 과제를 리딩하며 동료와 함께 목표 달성
- L1: 부서장/동료의 지시 또는 가이드를 받아 공동의 목표 달성
※ 본 Story 의 각 OKR/Initiative 별로 Level 지정

■ 주요 활동 방향
- 반복 업무 자동화 Tool 개발
- AI 활용 업무 효율화 솔루션 제작
- 기존 프로세스 분석 및 개선안 도출

■ 성과 측정
- 업무 효율 개선 효과 (시간/비용 절감 — 정량)
- 자동화 수준 및 재사용성
- 조직 내 확산 여부

■ 기간
2026.04 ~ 2026.10
```

---

## P-3 조직시너지 창출 (20%)

### Summary
```text
[AIE O-3] 2026 조직시너지 창출 - 조직 간 협업 및 기여
```

### Parent / 팀 Epic 연결
E1 (SW 품질 Shift Left), E2 (SW Governance) 간접 연결 — 파트 독립 영역

### Description
```text
■ 목적
타 조직과의 협업을 통해 사업부 전체 성과에 기여하고
조직 시너지를 극대화한다.

■ 평가 기준 (비중 20%)
- 임원 평가 기반 기여도
- OKR에 상대방 조직의 성공에 기여할 수 있는 Initiative 포함

■ 업무 권한 Level
- L3: 스스로 의사결정을 주도하며 주어진 목표 달성 (결과 부서장 보고)
- L2: 수립한 목표 또는 과제를 리딩하며 동료와 함께 목표 달성
- L1: 부서장/동료의 지시 또는 가이드를 받아 공동의 목표 달성
※ 본 Story 의 각 OKR/Initiative 별로 Level 지정

■ 주요 활동 방향
- 타 조직 협업 Initiative 수행 (OKR 연계)
- 사업부 AI 서비스 지원 활동
- Confluence/Jira를 통한 데이터 공유 활성화

■ 성과 측정
- 협업 프로젝트 수 및 영향도
- 타 조직 피드백 (임원 평가)
- 조직 간 성과 기여도

■ 기간
2026.04 ~ 2026.10
```

---

## P-4 부서원역량강화 (10%)

### Summary
```text
[AIE O-4] 2026 부서원역량강화 - 조직 역량 및 전문성 향상
```

### Parent / 팀 Epic 연결
E1~E4 전체 지원 — 파트 독립 영역

### Description
```text
■ 목적
파트 구성원의 역량 향상을 체계적으로 관리하여 조직 경쟁력을 강화한다.

■ 평가 기준 (비중 10%)
- SCI(Software Capability Index) 기준 기반 역량 관리
- 파트원 교육/세미나/기술 공유 활동 독려 및 지원

■ 업무 권한 Level
- L3: 스스로 의사결정을 주도하며 주어진 목표 달성 (결과 부서장 보고)
- L2: 수립한 목표 또는 과제를 리딩하며 동료와 함께 목표 달성
- L1: 부서장/동료의 지시 또는 가이드를 받아 공동의 목표 달성
※ 본 Story 의 각 OKR/Initiative 별로 Level 지정

■ 주요 활동 방향
- 파트원 역량 진단 및 개발 계획 수립
- 기술 세미나, 지식 공유 세션 운영 지원
- 특허, 논문, 자격 취득 등 개인 역량 강화 활동 독려

■ 성과 측정
- 파트원 역량 향상 수준 (SCI 변화)
- 교육 참여율 및 확산 효과
- 파트원 전문성 확보 건수 (자격, 논문, 특허 등)

■ 기간
2026.04 ~ 2026.10
```

---

## K-1 SLSI Agent App Store

### Summary
```text
[AIE 핵심제품] SLSI Agent App Store - 사내 AI 앱 스토어 개발
```

### Parent / 팀 Epic 연결
Story P-1 (파트 조직목표달성)

### Description
```text
■ 제품 개요
임직원이 사내 AI 앱을 탐색·실행하고, 직접 Prompt + RAG + Tools 기반
에이전트를 만들어 배포할 수 있는 사내 AI 앱 스토어.
Agent App과 Service Link App 두 타입을 지원.

■ 포지셔닝
- 기능: 업무/직무 구분 없이 가볍고 빠르게 사용할 수 있는 기능성 위주
- 기술: RAG, Tools 성능은 크고 복잡하지 않게 제한
- 역할: AI 기술 및 활용팁 전파 창구
- 경쟁 제품: 네이버/구글 검색, ChatGPT

■ 사용 시나리오
- 정보 검색, 번역
- 짧은 문서 작성 및 교정

■ KPI (예시 — OKR 수립 시 구체화)
- 앱 스토어 등록 앱 수
- MAU / DAU
- 사용자 만족도 (NPS)

■ 기간
2026.04 ~ 2026.10
```

---

## K-2 SLSI Alpha Agent

### Summary
```text
[AIE 핵심제품] SLSI Alpha Agent - 개인화된 대화형 Agent 시스템
```

### Parent / 팀 Epic 연결
Story P-1 (파트 조직목표달성)

### Description
```text
■ 제품 개요
임직원이 본인 업무에 맞게 사내 시스템과 연동해서 적극적으로 활용하는
개인화된 대화형 Agent 시스템. 다른 시스템, Agent와 연계 기능 제공.

■ 포지셔닝
- 기능: 대량 정보 처리, 다양한 사내 시스템 연결, 개인화된 성능
- 기술: 고성능 RAG, KG, 강력한 Tool set, 개인화 맞춤 기능
- 역할: AI 기술을 현업에 직접 활용하여 생산성 개선
- 경쟁 제품: Gemini, Dify

■ 사용 시나리오
- 업무용 App으로 제품 문서 작성 및 교정
- 사내 시스템 자동화 및 결과 리포트

■ KPI (예시 — OKR 수립 시 구체화)
- 연동 사내 시스템 수
- 사용자별 평균 세션 시간
- 업무 자동화 건수

■ 기간
2026.04 ~ 2026.10
```

---

## K-3 SLSI Cowork

### Summary
```text
[AIE 핵심제품] SLSI Cowork - 문서 특화 범용 Agent
```

### Parent / 팀 Epic 연결
Story P-1 (파트 조직목표달성)

### Description
```text
■ 제품 개요
직무 구분 없이 누구나 쉽게 Agent를 사용해서 데이터를 정리하고,
문서를 편집하고, 인사이트를 추출한 보고서를 만들 수 있는 문서 특화 범용 Agent.
SW 직군 외 전체 임직원 대상.

■ 포지셔닝
- 기능: 개인 소유 문서 기반 Context 생성 및 작업 수행
- 기술: DRM 이슈 해결, VLM 활용, 문서 생성 Agent, 로컬 파일 접근
- 역할: 개인 PC에서 개인 데이터 활용 업무의 생산성 개선
- 경쟁 제품: Cowork, NotebookLM

■ 사용 시나리오
- 개인 PC 문서 정리
- 문서 기반 보고서 생성
- 문서 기반 질의 응답

■ KPI (예시 — OKR 수립 시 구체화)
- 지원 문서 포맷 수
- 문서 처리 건수 / MAU
- DRM 문서 처리 성공률

■ 기간
2026.04 ~ 2026.10
```

---

## K-4 MCP/Skill Hub

### Summary
```text
[AIE 핵심제품] MCP/Skill Hub - 사내 MCP 마켓플레이스
```

### Parent / 팀 Epic 연결
Story P-1 (파트 조직목표달성)

### Description
```text
■ 제품 개요
사내 MCP(Model Context Protocol) 서버 마켓플레이스.
STDIO/HTTP/WebSocket/SSE 등 다양한 transport 지원.
LLM 연동 플레이그라운드 제공, Agent Skill 메타정보 제공.

■ 포지셔닝
- 기능: Agent가 사용할 도메인 지식(Skill)과 MCP 정보를 큐레이션
- 기술: 기술 도메인/업무 카테고리별 분류, 사용자 참여
- 역할: Agent 통한 업무 처리의 품질 개선 및 BP 공유
- 경쟁 제품: Threads, Dev Community

■ 사용 시나리오
- 기술 및 팁 검색
- 강의, 교육
- 업무 워크플로우 제안

■ KPI (예시 — OKR 수립 시 구체화)
- 등록 MCP/Skill 수
- 플레이그라운드 사용 건수
- Agent 연동 활용률

■ 기간
2026.04 ~ 2026.10
```

---

## P-5 수명업무 (Tracking-only, 가중치 0%)

> 비계획 지시 업무 Task 가 접수될 때마다 본 Story 하위에 Task 로 등록하는 **버킷 Story**. Story 자체는 평가 대상 아님.

### Summary
```text
[AIE O-5] 2026 수명업무 - 비계획 지시/긴급 대응 추적
```

### Parent / 팀 Epic 연결
직접 연결 없음 — 파트 독립 영역 (tracking only, 평가 가중치 없음)

### Description
```text
■ 목적
계획되지 않은 리더 지시 업무·임시 과제를 체계적으로 추적하고 대응한다.
단기(1~3일) 및 중기(1~2주) 범위의 비계획 업무를 본 Story 하위 Task 로 등록.

■ 평가 방식 (비중 0% — Tracking-only)
본 Story 자체는 평가 가중치 없음. 하위 Task 의 내용·성격에 따라
P-1~P-4 중 해당 카테고리로 귀속되어 평가됨.
- 제품 관련 지시 업무 → P-1 조직목표달성 기여분
- 프로세스 개선 지시 → P-2 혁신/개선업무 기여분
- 타 조직 협업 지시 → P-3 조직시너지 기여분

■ 업무 권한 Level
- L3: 스스로 의사결정을 주도하며 주어진 목표 달성 (결과 부서장 보고)
- L2: 수립한 목표 또는 과제를 리딩하며 동료와 함께 목표 달성
- L1: 부서장/동료의 지시 또는 가이드를 받아 공동의 목표 달성
※ 각 Task 별로 Level 지정

■ 대응 유형
- 단기 (1~3일): 긴급 분석 요청, 즉답 대응, 단발성 조사
- 중기 (1~2주): 지시 기반 PoC, 단기 개선 과제, 사업팀 요청 대응

■ 운영 방식
- 리더로부터 지시 접수 시 즉시 Task 생성 (본 Story 하위)
- Task 마다 예상 기간, 우선순위, 실제 소요시간 기록
- 월 1회 Retrospective: 비계획 업무 비중 분석 → 차기 OKR 반영 기회 파악

■ 성과 측정
- 비계획 업무 대응 건수 (정량)
- 평균 응답 시간 / 완료 시간
- 기존 OKR 달성에 미친 영향도 (긍정/부정)

■ 기간
2026.04 ~ 2026.10 (상시)
```
