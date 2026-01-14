---
name: linkerd-patterns
description: 경량·보안 중심의 서비스 메시(Linkerd) 배포를 위해, Linkerd 설치/트래픽 정책/최소 오버헤드의 제로 트러스트 네트워킹 패턴을 구현할 때 사용하는 스킬.
---

# Linkerd Patterns (한국어 요약)

Kubernetes 환경에서 **Linkerd 서비스 메시**를 운영(Production) 수준으로 적용하기 위한 **검증된 패턴과 템플릿**을 제공한다. 목표는 **가벼운 오버헤드**, **보안 우선(mTLS/정책 기반 접근 제어)**, **관측성(라우트 단위 메트릭)**, **점진적 배포(카나리/A·B)**를 빠르게 구현하는 것이다.

## 사용 시점 (When to Use)
- 경량 서비스 메시를 도입/초기 구성할 때
- 자동 **mTLS**를 활성화하고 제로 트러스트 통신을 구현할 때
- **Traffic Split** 기반 카나리 배포/A·B 테스트를 구성할 때
- **ServiceProfile**로 라우트(경로) 단위 메트릭/재시도/타임아웃을 적용할 때
- 재시도/타임아웃 정책으로 안정성을 높일 때
- **멀티 클러스터** 서비스 메시를 구성할 때

## 핵심 개념 (Core Concepts)

### 1) 아키텍처 개요
- **Control Plane**: 서비스 디스커버리/아이덴티티(mTLS)/프록시 주입 등 메시의 제어 기능 담당
- **Data Plane**: 각 워크로드에 사이드카 **proxy**가 붙어 트래픽을 중계하며, mTLS/정책/관측성을 적용

### 2) 주요 리소스 (Key Resources)
- **ServiceProfile**: 라우트별 메트릭, 재시도(retry), 타임아웃(timeout) 등 **L7 동작 정의**
- **TrafficSplit**: 카나리 배포, A/B 테스트를 위한 **트래픽 분할**
- **Server**: 서버(수신) 측 정책의 기준이 되는 **보호 대상(포트/프로토콜/셀렉터) 정의**
- **ServerAuthorization**: 클라이언트(발신) 조건에 따른 **접근 제어 정책**(mTLS 서비스어카운트/비인증 허용 등)

## 제공 템플릿 (Templates)

### 1) 메시 설치 (Mesh Installation)
- Linkerd CLI 설치 → 사전 점검(`linkerd check --pre`) → CRD 설치 → 컨트롤 플레인 설치 → 설치 점검(`linkerd check`)  
- 선택 사항으로 **viz 확장**을 설치해 관측 기능을 활성화

### 2) 프록시 주입 (Inject Namespace/Workload)
- 네임스페이스 또는 특정 디플로이먼트에 `linkerd.io/inject: enabled` 어노테이션을 적용해 **자동 사이드카 주입**을 활성화

### 3) ServiceProfile + 재시도/타임아웃
- HTTP 메서드/경로 정규식 기반으로 라우트를 정의하고,
  - 5xx 응답을 실패로 분류
  - GET 등 안전한 요청에 대해 재시도 가능 여부 설정
  - 라우트별 타임아웃 지정
- **retryBudget**로 재시도 폭주(retry storm)를 방지(비율/최소 RPS/TTL)

### 4) TrafficSplit(카나리)
- 백엔드별 가중치로 트래픽을 분할(예: 안정 90%, 카나리 10%)하여 **점진적 롤아웃**을 구현

### 5) ServerAuthorization(접근 제어)
- **Server**로 보호할 서비스/포트/프로토콜(예: HTTP/1)을 정의한 뒤,
- **ServerAuthorization**으로
  - 특정 서비스어카운트(메시 mTLS)만 허용하거나
  - 인그레스 등에서 오는 **비인증 트래픽**을 네트워크 CIDR 조건과 함께 제한적으로 허용

### 6) HTTPRoute(고급 라우팅)
- 경로 프리픽스/헤더 조건 등으로 룰을 나눠 서로 다른 백엔드(예: v1, v2)로 라우팅하는 **세밀한 L7 라우팅**을 구성

### 7) 멀티 클러스터 (Multi-cluster)
- 각 클러스터에 multicluster 구성요소 설치 → 클러스터 간 링크 생성 → 서비스 export 라벨 부여 → 상태 점검/게이트웨이 확인

## 모니터링 명령 (Monitoring Commands)
- `linkerd viz top`: 실시간 트래픽/부하 관찰
- `linkerd viz routes`: 라우트 단위 메트릭 확인
- `linkerd viz stat`: 프록시/리소스 상태 통계
- `linkerd viz edges`: 서비스 의존 관계 시각화
- `linkerd viz dashboard`: 대시보드 실행

## 디버깅 (Debugging)
- 프록시 주입/상태 점검(`linkerd check --proxy`)
- 링크erd-proxy 컨테이너 로그 확인
- 아이덴티티/TLS 관련 진단
- `tap`으로 실시간 트래픽 관찰

## 베스트 프랙티스 (Best Practices)

### 권장(Do’s)
- mTLS는 기본 자동 제공이므로 **전 구간 활성화**를 전제로 설계
- **ServiceProfile**로 라우트 단위 관측/정책(재시도/타임아웃)을 적극 활용
- **retryBudget** 설정으로 장애 시 재시도 폭주를 예방
- 성공률/지연/처리량 등 **골든 메트릭** 중심으로 모니터링

### 비권장(Don’ts)
- 변경 후 `linkerd check`를 생략하지 말 것
- 기본값이 합리적이므로 과도한 설정으로 복잡도를 높이지 말 것
- ServiceProfile을 무시하면 고급 기능(라우트 메트릭/정책)을 활용하기 어려움
- 라우트별 **타임아웃** 누락은 장애 전파를 키울 수 있음

## [원본 파일]
- (사용자 제공 본문) `linkerd-patterns` 스킬 파일 내용