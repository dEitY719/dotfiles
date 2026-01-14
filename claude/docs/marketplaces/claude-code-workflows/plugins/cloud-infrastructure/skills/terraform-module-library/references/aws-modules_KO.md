```yaml
---
name: aws-terraform-module-patterns
description: AWS 인프라 구성요소별 Terraform 모듈 패턴(VPC/EKS/RDS/S3/ALB/Lambda/보안 그룹)과 운영 모범 사례를 정리한 문서
model: gpt-5.2
---
```

# AWS Terraform Module Patterns 요약

## 개요
- AWS에서 자주 사용하는 인프라 구성요소를 Terraform 모듈로 표준화할 때 포함해야 할 기능 체크리스트를 제시합니다.
- 보안(암호화/최소 권한), 운영(태깅/로깅/모니터링/백업) 관점의 공통 모범 사례를 함께 제공합니다.

## 모듈별 주요 기능

### VPC 모듈
- 퍼블릭/프라이빗 서브넷을 포함한 VPC 구성
- Internet Gateway 및 NAT Gateway 구성
- 라우트 테이블과 서브넷 연결(association) 구성
- Network ACL 구성
- VPC Flow Logs 활성화

### EKS 모듈
- 관리형 노드 그룹(Managed Node Groups)을 포함한 EKS 클러스터 구성
- IRSA(IAM Roles for Service Accounts) 설정
- Cluster Autoscaler 구성
- VPC CNI 설정
- 클러스터 로깅 활성화

### RDS 모듈
- RDS 인스턴스 또는 클러스터 구성
- 자동 백업 설정
- 읽기 복제본(Read Replica) 구성
- 파라미터 그룹(Parameter Group) 관리
- 서브넷 그룹(Subnet Group) 구성
- 보안 그룹(Security Group) 설정

### S3 모듈
- 버저닝(Versioning) 활성화
- 저장 데이터 암호화(Encryption at rest) 적용
- 버킷 정책(Bucket Policy) 관리
- 라이프사이클 규칙(Lifecycle Rules) 설정
- 복제(Replication) 구성

### ALB 모듈
- Application Load Balancer 구성
- 타깃 그룹(Target Groups) 구성
- 리스너 규칙(Listener Rules) 정의
- SSL/TLS 인증서 구성
- 액세스 로그(Access Logs) 활성화

### Lambda 모듈
- Lambda 함수 구성
- 실행 IAM 역할(Execution Role) 구성
- CloudWatch Logs 연동
- 환경 변수(Environment Variables) 설정
- (선택) VPC 구성 적용

### Security Group 모듈
- 재사용 가능한 보안 그룹 규칙 구성
- 인바운드/아웃바운드(Ingress/Egress) 규칙 정의
- 동적 규칙 생성 지원
- 규칙 설명(Description) 표준화

## 모범 사례(Best Practices)
1. AWS Provider 버전은 `~> 5.0` 사용
2. 기본적으로 암호화 활성화
3. 최소 권한(Least-Privilege) IAM 적용
4. 모든 리소스에 일관된 태그 적용
5. 로깅 및 모니터링 활성화
6. KMS 기반 암호화 사용
7. 백업 전략 구현
8. 가능하면 PrivateLink 사용
9. GuardDuty/SecurityHub 활성화
10. AWS Well-Architected Framework 준수

## [원본 파일]
- 원본 파일 경로: 제공되지 않음(사용자 메시지 내 원문 텍스트)