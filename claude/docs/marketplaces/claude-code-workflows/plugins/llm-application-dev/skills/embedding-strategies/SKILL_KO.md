---
name: embedding-strategies
description: Select and optimize embedding models for semantic search and RAG applications. Use when choosing embedding models, implementing chunking strategies, or optimizing embedding quality for specific domains.
---

# Embedding Strategies (요약)

벡터 검색(semantic search) 및 RAG에서 사용할 **임베딩 모델 선택**, **청킹(chunking) 설계**, **품질 최적화**를 위한 실무 가이드와 코드 템플릿을 제공한다.

## 사용 시점 (When to Use)
- RAG용 임베딩 모델 선택 및 비교
- 문서 청킹 전략 최적화(크기/오버랩/경계 기준)
- 특정 도메인(법률/코드/멀티링구얼 등) 임베딩 성능 개선
- 임베딩 차원 축소 및 비용/지연 최적화
- 다국어 콘텐츠 처리 전략 수립

## 핵심 개념 (Core Concepts)

### 1) 임베딩 모델 비교 프레임
- 모델을 **차원 수(dimension)**, **최대 토큰**, **강점 도메인** 기준으로 비교한다.
- 예시로 고정밀(대형), 비용 효율(소형), 코드/법률 특화, 오픈소스, 경량/고속, 멀티링구얼 모델군을 제시한다.

### 2) 임베딩 파이프라인 표준 흐름
- 기본 흐름: `문서 → 청킹 → 전처리 → 임베딩 모델 → 벡터`
- 청킹에서는 **크기**와 **오버랩**을 조정하고, 전처리는 **정제/정규화**로 검색 품질을 안정화한다.
- 임베딩 실행은 **API 기반** 또는 **로컬 모델** 방식으로 구현한다.

## 제공 템플릿 (Templates)

### Template 1: OpenAI 임베딩 호출(배치 + 선택적 차원 축소)
- 다량 입력을 **배치 처리**하여 효율을 높인다.
- `dimensions` 옵션으로 **차원 축소(Matryoshka 방식)**를 지원하는 형태를 예시로 든다.
- 단건 임베딩 헬퍼(`get_embedding`)와 축소 임베딩 헬퍼(`get_reduced_embedding`)를 포함한다.

### Template 2: Sentence Transformers 로컬 임베딩
- 로컬 모델 로딩 후 `encode`로 임베딩을 생성하고, 필요 시 **정규화(normalize)** 옵션을 사용한다.
- 질의/문서 임베딩을 분리해 다루는 패턴을 제시한다.
- E5 계열처럼 **instruction/prefix(query:, passage:)**가 중요한 모델의 사용 예를 포함한다.
- (주의) 예시 코드의 BGE query prefix 조건은 구현상 점검이 필요해 보이며, 실제 적용 시 모델 타입/이름 기반으로 분기하는 방식이 일반적이다.

### Template 3: 청킹 전략 모음
- **토큰 기반 청킹**: 토크나이저로 토큰 수를 기준 삼아 `chunk_size`와 `chunk_overlap`로 분할.
- **문장 기반 청킹**: 문장 단위로 누적 길이를 관리해 최대/최소 크기를 맞춘다.
- **마크다운 섹션 기반 청킹**: 헤더 패턴으로 섹션을 분리해 계층을 보존한다.
- **재귀 문자 분할기**: 구분자 우선순위(`\n\n`, `\n`, `. `, 공백, 문자 단위)로 점진적으로 쪼개며, LangChain 스타일의 오버랩을 구성한다.

### Template 4: 도메인 특화 파이프라인
- **DomainEmbeddingPipeline**: 전처리(공백/특수문자 정리) → 토큰 청킹 → 임베딩 생성 → 벡터 저장 레코드 구성(id, chunk_index, text, embedding, 메타데이터).
- **CodeEmbeddingPipeline**: 코드의 함수/클래스 등 구조 단위 청킹(tree-sitter 등)과, **컨텍스트+코드 결합 임베딩** 패턴을 제시한다(구현은 스텁).

### Template 5: 임베딩 품질 평가
- 검색 품질 지표를 계산하는 평가 루틴 제공:
  - `precision@k`, `recall@k`, `MRR`, `NDCG@k`
- 임베딩 간 유사도 행렬 계산:
  - 코사인(정규화 후 내적), 유클리드(거리 기반 점수), 도트 제품(dot) 방식

## 권장 사항 (Best Practices)

### Do’s
- 사용 사례에 맞는 모델 선택(코드/문서/다국어 등)
- 의미 경계를 살리는 청킹(문장/섹션/구조 기반)
- 코사인 유사도 사용 시 임베딩 정규화
- API 호출은 배치 처리로 효율화
- 임베딩 캐시로 재계산 비용 절감

### Don’ts
- 토큰 제한 무시(잘림으로 정보 손실)
- 서로 다른 임베딩 모델을 혼용(벡터 공간 불일치)
- 전처리 생략(입력 노이즈가 검색 품질 악화)
- 과도한 청킹(문맥 손실)

## 리소스 (Resources)
- OpenAI Embeddings 문서
- Sentence Transformers 문서
- MTEB 벤치마크 리더보드

## [원본 파일]
- (사용자 제공 본문) `embedding-strategies` 스킬/에이전트 파일 내용