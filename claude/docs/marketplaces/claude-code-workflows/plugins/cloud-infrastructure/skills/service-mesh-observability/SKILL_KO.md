---
name: service-mesh-observability
description: 서비스 메시(Istio, Linkerd 등)에 대해 분산 트레이싱, 메트릭, 시각화를 포함한 종합 관측가능성(Observability)을 구현하는 가이드. 메시 모니터링 구축, 지연 원인 분석, 서비스 통신 SLO 구현 시 사용.
---

# Service Mesh Observability 요약 (한국어)

## 목적
- 서비스 메시 환경에서 **메트릭·트레이스·로그**를 체계적으로 수집/분석/시각화하여 **성능(지연), 안정성(오류), 연결성(의존성)** 문제를 빠르게 진단하고 **SLO 기반 운영**을 가능하게 함.

## 사용 시점 (When to Use)
- 서비스 간 **분산 트레이싱**을 설정해야 할 때
- 메시 **메트릭 수집 및 대시보드**(Grafana 등)를 구성할 때
- **지연(latency)**, **오류(5xx)**, **연결 문제**를 디버깅할 때
- 서비스 통신에 대한 **SLO/알림 규칙**을 설계·적용할 때
- 서비스 간 **의존성/토폴로지 시각화**가 필요할 때

## 핵심 개념 (Core Concepts)

### 1) 관측가능성 3대 축 (Three Pillars)
- **메트릭(Metrics)**: 요청률, 오류율, 지연(P50/P99), 포화도(리소스 사용률) 등 수치 기반 상태 파악
- **트레이스(Traces)**: 스팬 컨텍스트/지연/의존성/병목을 통해 요청 흐름의 원인 분석
- **로그(Logs)**: 액세스 로그, 오류 상세, 디버그 정보, 감사 추적 등 정황 정보 제공

### 2) 메시 운영의 Golden Signals
- **Latency(지연)**: P50/P99 등 (예: P99 > 500ms 경보 기준)
- **Traffic(트래픽)**: RPS/요청량 (이상 탐지 기반 경보)
- **Errors(오류)**: 5xx 비율 (예: > 1% 또는 더 엄격히)
- **Saturation(포화)**: 리소스 사용률 (예: > 80%)

## 제공 템플릿/예시 구성 (Templates)

### Istio + Prometheus + Grafana
- Prometheus 스크레이프 설정 및(또는) Prometheus Operator의 **ServiceMonitor**로 Istio 메트릭 수집 구성 예시 제공

### Istio 핵심 메트릭 PromQL 예시
- 서비스별 **요청률**, **5xx 오류율**, **P99 지연**(histogram_quantile), **TCP 연결 수**, **요청 크기** 등 운영에 바로 쓰는 쿼리 제공

### Jaeger 기반 분산 트레이싱(Istio)
- Istio `meshConfig`에서 **트레이싱 활성화**, 샘플링(개발 100%, 운영은 축소 권장)
- `jaegertracing/all-in-one` 기반 **Jaeger 배포 예시** 포함

### Linkerd Viz 대시보드/CLI
- `linkerd viz` 확장 설치 및 대시보드 접속
- `top`, `routes`, `tap`, `edges` 등 **실시간 트래픽/라우트/의존성** 관측 명령 예시 제공

### Grafana 대시보드 JSON 예시
- 요청률/오류율(게이지)/P99 지연/서비스 토폴로지(NodeGraph) 패널 구성 예시 제공

### Kiali 시각화(Istio)
- Kiali CR 예시: 인증 전략(anonymous/openid/token), 접근 네임스페이스 범위
- Prometheus/Tracing/ Grafana 연동 URL 설정으로 **서비스 그래프/트래픽 플로우 시각화** 지원

### OpenTelemetry(OTel) 연동
- OTel Collector 구성(OTLP/Zipkin 수신, Jaeger/Prometheus 내보내기, 배치 프로세서)
- Istio Telemetry 설정 예시로 **샘플링 비율** 지정 및 OTel 프로바이더 연결

## 알림 규칙 (Alerting Rules)
- PrometheusRule 예시 제공:
  - **HighErrorRate**: 5xx 비율이 임계치(예: 5%) 초과 시 경보
  - **HighLatency**: P99 지연이 임계치(예: 1000ms) 초과 시 경보
  - **MeshCertExpiring**: 인증서 만료가 7일 이내로 임박 시 경보

## 운영 모범 사례 (Best Practices)

### 권장(Do’s)
- 환경별 **샘플링 전략** 적용(개발 100%, 운영 1–10% 등)
- 트레이스 **컨텍스트 전파**(헤더) 일관성 유지
- Golden Signals 중심의 **알림 체계** 구축
- 메트릭-트레이스 **상관분석**(예: exemplars) 활용
- 보관 정책을 **핫/콜드 계층**으로 전략적으로 설계

### 비권장(Don’ts)
- 과도한 샘플링으로 **저장/비용 증가** 유발 금지
- **카디널리티 폭증**(레이블 값 무분별 증가) 방지
- 대시보드 부재로 **의존성 가시성**을 잃지 않기
- 관측성 자체의 **비용/자원 사용량**도 함께 모니터링

## 참고 자료 (Resources)
- Istio Observability, Linkerd Observability, OpenTelemetry, Kiali 공식 문서 링크 제공

## [원본 파일]
- (사용자 제공 텍스트) `service-mesh-observability` 스킬 정의 내용