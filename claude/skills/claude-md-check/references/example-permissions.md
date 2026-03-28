# Example: Permission Control File (.company/steering/permissions.md)

This file is READ by agents — never modified during task execution.
Human review required before any changes.

---

```markdown
# 권한·임계값 설정

## 비용 임계값

\`\`\`yaml
auto_approve_limit: 50000  # 원. 이 금액 이하는 자동 승인
ceo_approval_above: 50000  # 원. 이 금액 이상은 CEO 승인 필요
monthly_ai_budget: 200     # USD. 월간 AI 운용 예산 상한
\`\`\`

## 자동 실행 (read-only) — 승인 불필요

\`\`\`yaml
auto_execute_readonly:
  - analytics_report      # 분석 리포트 생성
  - kpi_update            # KPI 대시보드 업데이트
  - competitor_analysis   # 경쟁사 조사 리포트
  - internal_docs         # 사내 문서 업데이트
\`\`\`

## 반드시 승인 필요 (always_draft)

\`\`\`yaml
always_draft:
  - proposal              # 제안서
  - contract              # 계약서
  - invoice               # 세금계산서
  - press_release         # 보도 자료
  - deploy_production     # 프로덕션 배포
  - pricing_change        # 가격 변경 공지
  - claim_response        # 클레임·불만 대응
  - client_communication  # 클라이언트 연락
  - marketing_email       # 마케팅 이메일
  - sns_post              # SNS 게시물
\`\`\`

## 자동 실행 (execute) — 임계값 내 내부 액션

\`\`\`yaml
auto_execute:
  - bugfix                # 버그 수정
  - minor_feature         # 마이너 기능 추가
  - test                  # 테스트 추가·수정
  - refactor              # 리팩토링
  - docs                  # 문서 업데이트
  - dependency_patch      # 의존 패키지 업데이트 (patch/minor)
  - internal_notification # 사내 알림
\`\`\`

## 한 번 승인된 템플릿 기반 자동 실행

\`\`\`yaml
auto_after_approval:
  - scheduled_sns         # 승인된 템플릿 기반 SNS 게시
  - faq_response          # 승인된 템플릿 기반 FAQ 답변
  - tech_article          # 리뷰 완료 기술 글
\`\`\`

## 배포 권한

\`\`\`yaml
deploy:
  local: execute          # 로컬 환경은 자유롭게
  staging: execute        # 스테이징도 자동 배포 가능
  production: draft       # 프로덕션은 항상 승인 필요
\`\`\`

## 이메일 발송 권한

\`\`\`yaml
email:
  internal_notification: execute    # 사내 알림은 자동
  client_communication: draft      # 클라이언트 연락은 확인 필요
  marketing_email: draft           # 마케팅 이메일도 확인 필요
  system_notification: execute     # 시스템 알림은 자동
\`\`\`

## 긴급 시 바이패스 규칙

\`\`\`yaml
emergency_bypass:
  conditions:
    - security_incident   # 보안 인시던트
    - service_down        # 서비스 중단
  actions_allowed:
    - hotfix_deploy       # 긴급 패치 배포
    - service_restart     # 서비스 재시작
  post_action:
    - notify_ceo          # 사후 보고 필수
    - log_to_decisions    # 의사결정 로그에 기록
\`\`\`

## 에스컬레이션 규칙

1. 자동 실행 태스크가 3회 연속 실패한 경우 → 관리자 알림
2. 예산의 80%에 도달한 경우 → 관리자 알림
3. 보안 인시던트 의심 시 → 즉시 관리자 알림
4. 사용자로부터 클레임 접수 → 즉시 관리자 알림

## 권한 설계 매트릭스

\`\`\`
             | read-only   | draft           | execute       |
─────────────┼─────────────┼─────────────────┼───────────────┤
 개발 부서    | 코드 분석   | 프로덕션 배포    | 버그 수정      |
             | 테스트 결과 | 신기능           | 테스트 추가    |
             | 의존성 감사 | DB 변경          | 리팩토링       |
─────────────┼─────────────┼─────────────────┼───────────────┤
 마케팅 부서  | SEO 감사   | 글 공개          | 글 집필        |
             | 경쟁사 분석 | SNS 게시         | SNS 초안       |
             | KPI 집계   | LP 변경          | 카피 작성      |
─────────────┼─────────────┼─────────────────┼───────────────┤
 영업 부서    | 파이프라인  | 제안 발송        | 제안서 작성    |
             | 분석        | 가격 협상        | 경쟁사 조사    |
─────────────┼─────────────┼─────────────────┼───────────────┤
 경리 부서    | 비용 분석  | 세금계산서 발행  | 수지 리포트    |
             | 예산 추적  | 지급 승인        |               |
\`\`\`
```

---

## Key Design Principles

**4 Tiers (not 3):**
- `read-only` — analytical, no side effects
- `execute` — internal actions within threshold
- `auto_after_approval` — template-based, approved once then auto
- `always_draft` — external-facing, always requires human approval

**The `always_draft` list** is the most important guardrail. Any action that affects
external parties (clients, public, production) MUST be in this list.

**Emergency bypass** exists but has strict conditions:
- Only `security_incident` or `service_down` trigger it
- Allowed actions are narrow (hotfix_deploy, service_restart only)
- Post-action reporting is mandatory — bypass ≠ no accountability

**YAML threshold values** like `auto_approve_limit` allow the orchestrator to make
cost-based decisions without hardcoding values in agent files.

**This file is referenced by path** from orchestrator CLAUDE.md and agent files —
never duplicated inline. One source of truth for the entire framework.
