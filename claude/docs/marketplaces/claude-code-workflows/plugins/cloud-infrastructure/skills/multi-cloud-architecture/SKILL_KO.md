---
name: multi-cloud-architecture
description: AWS, Azure, GCP 전반에서 서비스 선택·통합을 위한 의사결정 프레임워크로 멀티클라우드 아키텍처를 설계한다. 벤더 종속을 피하거나, 각 클라우드의 강점을 조합해(best-of-breed) 멀티클라우드 시스템을 구축할 때 사용한다.
---

# Multi-Cloud Architecture (요약)

## 개요
AWS·Azure·GCP를 동시에 고려하는 멀티클라우드 아키텍처를 설계하기 위한 **의사결정 프레임워크와 대표 패턴**을 제공한다. 목표는 **클라우드 종속 최소화**, **워크로드별 최적 서비스 선택**, **비용/가용성/규정 준수 최적화**다.

## 사용 시점(When to Use)
- 멀티클라우드 전략 수립 및 표준화
- 클라우드 간 마이그레이션/이전
- 워크로드 특성에 맞춘 클라우드 서비스 선정
- 클라우드-중립(agnostic) 아키텍처 구현
- 클라우드 간 비용 최적화(특히 데이터 전송/컴퓨트/예약 할인)

## 핵심 기능 1) 클라우드 서비스 비교 프레임
- **컴퓨트**: VM(EC2/VM/Compute Engine), 컨테이너(ECS/Container Instances/Cloud Run), 쿠버네티스(EKS/AKS/GKE), 서버리스(Lambda/Functions/Cloud Functions) 등으로 동등군을 매핑해 선택을 돕는다.
- **스토리지**: 오브젝트(S3/Blob/Cloud Storage), 블록(EBS/Managed Disks/Persistent Disk), 파일(EFS/Azure Files/Filestore), 아카이브(Glacier/Archive/Archive) 비교를 제공한다.
- **데이터베이스**: 관리형 SQL(RDS/SQL Database/Cloud SQL), NoSQL(DynamoDB/Cosmos DB/Firestore), 분산 SQL(Aurora/Cloud Spanner 등), 캐시(ElastiCache/Cache for Redis/Memorystore) 비교를 제시한다.
- 전체 비교 확장은 `references/service-comparison.md`를 참고하도록 안내한다.

## 핵심 기능 2) 멀티클라우드 대표 패턴 4가지
1. **단일 클라우드 운영 + 타 클라우드 DR(재해복구)**: 주 운영은 한 곳, DR은 다른 곳에 두고 복제/자동 페일오버를 설계.
2. **Best-of-Breed(강점 조합)**: 예) AI/ML은 GCP, 엔터프라이즈 앱은 Azure, 범용 컴퓨트는 AWS 등 워크로드별 최적 클라우드를 선택.
3. **지리적 분산(Geographic Distribution)**: 사용자 근접 리전 제공, 데이터 주권/규정 준수, 글로벌 로드밸런싱, 지역 장애 시 페일오버.
4. **클라우드-중립 추상화(Cloud-Agnostic Abstraction)**: Kubernetes, PostgreSQL, S3 호환 스토리지(MinIO), 오픈소스 기반으로 이식성을 강화.

## 핵심 기능 3) 클라우드-중립 아키텍처 구성 가이드
- **클라우드 네이티브 대체 수단 제시**: 컴퓨트(Kubernetes), DB(PostgreSQL/MySQL), 메시징(Kafka 계열), 캐시(Redis), 모니터링(Prometheus/Grafana), 서비스 메시(Istio/Linkerd) 등.
- **추상화 레이어 권장**: 애플리케이션 위에 Terraform/OpenTofu 같은 IaC로 인프라를 선언하고, 그 아래에서 각 클라우드 API를 흡수하는 계층 구조를 제시한다.

## 핵심 기능 4) 비용 비교 관점 및 최적화 체크리스트
- **과금 모델 비교 포인트**: 온디맨드, 예약/커밋, 스팟/프리엠티블 등 클라우드별 할인/옵션 체계를 정리.
- **최적화 전략**: 예약/커밋(대략 30–70% 절감 가능), 스팟 활용, 리소스 라이트사이징, 변동 워크로드 서버리스 전환, 데이터 전송비 최적화, 라이프사이클 정책, 비용 태그/할당, 비용 도구 모니터링.

## 마이그레이션 전략(단계별)
- **Assessment**: 인프라 인벤토리, 의존성 파악, 호환성/비용 평가
- **Pilot**: 파일럿 워크로드 선정, 대상 클라우드 구현, 테스트, 학습 문서화
- **Migration**: 점진적 이전, 듀얼런(병행 운영) 기간, 성능 모니터링, 기능 검증
- **Optimization**: 라이트사이징, 관리형/클라우드 네이티브 채택, 비용/보안 강화

## 베스트 프랙티스(요지)
- IaC(Terraform/OpenTofu) 및 CI/CD로 표준화·자동화
- 멀티클라우드 장애를 전제로 한 설계(복구·페일오버 테스트 포함)
- 가능한 관리형 서비스 활용 + 관측성(모니터링) 포괄
- 비용 최적화 자동화와 태깅, 클라우드별 설정 문서화
- 팀의 멀티클라우드 운영 역량 교육

## 참고/연계
- 참고 파일: `references/service-comparison.md`, `references/multi-cloud-patterns.md`
- 관련 스킬: `terraform-module-library`, `cost-optimization`, `hybrid-cloud-networking`

## [원본 파일]
- (사용자 제공 텍스트; 원본 파일 경로 미제공)