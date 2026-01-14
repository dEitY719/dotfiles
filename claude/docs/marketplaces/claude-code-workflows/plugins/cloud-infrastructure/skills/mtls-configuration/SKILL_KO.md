---
name: mtls-configuration
description: 제로 트러스트 기반의 서비스-투-서비스 통신을 위해 상호 TLS(mTLS)를 구성합니다. 제로 트러스트 네트워킹 구현, 인증서 관리, 내부 서비스 통신 보안 강화가 필요할 때 사용합니다.
---

# mTLS Configuration 요약 (한국어)

제로 트러스트 서비스 메시 환경에서 **mTLS(상호 TLS)** 를 구현·운영하기 위한 종합 가이드입니다. 서비스 간 통신을 **양방향 인증(클라이언트/서버 모두 인증서 제시 및 검증)** 과 **암호화 채널**로 보호하는 데 초점을 둡니다.

## 사용 시점(When to Use)
- 제로 트러스트 네트워킹 구현
- 마이크로서비스/내부 서비스 간 통신 보안 강화
- 인증서 발급·회전(로테이션)·만료 관리
- TLS 핸드셰이크/연결 오류 디버깅
- 규정 준수(PCI-DSS, HIPAA 등) 대응
- 멀티 클러스터 간 보안 통신 구축

## 핵심 개념(Core Concepts)

### 1) mTLS 흐름(mTLS Flow)
- 각 서비스 앞단의 프록시(사이드카)가 TLS 핸드셰이크를 수행
- 서버 인증서뿐 아니라 **클라이언트 인증서도 교환**
- 양측이 서로의 인증서 체인을 검증한 뒤 암호화 채널을 형성

### 2) 인증서 계층(Certificate Hierarchy)
- **Root CA(장기/자체서명)** → **Intermediate CA(클러스터 단위)** → **워크로드(서비스) 인증서**
- 멀티 클러스터 환경에서는 별도 Intermediate 또는 교차 클러스터 신뢰 구성이 포함될 수 있음

## 제공 템플릿(Templates) 요약

### Template 1: Istio mTLS (Strict Mode)
- 메시 전체 기본 정책을 `STRICT`로 설정해 **기본적으로 모든 서비스 간 mTLS 강제**
- 마이그레이션을 위해 네임스페이스 단위로 `PERMISSIVE` 예외 허용 가능
- 워크로드/포트 단위로 `STRICT`/`DISABLE` 등 세밀한 정책 적용(예: 메트릭 포트는 예외)

### Template 2: Istio DestinationRule for mTLS
- 내부 서비스에 `ISTIO_MUTUAL`로 **Istio가 관리하는 상호 TLS 적용**
- 외부 서비스에 대해:
  - `SIMPLE`: 서버 인증만 검증(외부 CA 지정)
  - `MUTUAL`: 클라이언트 인증서/키 + 외부 CA를 지정해 **상호 TLS 구성**

### Template 3: cert-manager + Istio 연동
- `ClusterIssuer`로 CA 기반 발급 체계를 구성
- `Secret`에 CA 인증서/키를 저장해 Issuer가 참조
- 워크로드용 `Certificate` 리소스로 **짧은 수명(예: 24h)** 인증서 발급 및 `renewBefore`로 자동 갱신 유도
- 서비스 DNS 이름/용도(`server auth`, `client auth`)를 명시해 mTLS 요구에 맞춤

### Template 4: SPIFFE/SPIRE 통합
- SPIRE Server 설정(신뢰 도메인, CA TTL, SVID TTL, 데이터스토어, 노드 어테스테이션 등)
- SPIRE Agent를 DaemonSet으로 배포해 노드 전반에 워크로드 신원/인증서(SVID) 제공 기반 마련

### Template 5: Linkerd mTLS (Automatic)
- Linkerd는 기본적으로 mTLS를 자동 활성화하는 운영 모델을 전제
- 관측 명령으로 엣지/트래픽 상태 확인
- 외부 연동 등 mTLS가 없는 대상에 대해 포트/정책 단위로 예외 또는 패스스루 설정 가이드 포함

## 인증서 로테이션(Certificate Rotation)
- Istio에서 프록시가 보유한 인증서 만료/내용을 확인하는 예시(예시 파이프라인: `istioctl` + `jq` + `openssl`)
- 필요 시 배포 롤아웃 재시작으로 인증서 재발급/재로딩 유도
- Linkerd의 identity 상태 확인 명령 제공

## mTLS 이슈 디버깅(Debugging)
- Istio: mTLS 적용 여부 점검, PeerAuthentication/DestinationRule 조회, 프록시 로그 레벨 조정 및 TLS 관련 로그 필터링
- Linkerd: mTLS 상태/트래픽을 관측 도구로 확인(엣지/탭)

## 모범 사례(Best Practices)

### Do’s
- 초기엔 `PERMISSIVE`로 시작해 점진적으로 `STRICT`로 전환
- 인증서 만료 모니터링/알림 체계 구축
- 워크로드 인증서는 짧은 수명(예: 24시간 이하) 권장
- CA 로테이션을 정기적으로 계획/실행
- TLS 오류 로깅을 통해 디버깅 및 감사(Audit) 가능성 확보

### Don’ts
- 운영 환경에서 편의상 mTLS를 비활성화하지 않기
- 인증서 만료를 방치하지 말고 자동 회전 체계화
- 무분별한 자체서명 인증서 사용 지양(적절한 CA 계층 사용)
- 전체 체인(루트/중간/워크로드) 검증을 생략하지 않기

## 참고 자료(Resources)
- Istio Security, SPIFFE/SPIRE, cert-manager, NIST Zero Trust Architecture 링크 제공

## [원본 파일]
- 경로: (사용자가 원본 파일 경로를 제공하지 않음)