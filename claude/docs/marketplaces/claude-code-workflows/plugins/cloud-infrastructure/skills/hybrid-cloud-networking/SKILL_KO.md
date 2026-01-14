---
name: hybrid-cloud-networking
description: Configure secure, high-performance connectivity between on-premises infrastructure and cloud platforms using VPN and dedicated connections. Use when building hybrid cloud architectures, connecting data centers to cloud, or implementing secure cross-premises networking.
---

# Hybrid Cloud Networking (요약)

## 개요
- 온프레미스 데이터센터와 클라우드(AWS/Azure/GCP) 간에 **안전하고 안정적이며 고성능의 네트워크 연결**을 구축하는 가이드입니다.
- **VPN(인터넷 기반 IPSec)** 과 **전용 회선(Direct Connect/ExpressRoute/Interconnect)** 을 중심으로 구성하며, 예시로 **Terraform(HCL)** 리소스 설정이 포함됩니다.

## 목적(Purpose)
- 온프레미스 ↔ 클라우드 간 **보안(암호화/사설 연결)과 신뢰성(고가용성/이중화)** 을 갖춘 연결을 표준화합니다.

## 사용 시점(When to Use)
- 온프레미스를 클라우드에 연결하거나 데이터센터를 클라우드로 확장할 때
- 하이브리드 **Active-Active** 구성(자동 장애조치/부하분산 포함)이 필요할 때
- 규정 준수(컴플라이언스) 요구로 네트워크 경로/보안을 강화해야 할 때
- 단계적 클라우드 마이그레이션을 진행할 때

## 연결 옵션(Connection Options)

### AWS
- **Site-to-Site VPN**: 인터넷 기반 IPSec, 터널당 최대 1.25Gbps 수준, 비용 효율적이나 인터넷 의존/지연 증가 가능
- **Direct Connect**: 전용 연결(1~100Gbps), 낮은 지연과 안정적 대역폭 제공(비용/구축 리드타임 증가)

### Azure
- **Site-to-Site VPN**: `azurerm_virtual_network_gateway` 등으로 구성(예시 HCL 포함)
- **ExpressRoute**: 통신사업자 기반 사설 연결(최대 100Gbps), 고신뢰/저지연, 글로벌 연결은 Premium 고려

### GCP
- **Cloud VPN**: IPSec(클래식/HA), HA VPN은 99.99% SLA, 터널당 최대 3Gbps 수준
- **Cloud Interconnect**: Dedicated(10/100Gbps) 또는 Partner(50Mbps~50Gbps), VPN 대비 낮은 지연

## 하이브리드 네트워크 패턴(Hybrid Network Patterns)
- **Hub-and-Spoke**: 중앙 허브(예: AWS Transit Gateway, Azure vWAN)를 통해 Prod/Staging/Dev VPC/VNet을 분리·연결
- **Multi-Region Hybrid**: 각 리전에 전용 연결을 두고 리전 간 피어링/연동으로 확장
- **Multi-Cloud Hybrid**: 온프레미스에서 AWS/Azure/GCP 각각에 전용 연결을 구성해 멀티클라우드 연계를 구현

## 라우팅 구성(Routing Configuration)
- **BGP 기반 동적 라우팅**: 온프레미스/클라우드 라우터 간 AS 번호 및 광고(Advertise) 프리픽스를 정의
- **Route Propagation**: 라우트 테이블 전파 활성화, 라우트 필터링(정책 기반 통제), 광고 상태 모니터링 권장

## 보안 모범 사례(Security Best Practices)
- 전용 사설 연결(Direct Connect/ExpressRoute 등) 우선 고려, VPN은 터널 암호화/키 관리 강화
- 인터넷 경로 회피를 위해 **VPC 엔드포인트/PrivateLink(Private Endpoints)** 활용
- **NACL/Security Group** 최소 권한 구성, **Flow Logs** 등 로깅/가시성 확보
- **DDoS 보호**, 연결 상태/로그에 대한 정기 모니터링 및 **정기 보안 감사** 수행
- **이중 터널/다중 회선**으로 장애 대비(단일 장애점 제거)

## 고가용성(High Availability)
- **Dual VPN Tunnels**: 2개 터널로 이중화(예시 HCL 포함)
- **Active-Active**: 다중 위치/다중 연결 + BGP 자동 장애조치 + ECMP(동일비용 다중경로) + 헬스 모니터링

## 모니터링 및 트러블슈팅(Monitoring & Troubleshooting)
- 핵심 지표: 터널 상태, In/Out 바이트, 패킷 손실, 지연, BGP 세션 상태
- 예시 명령: AWS(`aws ec2 describe-vpn-connections`, `get-vpn-connection-telemetry`), Azure(`az network vpn-connection show` 등)

## 비용 최적화(Cost Optimization)
- 트래픽 기반 **회선/대역폭 적정화**, 저대역 워크로드는 VPN 활용
- 연결 수를 줄이도록 트래픽을 집약하고 데이터 전송 비용을 최소화
- 고대역/일관된 성능 요구는 전용 연결 채택, 캐싱으로 트래픽 절감

## 참조 및 연관(Reference Files / Related Skills)
- 참조 문서: `references/vpn-setup.md`, `references/direct-connect.md`
- 연관 스킬: `multi-cloud-architecture`, `terraform-module-library`

## [원본 파일]
- 파일 경로 미제공(사용자가 본문 텍스트로 원본 내용을 제공)