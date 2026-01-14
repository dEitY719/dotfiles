---
name: prompt-engineering-patterns
description: 프로덕션 환경에서 LLM의 성능, 신뢰성, 제어 가능성을 극대화하기 위한 고급 프롬프트 엔지니어링 기법을 다룹니다. 프롬프트 최적화, 출력 품질 개선, 프로덕션용 템플릿 설계 시 사용합니다.
---

# Prompt Engineering Patterns (요약)

## 개요
LLM을 프로덕션에서 안정적으로 운영하기 위해, **프롬프트를 설계·최적화·템플릿화·검증**하는 핵심 패턴과 워크플로를 정리한 스킬입니다.

## 사용 시점 (When to Use)
- 프로덕션용으로 **복잡한 프롬프트**를 설계할 때
- 출력의 **일관성/정확성**을 높이도록 프롬프트를 최적화할 때
- **구조화된 추론 패턴**(Chain-of-Thought, Tree-of-Thought 등)을 도입할 때
- **Few-shot 학습**을 위한 예시(데모) 구성을 체계화할 때
- **변수 치환**이 가능한 재사용 프롬프트 템플릿을 만들 때
- 결과가 들쭉날쭉한 프롬프트를 **디버깅/개선**할 때
- 특정 역할/정책/형식을 강제하는 **시스템 프롬프트**를 설계할 때

## 핵심 기능 (Core Capabilities)

### 1) Few-Shot Learning
- 예시 선택 전략: **의미적 유사도 기반 선택**, **다양성 샘플링** 등
- 컨텍스트 윈도우 한계 내에서 **예시 개수와 품질 균형**
- 입력-출력 쌍으로 구성된 **효과적인 데모(시연) 작성**
- 지식베이스에서 **동적 예시 검색/주입**
- 엣지 케이스를 예시로 커버하는 **전략적 구성**

### 2) Chain-of-Thought(CoT) 프롬팅
- 단계별 추론을 유도하는 프롬프트 패턴
- “Let’s think step by step” 같은 **제로샷 CoT**
- 추론 흔적(reasoning trace)을 포함하는 **퓨샷 CoT**
- 여러 추론 경로를 샘플링하는 **Self-consistency**
- 결과 **검증/확인 단계**를 프롬프트에 포함

### 3) 프롬프트 최적화 (Prompt Optimization)
- 반복 개선(Iterative refinement) 워크플로
- 프롬프트 변형에 대한 **A/B 테스트**
- 정확도/일관성/지연시간 등 **성능 지표 측정**
- 품질을 유지하며 **토큰 사용량 절감**
- 실패 모드와 엣지 케이스 대응 설계

### 4) 템플릿 시스템 (Template Systems)
- **변수 치환** 및 포맷팅
- 조건부 섹션(Conditional sections)
- 멀티턴 대화 템플릿
- 역할 기반(ROLE) 프롬프트 구성
- 모듈형 컴포넌트로 재사용성 강화

### 5) 시스템 프롬프트 설계 (System Prompt Design)
- 모델의 행동/제약을 **명시적으로 설정**
- 출력 형식/구조 정의
- 역할과 전문성 범위 설정
- 안전 가이드라인/콘텐츠 정책 포함
- 배경 정보와 컨텍스트 설정

## 대표 패턴 (Key Patterns)

### Progressive Disclosure (점진적 공개)
처음엔 단순하게 시작하고, 필요할 때만 제약·추론·예시를 단계적으로 추가합니다.
- Level 1: 직접 지시
- Level 2: 제약 추가(분량/형식/관점)
- Level 3: 수행 절차(추론/분해) 추가
- Level 4: 입력-출력 예시 추가(퓨샷)

### Instruction Hierarchy (지시 우선순위)
`[시스템 컨텍스트] → [과업 지시] → [예시] → [입력 데이터] → [출력 형식]` 순으로 구성해 충돌을 줄이고 통제력을 높입니다.

### Error Recovery (오류 복구)
- 실패 시 **대체 지침(fallback)** 포함
- **확신도/불확실성 표시** 요구
- 모호할 때 **대안 해석** 제시 요구
- 정보가 부족하면 **무엇이 누락됐는지 명시**하도록 강제

## 모범 사례 (Best Practices)
- 구체적으로 지시해 **일관성**을 확보
- 설명보다 **예시(Show, Don’t Tell)**로 학습 유도
- 다양한 입력으로 **충분히 테스트**
- 작은 변경을 빠르게 반복(Iterate)하며 개선
- 프로덕션에서 지표를 **모니터링**
- 프롬프트를 코드처럼 **버전 관리**
- 프롬프트 구조의 의도를 **문서화**

## 흔한 함정 (Common Pitfalls)
- 단순 시도 없이 처음부터 과도하게 복잡하게 설계(Over-engineering)
- 과업과 맞지 않는 예시 사용(Example pollution)
- 예시 과다로 토큰 한도 초과(Context overflow)
- 지시가 모호해 해석이 갈리는 문제(Ambiguous instructions)
- 엣지 케이스 미검증(Ignoring edge cases)

## 통합 패턴 (Integration Patterns)
- **RAG 결합**: 검색된 컨텍스트 + 예시 + 질문을 묶고, “컨텍스트에만 근거해 답하라 / 부족하면 부족한 점을 말하라”를 명시
- **검증 단계 추가**: 답변 생성 후 기준(질문 직접 답변, 컨텍스트 근거, 출처 명시, 불확실성 인정 등)으로 자기검증하고 실패 시 수정

## 성능 최적화 (Performance Optimization)
- 토큰 효율: 중복 표현 제거, 약어 일관화, 지시 통합, 안정 문구는 시스템 프롬프트로 이동
- 지연시간: 프롬프트 길이 최소화, 스트리밍 활용, 접두부 캐싱, 유사 요청 배치 처리

## 리소스/도구 구성 (Resources)
- 참조 문서: few-shot, CoT, 최적화, 템플릿, 시스템 프롬프트 관련 심화 자료
- 자산: 템플릿 라이브러리, 예시 데이터셋
- 스크립트: 자동 프롬프트 최적화 도구(`optimize-prompt.py`)

## 성공 지표 (Success Metrics)
- 정확도(Accuracy), 일관성(Consistency), 지연시간(Latency), 토큰 사용량(Token Usage), 성공률(Success Rate), 사용자 만족(User Satisfaction)

## 다음 단계 (Next Steps)
- 템플릿 라이브러리 검토 → few-shot 실험 → 버전관리/A-B 테스트 구축 → 자동 평가 파이프라인 → 의사결정 문서화

## [원본 파일]
- `/home/bwyoon/.codex/skills/prompt-engineering-patterns/SKILL.md`