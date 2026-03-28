# Example: State File Structures

State files are the persistent memory of an AI agent system. All state is
referenced by file path from CLAUDE.md — never inlined.

State files use emoji status indicators as standard:
🟢 정상 | 🟡 주의 | 🔴 문제 있음 | ⚪ 미가동

---

## Company-Wide State (.company/STATE.md)

```markdown
# 전사 경영 상태

## 상태: 🟢 정상

## 회사 기본 정보

- 회사명: (여기에 기재)
- 사업 내용: (여기에 기재)
- 대표자: (여기에 기재)

## 사업 포트폴리오

| 서비스명 | 상태 | 비고 |
|---------|------|------|
| (서비스1) | 운영 중 | |

## 전사 KPI

| 지표 | 현재값 | 목표값 | 상태 |
|------|--------|--------|------|
| 월간 매출 | — | — | — |
| AI 운용 비용 | — | — | — |

## 최종 업데이트: YYYY-MM-DD
```

---

## Department State (.company/departments/{dept}/STATE.md)

Each department maintains its own STATE.md. The orchestrator reads these
when generating a system-wide morning digest.

```markdown
# {부서명} — 부서 상태

## 상태: ⚪ 미가동

## 진행 중 태스크

- [ ] {태스크명} — {상태} — 기한: YYYY-MM-DD

## KPI

| 지표 | 현재값 | 목표값 | 상태 |
|------|--------|--------|------|

## 최근 성과물

| 날짜 | 성과물 | 비고 |
|------|--------|------|

## 주의 사항

- (주요 문제점 또는 "없음")

## 최종 업데이트: YYYY-MM-DD
```

Department state files follow this pattern for all departments:
`dev/`, `marketing/`, `sales/`, `finance/`, `cs/`, `legal/`

---

## Approval Queue (.company/approval-queue.md)

All draft-tier actions wait here before execution.

```markdown
# 승인 대기 큐

## 승인 대기 (N건)

### [ID-001] {액션 제목}
- **요청 부서**: {에이전트명}
- **요청일**: YYYY-MM-DD
- **내용**: {구체적인 실행 내용}
- **근거**: {왜 이 액션이 필요한가}
- **승인**: `/cmd:approve ID-001`
- **반려**: `/cmd:reject ID-001 "이유"`

## 최근 승인/반려

| ID | 내용 | 결과 | 날짜 |
|----|------|------|------|
| ID-000 | ... | 승인 | YYYY-MM-DD |
```

The queue starts empty:
```markdown
# 승인 대기 큐

## 승인 대기 (0건)

승인 대기 아이템이 없습니다.

## 최근 승인/반려

(아직 이력이 없습니다)
```

---

## Decision Log (.company/decisions/YYYY-MM.md)

```markdown
# CEO 의사결정 로그 — YYYY년 MM월

## YYYY-MM-DD: {결정 제목}

- **결정**: {무엇을 결정했는가}
- **이유**: {왜 이 결정을 내렸는가}
- **영향 범위**: {어느 부서/서비스에 영향}
- **다음 액션**: {이후 실행 사항}
```

---

## Steering Files (.company/steering/)

Configuration files that rarely change. Agents reference these by path.

### permissions.md — Permission thresholds and rules
### policies.md — Company-wide operating policies
### brand.md — Brand guidelines for content/marketing agents
### tech-stack.md — Technology choices for dev/CTO agents

These are READ by agents, never modified during task execution.
Modifications require human review and explicit update.

---

## State File Lifecycle

```
Agent completes task
    ↓
Agent updates .company/departments/{dept}/STATE.md
    ↓
If external action needed:
    Agent adds item to .company/approval-queue.md
    ↓
    Orchestrator notifies human: "승인 대기 N건"
    ↓
    Human runs /cmd:approve <id>
    ↓
    Agent executes and removes from queue
    ↓
    Agent records decision in .company/decisions/YYYY-MM.md
```
