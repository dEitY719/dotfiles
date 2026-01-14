---
name: vector-index-tuning
description: 지연시간(latency), 재현율(recall), 메모리 사용량 관점에서 벡터 인덱스 성능을 최적화하는 가이드. HNSW 파라미터 튜닝, 양자화(quantization) 전략 선택, 대규모 벡터 검색 인프라 확장 시 사용.
---

# Vector Index Tuning (요약)

프로덕션 환경에서 벡터 인덱스를 **빠르고(낮은 지연시간)**, **정확하게(높은 재현율)**, **가볍게(낮은 메모리)** 운영하기 위한 튜닝 가이드입니다.

## 사용 시점 (When to Use)
- **HNSW 파라미터(M, efConstruction, efSearch)** 조정이 필요할 때
- **양자화(Scalar/PQ/Binary)**로 메모리 절감 또는 속도 향상이 필요할 때
- 벡터 검색의 **메모리 사용량 최적화**가 필요할 때
- **검색 지연시간 감소**가 목표일 때
- **재현율 vs 속도**의 트레이드오프를 조정해야 할 때
- **수억~수십억 벡터 규모**로 확장(스케일링)할 때

## 핵심 개념 (Core Concepts)

### 1) 인덱스 타입 선택 (Index Type Selection)
데이터 규모에 따라 권장 인덱스가 달라집니다.
- `< 10K` : **Flat(정확 검색)** — 단순하지만 정확, 규모가 커지면 느려짐
- `10K ~ 1M` : **HNSW** — 일반적인 ANN 선택지
- `1M ~ 100M` : **HNSW + Quantization** — 속도/메모리 균형 개선
- `> 100M` : **IVF+PQ 또는 DiskANN** — 초대규모에서 메모리/디스크 활용 고려

### 2) HNSW 주요 파라미터 (HNSW Parameters)
- `M` (기본 16): 노드당 연결 수  
  - 값 ↑ → **재현율 향상**, **메모리 증가**
- `efConstruction` (기본 100): 인덱스 구축 품질/비용  
  - 값 ↑ → **더 좋은 인덱스(재현율 개선 여지)**, **빌드 시간 증가**
- `efSearch` (기본 50): 검색 시 탐색 폭  
  - 값 ↑ → **재현율 향상**, **검색 지연시간 증가**

### 3) 양자화 종류와 메모리 특성 (Quantization Types)
벡터 저장 비용을 줄이기 위한 대표 옵션들입니다.
- **FP32**: `4 bytes × dims` (정밀도 최고, 메모리 큼)
- **FP16**: `2 bytes × dims`
- **INT8 Scalar**: `1 byte × dims`
- **Product Quantization(PQ)**: 대략 `~32–64 bytes` 수준으로 강한 압축 가능(설계/품질 트레이드오프 큼)
- **Binary**: `dims/8 bytes` (가장 작지만 정보 손실 큼)

## 제공 템플릿 (Templates)

### Template 1: HNSW 파라미터 벤치마크/추천
- 여러 `M`, `efConstruction`, `efSearch` 조합을 반복 측정해
  - **빌드 시간**, **검색 시간(ms/query)**, **recall@10**, **추정 메모리(MB)**를 비교합니다.
- 목표 재현율/규모에 따라 `efSearch` 등을 **규칙 기반으로 추천**하는 예시도 포함합니다.

### Template 2: 양자화 전략 구현 + 메모리 추정
- **INT8 스칼라 양자화/복원(dequantize)** 구현 예시
- **PQ(Product Quantization)** 구현 개요(서브벡터별 KMeans 코드북)
- **Binary 양자화**(부호 기반) 및 비트 패킹
- 설정(벡터 수/차원/양자화/인덱스 타입/HNSW M)에 따른 **메모리 사용량 추정 함수** 제공

### Template 3: Qdrant 인덱스 구성 최적화 예시
- `optimize_for = recall | speed | balanced | memory` 목표에 따라:
  - **HNSW 설정(m, ef_construct)**
  - **Quantization 설정(INT8 Scalar 또는 PQ 등)**
  - **Optimizer 설정(indexing_threshold, memmap_threshold)**
  를 다르게 적용해 컬렉션을 생성합니다.
- 목표 재현율에 따른 검색 파라미터(`hnsw_ef`, quantization ignore/rescore/oversampling) 추천 로직 포함

### Template 4: 성능 모니터링/프로파일링
- `p50/p95/p99 latency`, `recall`, `QPS`를 측정하는 모니터링 구조 제공
- 배치 사이즈별 인덱스 빌드 처리량(벡터/초) 측정으로 **빌드 성능 병목** 파악

## 베스트 프랙티스 (Best Practices)

### Do’s
- 프로덕션과 유사한 **실제 쿼리로 벤치마크**
- **재현율을 지속 모니터링**(데이터 드리프트로 저하 가능)
- **기본값으로 시작**하고 필요할 때만 튜닝
- 가능하면 **양자화로 메모리 크게 절감**
- **계층형 저장(Hot/Cold)** 등 스토리지 전략 고려

### Don’ts
- **초기에 과도한 최적화 금지**(먼저 프로파일링)
- **빌드 시간/업데이트 비용** 무시 금지
- **재인덱싱(유지보수)** 계획 누락 금지
- **웜업(warming)** 없이 성능 판단 금지(콜드 인덱스는 느림)

## 참고 자료 (Resources)
- HNSW 논문, Faiss Wiki, ANN Benchmarks 링크 제공

## [원본 파일]
- (사용자 제공 원문: `vector-index-tuning` 스킬/에이전트 문서)