---
name: langchain-architecture
description: LangChain 프레임워크에서 에이전트, 메모리, 도구 통합 패턴을 활용해 LLM 애플리케이션을 설계하는 스킬. LangChain 앱 구축, AI 에이전트 구현, 복잡한 LLM 워크플로 구성 시 사용.
---

# LangChain Architecture 요약

LangChain을 사용해 **에이전트(Agent)**, **체인(Chain)**, **메모리(Memory)**, **문서 처리(RAG)**, **콜백(Callbacks)** 등을 조합하여 **모듈식·재사용 가능한 프로덕션급 LLM 애플리케이션**을 설계하는 방법을 다룹니다.

## 언제 사용하나
- 도구(tool)에 접근하는 **자율 에이전트**를 만들 때
- 여러 단계를 거치는 **복잡한 LLM 워크플로**를 구현할 때
- 대화 **상태/컨텍스트(메모리)** 관리를 설계할 때
- 외부 데이터 소스·API와 **통합**할 때
- 문서 기반 **검색-생성(RAG)** 파이프라인을 만들 때
- 운영 환경을 고려한 **프로덕션 아키텍처**를 정리할 때

## 핵심 개념

### 1) Agents (에이전트)
LLM이 상황에 따라 “어떤 행동/도구를 쓸지”를 스스로 결정하는 실행 주체입니다.  
주요 유형:
- **ReAct**: 추론(Reasoning)과 행동(Acting)을 번갈아 수행
- **OpenAI Functions**: 함수 호출(function calling) 기반 도구 실행
- **Structured Chat**: 여러 입력을 받는 도구를 구조화해 처리
- **Conversational**: 대화형 UX에 최적화
- **Self-Ask with Search**: 복잡한 질문을 하위 질문으로 분해해 검색 결합

### 2) Chains (체인)
LLM 호출 및 유틸리티 호출을 **순서대로 조합한 파이프라인**입니다.  
주요 유형:
- **LLMChain**: 프롬프트 + LLM의 기본 조합
- **SequentialChain**: 여러 체인을 직렬로 연결
- **RouterChain**: 입력을 분석해 적절한 전문 체인으로 라우팅
- **TransformChain**: 단계 사이의 데이터 변환 처리
- **MapReduceChain**: 병렬 처리 후 결과를 집계

### 3) Memory (메모리)
상호작용 전반에서 **대화 컨텍스트/상태를 유지**하는 방식입니다.  
주요 유형:
- **ConversationBufferMemory**: 전체 메시지를 그대로 저장
- **ConversationSummaryMemory**: 오래된 대화를 요약해 축약
- **ConversationBufferWindowMemory**: 최근 N개 메시지만 유지
- **EntityMemory**: 엔티티(사람/조직/객체) 중심 정보 추적
- **VectorStoreMemory**: 의미 기반 유사도 검색으로 관련 히스토리 회수

### 4) Document Processing (문서 처리 / RAG 구성요소)
문서를 로드·분할·임베딩·저장하고, 질의 시 관련 문서를 검색해 생성에 활용합니다.  
구성요소:
- **Document Loaders**: 다양한 소스에서 문서 로드
- **Text Splitters**: 적절한 크기로 청킹(chunking)
- **Vector Stores**: 임베딩 저장/검색
- **Retrievers**: 관련 문서 검색
- **Indexes**: 효율적인 접근을 위한 구조화

### 5) Callbacks (콜백)
로깅/모니터링/디버깅을 위한 훅(hook) 시스템입니다.  
주요 사용처:
- 요청/응답 로깅
- 토큰 사용량 및 비용 추적
- 지연 시간(latency) 모니터링
- 오류 처리
- 커스텀 메트릭 수집

## 빠른 시작(개요)
- LLM 초기화 → 도구 로드 → 메모리 추가 → 에이전트 생성 → `agent.run()`으로 실행  
예시에서는 검색(serpapi)과 계산(llm-math) 도구를 붙이고, 대화 기록을 메모리로 유지하는 **대화형 ReAct 에이전트**를 구성합니다.

## 대표 아키텍처 패턴
- **Pattern 1: RAG with LangChain**: 문서 로드 → 청킹 → 임베딩/벡터스토어 구성 → `RetrievalQA`로 질의 응답(소스 문서 반환 포함)
- **Pattern 2: Custom Agent with Tools**: `@tool`로 내부 DB 검색, 이메일 발송 등 도구 정의 후 에이전트에 연결
- **Pattern 3: Multi-Step Chain**: (추출 → 분석 → 요약)처럼 여러 `LLMChain`을 `SequentialChain`으로 결합해 단계적 처리를 구현

## 메모리 운영 베스트 프랙티스
- 짧은 대화: `ConversationBufferMemory`
- 긴 대화: `ConversationSummaryMemory`로 요약 기반 축약
- 슬라이딩 윈도우: `ConversationBufferWindowMemory(k=N)`
- 엔티티 추적: `ConversationEntityMemory`
- 관련 히스토리만 의미 검색: `VectorStoreRetrieverMemory`

## 테스트 전략(개요)
- LLM 응답을 Mock 처리해 **도구 선택이 기대대로인지** 검증
- 메모리에 컨텍스트를 저장/로드해 **대화 이력 지속성** 검증

## 성능 최적화 포인트
- **캐싱**: LLM 결과 캐시로 반복 호출 비용 절감
- **배치/병렬 처리**: 문서 분할 등 전처리를 병렬화
- **스트리밍 응답**: 콜백을 이용해 토큰 단위 스트리밍 출력

## 흔한 함정(주의사항)
- 메모리 무제한 저장으로 인한 **컨텍스트 폭증**
- 도구 설명이 부정확해 발생하는 **도구 선택 오류**
- **컨텍스트 윈도우 초과**(토큰 한도)
- 에러 핸들링 부재로 인한 장애 확대
- 비효율적 검색/벡터 질의로 인한 성능 저하

## 프로덕션 체크리스트(요지)
- 에러 처리, 로깅, 토큰/비용 모니터링, 타임아웃, 레이트 리밋, 입력 검증
- 엣지 케이스 테스트, 관측성(콜백) 구성
- 폴백 전략 및 프롬프트/설정 버전 관리

## [원본 파일]
- (제공된 스니펫) `langchain-architecture` 스킬 문서 내용 (파일 경로 미제공)