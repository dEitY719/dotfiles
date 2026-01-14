---
name: istio-traffic-management
description: Configure Istio traffic management including routing, load balancing, circuit breakers, and canary deployments. Use when implementing service mesh traffic policies, progressive delivery, or resilience patterns.
---

# Istio 트래픽 관리 요약

프로덕션 서비스 메시 환경에서 Istio의 트래픽 관리(라우팅/정책/탄력성/점진 배포)를 구성하기 위한 실전 가이드입니다.

## 이 스킬을 사용할 때
- 서비스 간 라우팅 규칙 설정(특정 사용자/헤더/경로 기반 라우팅 등)
- 카나리/블루-그린 등 점진적 배포 구성(트래픽 가중치 분배)
- 재시도/타임아웃/서킷 브레이커 등 복원력 패턴 적용
- 로드밸런싱 정책(라운드로빈, 최소연결, 세션 고정 등)
- 트래픽 미러링(테스트/검증 목적)
- 장애 주입(지연/에러) 기반 카오스 엔지니어링

## 핵심 개념
### 트래픽 관리 리소스 역할
- `VirtualService`: **라우팅 규칙** 정의(어떤 트래픽을 어디로 보낼지)
- `DestinationRule`: 라우팅 이후 **대상 서비스 정책** 정의(로드밸런싱, 연결 풀, 이상 감지 등)
- `Gateway`: 인그레스/이그레스 **게이트웨이** 구성(클러스터 경계 트래픽)
- `ServiceEntry`: 메시 내부에서 **외부 서비스**를 인지/접속 가능하게 등록

### 트래픽 흐름(개념)
- Client → Gateway → VirtualService(라우팅) → DestinationRule(정책) → Service/Pods

## 제공 템플릿(구성 예시의 의도)
- **기본 라우팅**: 헤더 매칭(예: 특정 사용자) 시 특정 `subset`(버전)으로 라우팅, 그 외 기본 버전으로 라우팅
- **카나리 배포**: `weight`로 stable/canary 트래픽 비율 분배 + `trafficPolicy`로 커넥션 풀/HTTP 설정
- **서킷 브레이커**: 연결 풀 제한 + `outlierDetection`으로 비정상 엔드포인트 격리(에러 기준, 격리 시간/비율 등)
- **재시도/타임아웃**: 요청 타임아웃과 재시도 횟수/조건/시도별 타임아웃 구성
- **트래픽 미러링**: 실제 트래픽은 v1로 보내면서, 동일 트래픽을 v2로 미러링(검증/관찰 목적)
- **장애 주입**: 일부 비율에 지연(delay) 또는 오류(abort/HTTP 503) 주입
- **인그레스 게이트웨이**: TLS(시크릿 기반) 포함한 HTTPS 인그레스 + 경로(prefix) 기반 라우팅
- **로드밸런싱 전략**: 단순 알고리즘(ROUND_ROBIN 등) 및 일관 해시 기반 세션 고정(예: 헤더 `x-user-id`)

## 베스트 프랙티스(요지)
- Do: 단순하게 시작 → 점진적으로 확장, 버전 `subset` 명확화, 합리적 타임아웃 기본 적용, 재시도는 제한/백오프 고려, Kiali/Jaeger 등으로 관측성 확보
- Don’t: 과도한 재시도(연쇄 장애 유발), 이상 감지/서킷 브레이커 무시, 프로덕션에 무분별한 미러링, 카나리는 소량 트래픽부터 시작

## 디버깅 명령(요지)
- `istioctl analyze`: 구성 오류/잠재 이슈 분석
- `istioctl proxy-config routes/endpoints`: Envoy에 반영된 라우트/엔드포인트 확인
- `istioctl proxy-config log ... --level debug`: 프록시 로그 레벨 조정으로 트래픽 문제 추적

## 추가 참고자료
- Istio 트래픽 관리 개념 및 `VirtualService`/`DestinationRule` 레퍼런스 링크 제공

## [원본 파일]
- 경로: `(사용자 제공 정보에 없음)`