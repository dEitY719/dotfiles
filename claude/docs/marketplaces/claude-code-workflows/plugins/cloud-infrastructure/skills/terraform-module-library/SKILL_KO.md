---
name: terraform-module-library
description: Build reusable Terraform modules for AWS, Azure, and GCP infrastructure following infrastructure-as-code best practices. Use when creating infrastructure modules, standardizing cloud provisioning, or implementing reusable IaC components.
---

# Terraform Module Library 요약

## 개요
- AWS, Azure, GCP를 대상으로 **재사용 가능하고 운영 환경에 적합한(Production-ready) Terraform 모듈 패턴**을 표준화하기 위한 가이드입니다.
- 멀티클라우드 환경에서 공통 인프라 구성요소를 **일관된 구조/문서/테스트 체계**로 제공하는 것을 목표로 합니다.

## 목적(Purpose)
- 다양한 클라우드 공급자에서 반복되는 인프라 패턴을 **모듈화**하여 재사용성을 높이고, **검증된 IaC(Infrastructure as Code) 모범 사례**를 적용합니다.

## 사용 시점(When to Use)
- 조직 내에서 **표준 모듈 카탈로그**를 구축할 때
- VPC/VNet, Kubernetes(EKS/AKS/GKE), DB(RDS/Cloud SQL) 등 **공통 컴포넌트를 재사용**하려 할 때
- 멀티클라우드에 대응하는 **일관된 프로비저닝 규칙/인터페이스(variables/outputs)**가 필요할 때

## 디렉터리/모듈 구조(Module Structure)
- 최상위에서 클라우드별로 분리(`aws/`, `azure/`, `gcp/`)하고, 그 아래에 도메인별 모듈(예: `vpc`, `eks`, `rds`)을 둡니다.
- 각 모듈은 일반적으로 다음 파일 체계를 따릅니다:
  - `main.tf`: 리소스 정의(핵심)
  - `variables.tf`: 입력 변수(설명/타입/검증 포함)
  - `outputs.tf`: 외부 모듈/스택과 조합을 위한 출력
  - `versions.tf`: Provider 버전 고정
  - `README.md`: 사용법/설계 의도/입출력 문서
  - `examples/complete`: 완전한 사용 예제
  - `tests/`: Terratest 기반 테스트

## AWS VPC 예시에서 강조하는 핵심
- **태깅 일관성**: `merge()`로 기본 태그와 사용자 태그를 결합해 모든 리소스에 동일한 태그 전략 적용
- **조건부 리소스 생성**: `count`를 활용해 인터넷 게이트웨이 등 옵션 리소스를 필요 시에만 생성
- **입력 검증(Validation)**: CIDR 같은 핵심 입력값에 정규식 기반 검증을 추가해 잘못된 구성을 사전에 차단
- **모듈 조합을 위한 출력 설계**: `vpc_id`, `subnet_ids` 같은 속성을 출력해 다른 모듈(RDS 등)과 연결

## 모범 사례(Best Practices)
- 모듈은 **시맨틱 버저닝**을 적용해 변경 영향도를 명확히 관리
- 모든 변수에 **설명/타입/기본값/검증**을 제공
- `examples/`에 실사용 가능한 예제를 포함
- `versions.tf`로 Provider 버전을 고정해 재현성을 확보
- `locals`, `count/for_each`로 계산값/조건부 생성 패턴을 표준화
- Terratest로 **모듈 동작을 자동 검증**하고, 리소스 태깅 정책을 일관되게 유지

## 모듈 컴포지션(Module Composition)
- 상위 스택에서 `module "vpc"`의 출력값(`vpc_id`, `private_subnet_ids`)을 `module "rds"`의 입력으로 전달하는 방식으로 **모듈 간 결합**을 구성합니다.
- 결과적으로 네트워크 → 데이터베이스처럼 의존 관계가 있는 구성요소를 **느슨하게(출력/입력 계약으로) 결합**합니다.

## 참고/테스트(Reference & Testing)
- `assets/`와 `references/`에 클라우드별 모듈 패턴과 완성 예제가 제공된다는 전제를 둡니다.
- 테스트는 Go 기반 Terratest로 `init/apply` 후 출력값을 검증하고, 테스트 종료 시 `destroy`로 정리하는 패턴을 사용합니다.

## 관련 스킬(Related Skills)
- `multi-cloud-architecture`: 멀티클라우드 아키텍처 의사결정 보조
- `cost-optimization`: 비용 효율 설계 관점 보강

## [원본 파일]
- 원본 파일 경로: (사용자 제공 경로 없음 — 본 대화에 인라인 텍스트로 제공됨)