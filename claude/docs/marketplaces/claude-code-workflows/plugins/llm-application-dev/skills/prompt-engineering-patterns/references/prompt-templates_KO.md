---
name: Prompt Template Systems
description: 프롬프트 템플릿 시스템의 구조(기본/조건부/모듈식), 공통 패턴, 고급 기능(상속·검증·캐싱), 멀티턴 템플릿, 모범 사례와 성능 고려사항을 정리한 문서
model: (원본 YAML 헤더 미제공)
---

## 개요
- `.format()` 기반 문자열 템플릿을 표준화해 **재사용성/일관성/검증/성능**을 확보하는 프롬프트 템플릿 시스템을 설명합니다.

## 템플릿 아키텍처
### 1) 기본 템플릿(`PromptTemplate`)
- `template_string`과 `variables`(필수 변수 목록)를 보관합니다.
- `render(**kwargs)` 호출 시 필수 변수가 누락되면 예외를 발생시키고, 모두 존재하면 `template.format(**kwargs)`로 최종 프롬프트를 생성합니다.

### 2) 조건부 템플릿(`ConditionalTemplate`)
- Handlebars 유사 문법을 정규식으로 처리한 뒤, 마지막에 `.format()`으로 변수 치환을 수행합니다.
- 조건 블록: `{{#if var}} ... {{/if}}` 형태를 지원하며, `var`가 truthy일 때만 내용을 포함합니다.
- 반복 블록: `{{#each items}} ... {{/each}}` 형태를 지원하며, 반복 중 `{{this}}`를 각 아이템 값으로 치환해 줄바꿈으로 합칩니다.

### 3) 모듈식 합성(`ModularTemplate`)
- `register_component(name, template)`로 컴포넌트를 등록하고,
- `render(structure, **kwargs)`에서 `structure`(컴포넌트 순서 목록)에 따라 조각을 조합해 프롬프트를 구성합니다.
- 시나리오별로 `system/context/examples/instruction/input/format` 같은 섹션을 선택적으로 조립할 수 있습니다.

## 공통 템플릿 패턴
- **분류(Classification)**: 입력을 카테고리 중 하나로 분류하며, 필요 시 설명/예시 섹션을 조건부로 포함합니다.
- **추출(Extraction)**: 필드 정의를 기반으로 구조화된 정보를 추출하고 JSON 출력 유도를 포함합니다.
- **생성(Generation)**: 요구사항/스타일/제약/예시 등을 조건부로 포함해 산출물을 생성합니다.
- **변환(Transformation)**: 소스 포맷→타겟 포맷 변환 규칙과 예시를 포함해 변환 결과를 유도합니다.

## 고급 기능
### 1) 템플릿 상속(`TemplateRegistry`)
- `register(name, template, parent=None)`로 템플릿을 등록합니다.
- `parent`가 있으면 부모 템플릿과 병합(자식이 동일 키를 덮어씀)하여 공통 섹션 재사용을 지원합니다.

### 2) 변수 검증(`ValidatedTemplate`)
- `schema`로 변수별 **타입(type)**, **범위(min/max)**, **선택지(choices)** 검증을 수행합니다.
- 검증 통과 후에만 `.format()`으로 렌더링해 런타임 오류와 품질 저하를 줄입니다.

### 3) 템플릿 캐싱(`CachedTemplate`)
- `render(use_cache=True, **kwargs)`에서 동일 입력(변수 집합)에 대해 렌더 결과를 캐시합니다.
- 캐시 키는 `kwargs`를 해시해 생성하며, `clear_cache()`로 캐시를 초기화합니다.

## 멀티턴(대화형) 템플릿
### 1) 대화 템플릿(`ConversationTemplate`)
- `system_prompt`와 `history`(user/assistant 메시지 리스트)를 관리합니다.
- API용 메시지 배열(`render_for_api`)과 텍스트 합성본(`render_as_text`)을 모두 제공합니다.

### 2) 상태 기반 템플릿(`StatefulTemplate`)
- `state` 딕셔너리에 현재 상태 및 입력값을 저장하고,
- 상태명(`current_state`)에 따라 다른 템플릿을 선택해 멀티스텝 워크플로(초기화→처리→완료)를 구성합니다.

## 모범 사례(Best Practices)
- 템플릿으로 반복 제거(DRY), 렌더 전 변수 검증, 템플릿 버전 관리
- 다양한 입력 변형 테스트, 변수(필수/선택) 문서화, 타입 힌트/기본값 제공
- 정적 템플릿 중심으로 신중한 캐싱 적용

## 템플릿 라이브러리 예시
- **QA 템플릿**: 사실 기반(factual), 다중 사실 결합(multi_hop), 대화형(conversational)
- **콘텐츠 생성 템플릿**: 블로그 포스트, 제품 설명, 이메일(수신자/맥락/핵심 포인트 포함)

## 성능 고려사항
- 반복 사용 템플릿의 사전 컴파일(개념적으로), 정적 변수일 때만 렌더 결과 캐싱
- 루프 내 문자열 결합 최소화, 효율적인 포매팅 사용, 병목 프로파일링 권장

## [원본 파일]
- (경로 미제공: 사용자 제공 텍스트)