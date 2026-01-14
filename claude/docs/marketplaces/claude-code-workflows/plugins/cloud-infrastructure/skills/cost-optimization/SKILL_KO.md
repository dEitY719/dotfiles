---
name: cost-optimization
description: 리소스 라이트사이징, 태깅 전략, 예약 인스턴스, 지출 분석을 통해 클라우드 비용을 최적화합니다. 클라우드 비용 절감, 인프라 비용 분석, 비용 거버넌스 정책 구현 시 사용합니다.
---

# 클라우드 비용 최적화(Cloud Cost Optimization) 요약

AWS, Azure, GCP 전반에서 **성능/신뢰성을 유지하면서 지출을 줄이기 위한 체계적인 비용 최적화 전략**을 정리한 스킬입니다.

## 사용 목적(Goal)
- 클라우드 비용을 **가시화 → 최적화 → 거버넌스**로 연결해 지속적으로 절감
- 과다 프로비저닝/유휴 리소스 제거, 적정 규모 조정, 할인/약정 모델 활용

## 사용 시점(When to Use)
- 월별/분기별 클라우드 지출을 줄여야 할 때
- 리소스 라이트사이징(적정 규모 조정)이 필요할 때
- 태그 기반 비용 배분, 예산/경보 등 **비용 거버넌스**를 도입할 때
- 멀티클라우드 비용을 비교·최적화해야 할 때
- 예산 제약을 충족해야 할 때

## 비용 최적화 프레임워크(Framework)
### 1) 가시성(Visibility)
- 비용 배분 태그(Cost Allocation Tags) 표준화 및 적용
- 클라우드 비용 관리 도구 활용, 예산 경보(Budget Alerts) 설정
- 비용 대시보드 구성으로 추세/이상치 모니터링

### 2) 라이트사이징(Right-Sizing)
- CPU/메모리/스토리지 등 사용률 기반 분석
- 과다 할당 리소스 다운사이징, 유휴 리소스 제거
- 오토스케일링 도입으로 피크 대응 및 평시 비용 절감

### 3) 가격 모델(Pricing Models)
- 예약 용량/약정 할인(Reserved, Savings Plans, CUD 등) 활용
- 스팟/선점형 인스턴스(Spot/Preemptible)로 탄력적·배치성 워크로드 비용 절감
- 안정적 워크로드는 약정, 비정형/중단 허용 워크로드는 스팟 혼합 전략

### 4) 아키텍처 최적화(Architecture Optimization)
- 관리형 서비스로 운영 부담과 총비용(TCO) 절감
- 캐싱 도입, 데이터 전송 비용 최적화
- 스토리지 수명주기(Lifecycle) 정책으로 계층화(Hot/Warm/Cold/Archive)

## 클라우드별 핵심 전략
### AWS
- **Reserved Instances / Savings Plans**: 온디맨드 대비 큰 폭 절감(약정 기간·유연성 선택)
- **Spot Instances**: 최대 수준 절감 가능하나 중단 리스크(사전 통지) 고려, 혼합 운영 권장
- **S3 비용 최적화**: Lifecycle 설정으로 `STANDARD → IA → GLACIER` 등 자동 전환 및 만료

### Azure
- **Reserved VM Instances**: 1/3년 약정, 높은 절감률, 교환/유연성 옵션
- **Azure Hybrid Benefit**: 보유 라이선스(Windows/SQL) 활용로 추가 절감
- **Azure Advisor**: 라이트사이징, 미사용 리소스 제거, 예약/스토리지 최적화 권고 활용

### GCP
- **Committed Use Discounts(CUD)**: 1/3년 약정 기반 할인(리소스/지출 기반 옵션)
- **Sustained Use Discounts**: 별도 약정 없이 장시간 실행 시 자동 할인
- **Preemptible VMs**: 배치성 워크로드에 적합(최대 실행 시간 등 제약 고려)

## 태깅 전략(Tagging Strategy)
- `Environment`, `Project`, `CostCenter`, `Owner`, `ManagedBy` 등 공통 태그로 **비용 배분/책임/추적성** 확보
- Terraform 등 IaC로 태그 강제 및 일관성 유지
- 태그 표준은 `references/tagging-standards.md`를 참조하도록 안내

## 모니터링 및 거버넌스(Cost Monitoring)
- **예산 경보(Budget Alerts)**: 월 예산/임계치(예: 80%) 초과 시 알림
- **이상 비용 탐지(Anomaly Detection)**: AWS/ Azure/ GCP의 비용 경보 기능으로 급격한 지출 변화 감지

## 대표 아키텍처 패턴(Patterns)
- **Serverless First**: 실행 시간 기반 과금, 유휴 비용 최소화, 자동 확장
- **DB 라이트사이징**: 환경별(Dev/Staging/Prod) 크기 차등, 읽기 복제 등으로 비용/성능 균형
- **스토리지 계층화**: Hot/Warm/Cold/Archive로 데이터 수명주기 기반 비용 최적화
- **오토스케일링**: 메트릭 알람 기반 스케일 정책으로 과잉 용량 방지

## 체크리스트(Checklist)
- 태그 적용, 유휴 리소스 정리(EBS/EIP/스냅샷 등)
- 사용률 기반 인스턴스 라이트사이징
- 안정 워크로드 예약/약정, 배치성 워크로드 스팟/선점 활용
- 오토스케일링/캐싱/관리형 서비스 도입
- 스토리지 클래스 및 Lifecycle 정책 최적화
- 이상 탐지 및 예산 경보 설정, 주간 비용 리뷰로 지속 개선

## 도구(Tools)
- AWS: Cost Explorer, Cost Anomaly Detection, Compute Optimizer
- Azure: Cost Management, Advisor
- GCP: Cost Management, Recommender
- 멀티클라우드: CloudHealth, Cloudability, Kubecost

## 관련 스킬(Related Skills)
- `terraform-module-library`: 리소스 프로비저닝 표준화/재사용
- `multi-cloud-architecture`: 클라우드 선택/설계 관점의 최적화 연계

---

## [원본 파일]
- 경로: `미제공(프롬프트에 원문이 직접 포함됨)`