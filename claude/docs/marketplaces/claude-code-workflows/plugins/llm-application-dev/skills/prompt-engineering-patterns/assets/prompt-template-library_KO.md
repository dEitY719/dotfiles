---
name: prompt-template-library
description: 분류·추출·생성·변환·분석·질의응답 등 다양한 작업에 재사용 가능한 프롬프트 템플릿 모음
model: null
---

# 요약: Prompt Template Library

## 개요
- 여러 NLP/생성형 작업을 **표준화된 프롬프트 قالب(Template)** 으로 제공해, 입력 변수만 채워 일관된 결과를 얻도록 설계된 템플릿 라이브러리입니다.
- 모든 템플릿은 `{text}`, `{context}` 같은 **플레이스홀더 변수**를 채워 사용합니다.

## 주요 구성(기능)별 템플릿

### 1) 분류(Classification) 템플릿
- **감성 분석(Sentiment Analysis)**: 주어진 텍스트를 `Positive / Negative / Neutral` 중 하나로 분류합니다.
- **의도 분류(Intent Detection)**: 가능한 의도 목록 `{intent_list}` 중에서 사용자 메시지의 의도를 판별합니다.
- **주제 분류(Topic Classification)**: 기사/문서를 미리 정의된 `{categories}` 중 하나로 분류합니다.

### 2) 추출(Extraction) 템플릿
- **개체명 인식(NER)**: 텍스트에서 인물/조직/장소/날짜를 추출해 **JSON 스키마**로 정리합니다.
- **구조화 정보 추출(Structured Data Extraction)**: 채용 공고에서 직무명, 회사, 위치, 급여 범위, 요구사항, 책임 등을 **정형 JSON**으로 추출합니다.

### 3) 생성(Generation) 템플릿
- **이메일 생성(Email Generation)**: 수신자/맥락/핵심 포인트를 바탕으로 전문적인 이메일(제목·본문)을 작성합니다.
- **코드 생성(Code Generation)**: 작업 설명과 요구사항을 기반으로 특정 언어 `{language}` 코드 생성(오류 처리, 입력 검증, 인라인 주석 포함)을 지시합니다.
- **창작 글쓰기(Creative Writing)**: 길이/스타일/주제와 포함 요소들을 지정해 스토리를 생성합니다.

### 4) 변환(Transformation) 템플릿
- **요약(Summarization)**: `{num_sentences}` 문장 수로 텍스트를 요약합니다.
- **문맥 포함 번역(Translation with Context)**: 번역 방향, 문맥, 톤을 명시해 목적에 맞는 번역을 생성합니다.
- **형식 변환(Format Conversion)**: 입력 데이터를 `{source_format}`에서 `{target_format}`으로 변환합니다.

### 5) 분석(Analysis) 템플릿
- **코드 리뷰(Code Review)**: 버그/성능/보안 취약점/베스트 프랙티스 위반 관점에서 코드를 점검합니다.
- **SWOT 분석(SWOT Analysis)**: 대상과 문맥을 주고 강점·약점·기회·위협을 구조적으로 작성합니다.

### 6) 질의응답(Question Answering) 템플릿
- **RAG 템플릿**: 제공된 문맥 `{context}` 내에서만 답하고, 정보가 부족하면 부족하다고 명시하도록 지시합니다.
- **멀티턴 Q&A**: 이전 대화 이력과 새 질문을 받아 자연스럽게 이어서 답변합니다.

### 7) 특화(Specialized) 템플릿
- **SQL 생성(SQL Query Generation)**: 스키마와 요청을 기반으로 SQL 쿼리를 생성합니다.
- **정규식 생성(Regex Pattern Creation)**: 요구사항과 긍정/부정 예시를 기반으로 정규식을 설계합니다.
- **API 문서 생성(API Documentation)**: 함수 코드를 입력으로 받아 지정된 문서 형식 `{doc_format}`으로 문서를 생성합니다.

## 사용 방법
- 각 템플릿의 `{variables}` 자리에 실제 값을 채워 실행하는 방식으로 사용합니다.

## [원본 파일]
- 경로: (제공되지 않음; 사용자 메시지에 원문 텍스트만 포함)