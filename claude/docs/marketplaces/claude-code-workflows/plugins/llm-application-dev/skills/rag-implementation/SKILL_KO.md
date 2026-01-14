---
name: rag-implementation
description: 벡터 데이터베이스와 시맨틱 검색을 활용해 LLM 애플리케이션용 RAG(Retrieval-Augmented Generation) 시스템을 구축하는 방법을 안내한다. 지식 기반(grounded) 응답이 필요한 AI 구현, 문서 Q&A 시스템 구축, 외부 지식 베이스와 LLM 연동 시 사용한다.
---

# RAG Implementation (요약)

## 개요
- RAG는 LLM이 **외부 지식 소스(문서/DB)**에서 관련 정보를 **검색(Retrieval)**해 가져오고, 그 컨텍스트를 바탕으로 **근거 있는 생성(Generation)**을 수행하도록 하는 설계다.
- 목표는 **정확성 향상**, **도메인 지식 활용**, **환각(hallucination) 감소**, **출처 기반 답변**이다.

## 사용 시점(When to Use)
- 사내/독점 문서를 대상으로 하는 **문서 Q&A**
- 최신 사실 기반 정보가 필요한 **챗봇/어시스턴트**
- 자연어 질의로 동작하는 **시맨틱 검색**
- 도메인 특화 지식에 접근하는 **지식 접지(grounding)형 LLM 앱**
- 문서/리서치 도구에서 **출처 인용**이 필요한 경우

## 핵심 구성요소(Core Components)
### 1) 벡터 데이터베이스(Vector Databases)
- **목적**: 문서를 임베딩으로 저장하고, 유사도 기반으로 빠르게 검색
- **대표 옵션**: Pinecone(관리형), Weaviate(오픈소스/하이브리드), Milvus(고성능/온프레미스), Chroma(경량/로컬), Qdrant(빠른 필터 검색), FAISS(로컬 라이브러리)

### 2) 임베딩(Embeddings)
- **목적**: 텍스트를 수치 벡터로 변환해 의미 유사도 검색 수행
- **모델 예시**: OpenAI `text-embedding-ada-002`, Sentence Transformers `all-MiniLM-L6-v2`, `e5-large-v2`(다국어 고품질), Instructor(작업 지시 기반), `bge-large-en-v1.5`(고성능)

### 3) 검색 전략(Retrieval Strategies)
- Dense Retrieval: 임베딩 기반 의미 검색
- Sparse Retrieval: BM25/TF‑IDF 등 키워드 기반
- Hybrid Search: Dense + Sparse 결합
- Multi-Query: 질의를 여러 변형으로 확장해 재검색
- HyDE: “가상의 답변 문서”를 생성해 검색 품질 개선

### 4) 재정렬(Reranking)
- **목적**: 1차 검색 결과를 더 정확한 순서로 재배치해 상위 결과 품질 개선
- **방법**: Cross-Encoder(BERT 계열), Cohere Rerank(API), MMR(관련성+다양성), LLM 기반 스코어링

## 빠른 시작(Quick Start) 흐름
- 문서 로드 → 청킹(분할) → 임베딩 생성 → 벡터스토어 구축 → Retriever+LLM으로 RetrievalQA 체인 구성 → 질의 및 (필요 시) 출처 문서 반환

## 고급 RAG 패턴(Advanced Patterns)
- Hybrid Search: BM25(스파스) + 임베딩(덴스)을 가중치로 앙상블
- Multi-Query Retrieval: 단일 질문을 여러 관점의 질의로 확장 후 결과 통합
- Contextual Compression: 문서 전체 대신 **관련 부분만 추출**해 컨텍스트를 압축
- Parent Document Retriever: 검색은 작은 청크로, 답변 컨텍스트는 큰 “부모 문서”로 제공

## 문서 청킹 전략(Chunking)
- Recursive Character Splitter: 구분자 우선순위로 안정적 분할
- Token 기반 분할: 토큰 길이 기준으로 모델 컨텍스트에 맞춤
- Semantic Chunking: 임베딩을 활용해 의미 경계 기반 분할
- Markdown Header Splitter: 헤더 구조를 보존하며 섹션 단위 분할

## 벡터 스토어 구성 예시(Vector Store Configurations)
- Pinecone / Weaviate / Chroma(Local) 각각의 초기화 및 연결 예시를 제공하며, 로컬/관리형/자체 호스팅 선택지를 전제로 한다.

## 검색 최적화(Retrieval Optimization)
- Metadata Filtering: 인덱싱 시 메타데이터(출처/페이지/카테고리 등) 추가 후 검색 시 필터 적용
- MMR: 관련성과 다양성을 균형 있게 선택해 중복 컨텍스트 감소
- Cross-Encoder Rerank: 상위 후보를 재점수화해 최종 Top‑k 품질 향상

## RAG용 프롬프트 엔지니어링(Prompt Engineering)
- 컨텍스트 기반 답변 강제(컨텍스트 없으면 “정보 부족”으로 응답)
- 인용 형식([1], [2] 등)으로 **출처 기반 답변**
- 신뢰도 점수(0–100%)를 함께 출력하는 템플릿

## 평가(Evaluation Metrics)
- 정확도(Answer accuracy), 검색 품질(Retrieval quality), 근거성(Groundedness)을 테스트 케이스 기반으로 측정하는 예시 함수를 제시한다.

## 리소스(Resources)
- 벡터 DB 비교, 임베딩 선택, 검색 전략, 재정렬, 컨텍스트 윈도우 관리 문서 및 파이프라인/설정 템플릿(assets)을 참조하도록 안내한다.

## 모범 사례(Best Practices)
- 청크 크기(대략 500–1000 토큰), 오버랩(10–20%), 메타데이터 포함
- 하이브리드 검색 + 재정렬로 상위 결과 품질 강화
- 출처 문서 반환/인용으로 투명성 확보
- 지속적 평가/모니터링으로 운영 품질 관리

## 흔한 이슈(Common Issues)와 대응
- 검색 부정확: 임베딩 품질/청크 크기/질의 구성 점검
- 결과 무관: 메타데이터 필터, 하이브리드, 재정렬 적용
- 정보 누락: 인덱싱/수집 누락 여부 확인
- 성능 저하: 벡터스토어 최적화, 캐싱, k 축소
- 환각: 접지 프롬프트 강화, 검증 단계 추가

## [원본 파일]
- (사용자 제공 원문: `rag-implementation` 스킬 문서)