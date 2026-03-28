---
name: claude-md-create
description: >-
  Create a CLAUDE.md orchestrator file for an AI agent framework from scratch.
  Use when building a new AI agent orchestration system — multi-agent pipelines,
  domain-specific orchestrators, automated workflow systems — and you need a
  well-structured CLAUDE.md to define roles, commands, permissions, and
  delegation patterns. Triggers on: "create CLAUDE.md", "set up my AI agent
  framework", "initialize my orchestrator", "build an AI agent system",
  "/claude-md-create". Distinct from claude-md-check (audit only).
compatibility:
  tools: Read, Glob, Grep, Write, Bash
---

# CLAUDE.md Orchestrator Creator

## Workflow

### Phase 0: Discover (always run first)

Ask the user:
1. **도메인** — 어떤 종류의 AI Agent 프레임워크인가? (예: 비즈니스 운영, DevOps, 콘텐츠, 고객 지원)
2. **에이전트 목록** — 어떤 역할의 에이전트가 필요한가? (부서/도메인별로)
3. **커맨드** — 관리자가 실행할 주요 커맨드는 무엇인가?
4. **외부 액션 범위** — 어떤 액션이 외부에 영향을 주는가? (이메일, 배포, SNS 등)

프레임워크 규모 분류:
- **Simple**: 에이전트 1~2개, 단일 도메인 → `references/simple-framework.md`
- **Standard**: 에이전트 3~6개, 복수 도메인 → `references/standard-framework.md`
- **Large**: 에이전트 7개 이상, 엔터프라이즈 → `references/large-framework.md`

### Phase 1: Select Template

Read the appropriate template from `references/`.

### Phase 2: Fill Template

Replace all `{placeholder}` values with domain-specific content from Phase 0:
- 프레임워크 이름과 역할 정의
- 에이전트 목록과 STATE.md 경로 (`.company/departments/{name}/STATE.md` 패턴)
- 커맨드 목록 (도메인별 그룹화)
- 권한 분류 (외부 액션 → `always_draft`, 내부 액션 → `execute`)
- 서브에이전트 위임 방법 (5가지 파라미터 포함)

### Phase 3: Validate Before Writing

Mental checklist (fix before writing if any fail):
- [ ] 역할 정의 섹션 존재 (당신의 역할 + Thin Orchestrator 원칙)
- [ ] 모든 상태 정보는 파일 경로로만 참조 (인라인 데이터 없음)
- [ ] 커맨드 목록이 도메인별로 그룹화됨
- [ ] 권한 제어 3계층 정의 (read-only / execute / draft)
- [ ] 기본 규칙 섹션 존재 (Git 커밋, 에러 처리, 에스컬레이션)

Run mentally against all 6 claude-md-check criteria before writing.

### Phase 4: Write Files

Write `CLAUDE.md` at the location specified (default: current directory).
Report what was created and suggest next steps.

## Output Report

```
## CLAUDE.md Created

File: <path>
Lines: <N>
Agents: <count> (listed)
Commands: <count> (listed)

Validation: <pass count>/5 pre-checks passed
Next: Run /claude-md-check to audit the result
      Create agent files: /agents-md-create in each .claude/agents/ file
```
