# REQ-Based Agent to SKILL Migration Proposal

**Date**: 2026-01-01
**Author**: Claude Code
**Status**: Review Draft

---

## Executive Summary

현재 6개의 REQ-based development agent를 claude/skills/로 마이그레이션하여 토큰 사용량을 줄이고 유지보수성을 향상시키는 방안을 제안합니다.

**현재 상태:**
- 6개 agent 파일 총 ~3,800줄
- 중복 코드 약 40% (Configuration Loading, Input/Output Format 등)
- 매번 sub-agent 호출 시 전체 context 로드

**제안 후 예상:**
- 3개 SKILL 파일 총 ~1,200줄 (68% 감소)
- 중복 코드 제거로 토큰 효율성 향상
- 필요한 phase만 로드하여 context window 최적화

---

## Current Architecture Analysis

### Agent Files Overview

| Agent | Lines | Model | Primary Function |
|-------|-------|-------|------------------|
| feature-agent | 473 | haiku | Phase 0: REQ 정의 |
| req-orchestrator-agent | 514 | sonnet | Phase 1-4 조율 |
| req-spec-agent | 292 | haiku | Phase 1: Specification |
| req-test-design-agent | 403 | haiku | Phase 2: Test Design |
| req-implementation-agent | 526 | haiku | Phase 3: Implementation |
| req-summary-agent | 942 | haiku | Phase 4: Documentation |
| **Total** | **~3,150** | - | - |

### Identified Redundancies

1. **Configuration Loading Block** (~30 lines x 6 = 180 lines)
   - 모든 agent에 동일한 `.claude/agent-config.yaml` 로딩 코드 존재

2. **Input/Output Format Sections** (~50 lines x 6 = 300 lines)
   - YAML 형식의 입출력 정의가 반복됨

3. **Quality Checklist** (~20 lines x 6 = 120 lines)
   - 각 agent별 체크리스트가 유사한 패턴

4. **Error Handling** (~40 lines x 5 = 200 lines)
   - 에러 처리 패턴이 대부분 동일

**총 중복: ~800줄 (25%)**

---

## Proposed SKILL Architecture

### Option A: Monolithic SKILL (NOT Recommended)

```
claude/skills/req-workflow/SKILL.md (single file ~2,000+ lines)
```

**단점:**
- 500줄 제한 위반
- 모든 phase가 항상 로드됨
- 유지보수 어려움

### Option B: Phase-Separated SKILLs (NOT Recommended)

```
claude/skills/req-define/SKILL.md
claude/skills/req-spec/SKILL.md
claude/skills/req-test/SKILL.md
claude/skills/req-impl/SKILL.md
claude/skills/req-summary/SKILL.md
```

**단점:**
- Agent 구조와 동일 (개선 효과 미미)
- 사용자가 개별 phase를 직접 호출해야 함
- Orchestration 로직 부재

### Option C: Hybrid Architecture (RECOMMENDED)

```
claude/skills/
  req-workflow/           # Main orchestrator skill
    SKILL.md              # ~400 lines - Phase 조율 및 user interaction
    README.md             # Usage documentation
  req-phases/             # Internal phase protocols (NOT user-invocable)
    _common.md            # ~150 lines - 공통 설정, 템플릿
    phase1-spec.md        # ~200 lines - Specification protocol
    phase2-test.md        # ~200 lines - Test design protocol
    phase3-impl.md        # ~250 lines - Implementation protocol
    phase4-summary.md     # ~200 lines - Documentation protocol
  req-define/             # Standalone feature definition skill
    SKILL.md              # ~300 lines - REQ 정의 (Phase 0)
    README.md
```

**장점:**
- 500줄 제한 준수
- 공통 로직 _common.md로 추출
- 필요한 phase만 참조 가능
- User-invocable은 2개만 (req-workflow, req-define)
- 내부 protocol은 필요시에만 include

---

## Detailed SKILL Design

### 1. req-workflow/SKILL.md (Main Orchestrator)

```yaml
---
name: req-workflow
description: REQ-based 4-phase development workflow. Use when implementing features with "REQ-X-Y 개발해" format. Orchestrates Spec, Test, Implementation, Summary phases with user approval gates.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task
---
```

**Structure:**

```markdown
# REQ Development Workflow

## Role
REQ-based development workflow orchestrator. Parse REQ ID, execute 4 phases, manage user approvals.

## Trigger Scenarios
- "REQ-F-A1-1 개발해"
- "implement REQ-AUTH-1"
- "REQ-B-Access-1 구현해줘"

## Configuration
[Include from _common.md]

## Workflow Protocol

### Phase 0: Request Parsing
- Extract REQ ID from user input
- Validate REQ exists in requirement file
- Determine project type (F/B/A/CLI)

### Phase 1: Specification (PAUSE for approval)
[Reference: phase1-spec.md]
- Present spec summary
- Ask: "Specification approved? (YES/NO)"

### Phase 2: Test Design (PAUSE for approval)
[Reference: phase2-test.md]
- Present test case list
- Ask: "Test plan approved? (YES/NO)"

### Phase 3: Implementation (Auto-proceed on success)
[Reference: phase3-impl.md]
- Run tests + lint
- Stop on failure, report errors

### Phase 4: Summary (Auto-complete)
[Reference: phase4-summary.md]
- Create progress file
- Update DEV-PROGRESS.md
- Git commit

## Progress Indicator
[Visual progress bar template]

## Error Handling
[Common error patterns from _common.md]
```

**Estimated Lines: ~400**

---

### 2. req-define/SKILL.md (Feature Definition)

```yaml
---
name: req-define
description: Convert free-form requirements into structured REQ format. Use when defining new features or documenting urgent requests.
allowed-tools: Read, Glob, Grep, Write, Edit
---
```

**Structure:**

```markdown
# REQ Feature Definition

## Role
Parse natural language requirements and generate structured REQ documents.

## Trigger Scenarios
- "새로운 기능 정의해줘: [description]"
- "REQ 문서 만들어줘"
- "feature requirement 작성해"

## Classification Rules
- REQ-F-*: Frontend (UI, components, pages)
- REQ-B-*: Backend (APIs, services, databases)
- REQ-A-*: Agent (LLM, AI features)
- REQ-CLI-*: CLI (commands, tools)

## REQ-ID Generation
[Duplicate check algorithm]

## Output Template
[Markdown template for feature_requirement_mvp1.md]

## Quality Checklist
[Validation criteria]
```

**Estimated Lines: ~300**

---

### 3. req-phases/_common.md (Shared Protocol)

```markdown
# Common REQ Workflow Configuration

## Configuration Loading
```yaml
# Single source of truth for all phases
config_file: .claude/agent-config.yaml

defaults:
  requirement_file: docs/feature_requirement_mvp1.md
  progress_directory: docs/progress/
  progress_tracking: docs/DEV-PROGRESS.md
  test_command: ./tools/dev.sh test
  format_command: ./tools/dev.sh format
  max_retries: 3
```

## Project Type Detection
```
REQ-F-*  → Frontend (React/TypeScript)
REQ-B-*  → Backend (Python/FastAPI)
REQ-A-*  → Agent (Python/LangChain)
REQ-CLI-* → CLI (Python)
```

## Status Indicators
```
⏳ Backlog → 🔄 In Progress → ✅ Done
Phase: 0 → 1 → 2 → 3 → 4
```

## Git Commit Format
```
chore: Update progress for REQ-X-Y completion

[Phase summary]

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

## Error Response Format
```yaml
status: "SUCCESS" | "FAILURE" | "PENDING_APPROVAL"
phase: 1-4
details: [specific information]
action_required: [next steps if any]
```
```

**Estimated Lines: ~150**

---

### 4. Phase-Specific Protocols (Internal, Not User-Invocable)

#### phase1-spec.md (~200 lines)

```markdown
# Phase 1: Specification Protocol

## Input
- req_id: string
- requirement_file: path

## Steps
1. Locate REQ in file (grep pattern)
2. Extract: Description, Priority, Use Cases, Expected Output, Error Cases
3. Define: Intent, Location, Signature, Behavior, Dependencies, Acceptance Criteria

## Output Format
[Structured spec markdown template]

## Validation
- [ ] REQ ID found
- [ ] All sections populated
- [ ] Intent is single sentence
- [ ] Location has file paths
```

#### phase2-test.md (~200 lines)

```markdown
# Phase 2: Test Design Protocol

## Input
- req_id: string
- specification: from Phase 1

## Test Case Pattern
TC-1: Happy Path (component exists)
TC-2: Main Happy Path (core requirement)
TC-3: User Interaction (click, input)
TC-4: Acceptance Criteria (all met)
TC-5: Edge Cases (error handling)

## Test File Location
Frontend: src/frontend/src/**/__tests__/*.test.tsx
Backend: tests/backend/test_*.py
CLI: tests/cli/test_*.py

## Output
- Test design document
- Test file skeleton with REQ ID in docstrings
```

#### phase3-impl.md (~250 lines)

```markdown
# Phase 3: Implementation Protocol

## Input
- req_id: string
- specification: from Phase 1
- test_design: from Phase 2
- test_file_path: from Phase 2

## Execution Flow
1. Read test file, understand assertions
2. Write minimal code to pass tests
3. Run: test_command (max 3 retries)
4. Run: format_command
5. Report results

## Retry Logic
retry_count < 3 → Fix and retry
retry_count >= 3 → STOP, report failure

## Success Criteria
- All tests pass
- No lint issues
- Code quality clean
```

#### phase4-summary.md (~200 lines)

```markdown
# Phase 4: Summary Protocol

## Input
- All previous phase outputs

## Steps
1. Create docs/progress/REQ-X-Y.md
2. Update docs/DEV-PROGRESS.md (Phase: 0→4, Status: ⏳→✅)
3. Git commit with standard format

## Progress File Template
[Full template with all sections]

## Git Operations
- Stage: progress file + DEV-PROGRESS.md
- Commit: formatted message with 🤖 marker
- (Optional) Conflict check if enabled
```

---

## Migration Plan

### Phase 1: Preparation (Day 1)

1. Create directory structure:
   ```bash
   mkdir -p claude/skills/req-workflow
   mkdir -p claude/skills/req-define
   mkdir -p claude/skills/req-phases
   ```

2. Extract _common.md from existing agents

3. Create README.md files for user-facing skills

### Phase 2: SKILL Creation (Day 2-3)

1. Write req-workflow/SKILL.md (orchestrator)
2. Write req-define/SKILL.md (feature definition)
3. Write phase1-4 protocol files
4. Test individual components

### Phase 3: Integration Testing (Day 4)

1. Test complete workflow with sample REQ
2. Verify approval gates work correctly
3. Check progress file generation
4. Validate git commit format

### Phase 4: Deprecation (Day 5)

1. Update CLAUDE.md to reference new skills
2. Mark old agents as deprecated
3. (Optional) Keep agents as fallback for 1 week
4. Remove deprecated agents after validation period

---

## Token Usage Comparison

### Current Agent Architecture

```
Orchestrator call:
  - Load req-orchestrator-agent.md: ~514 lines
  - Task tool overhead: ~100 tokens

Phase 1 sub-agent call:
  - Load req-spec-agent.md: ~292 lines
  - Context passing: ~200 tokens

Phase 2 sub-agent call:
  - Load req-test-design-agent.md: ~403 lines
  - Context passing: ~400 tokens (spec included)

Phase 3 sub-agent call:
  - Load req-implementation-agent.md: ~526 lines
  - Context passing: ~600 tokens (spec + test)

Phase 4 sub-agent call:
  - Load req-summary-agent.md: ~942 lines
  - Context passing: ~800 tokens (all previous)

Total context loaded: ~3,150 + ~2,100 = ~5,250 effective lines
```

### Proposed SKILL Architecture

```
Single skill invocation:
  - Load req-workflow/SKILL.md: ~400 lines
  - Reference _common.md: ~150 lines
  - Reference phase protocols as needed: ~200 lines each

Typical full workflow:
  - SKILL.md: 400
  - _common.md: 150
  - phase1-spec.md: 200
  - phase2-test.md: 200
  - phase3-impl.md: 250
  - phase4-summary.md: 200

Total context: ~1,400 lines (73% reduction)
```

### Estimated Token Savings

| Metric | Current | Proposed | Savings |
|--------|---------|----------|---------|
| Lines loaded | ~5,250 | ~1,400 | 73% |
| Sub-agent calls | 4 | 0 | 100% |
| Context overhead | ~2,100 | ~0 | 100% |
| Approximate tokens | ~15,000 | ~4,500 | 70% |

---

## Risk Assessment

### Low Risk

- **Structure change**: New skills can coexist with old agents during transition
- **Backward compatibility**: Users can still use "REQ-X-Y 개발해" format

### Medium Risk

- **Behavior differences**: SKILL may behave slightly differently than agents
- **Mitigation**: Extensive testing before deprecating agents

### High Risk

- **None identified**: This is primarily a refactoring exercise

---

## Acceptance Criteria

Migration is complete when:

- [ ] All 3 main SKILL files created and under 500 lines each
- [ ] _common.md and phase protocols created
- [ ] Full workflow tested with real REQ
- [ ] Token usage reduced by at least 50%
- [ ] User approval gates function correctly
- [ ] Progress file generation works
- [ ] Git commits have correct format
- [ ] Documentation updated

---

## Decision Required

**Options:**

1. **Approve and proceed** with Option C (Hybrid Architecture)
2. **Request modifications** to the proposed structure
3. **Reject** and continue with current agent architecture
4. **Defer** decision pending additional analysis

---

## Appendix: File Structure After Migration

```
claude/
├── skills/
│   ├── req-workflow/
│   │   ├── SKILL.md          # Main orchestrator (~400 lines)
│   │   └── README.md         # Usage documentation
│   ├── req-define/
│   │   ├── SKILL.md          # Feature definition (~300 lines)
│   │   └── README.md
│   └── req-phases/           # Internal protocols (not user-invocable)
│       ├── _common.md        # Shared configuration (~150 lines)
│       ├── phase1-spec.md    # Specification (~200 lines)
│       ├── phase2-test.md    # Test design (~200 lines)
│       ├── phase3-impl.md    # Implementation (~250 lines)
│       └── phase4-summary.md # Summary (~200 lines)
├── [DEPRECATED] feature-agent.md
├── [DEPRECATED] req-orchestrator-agent.md
├── [DEPRECATED] req-spec-agent.md
├── [DEPRECATED] req-test-design-agent.md
├── [DEPRECATED] req-implementation-agent.md
└── [DEPRECATED] req-summary-agent.md
```

---

**Document End**
