# Skill Design: write-task-history

## 1. 개요

현재 대화에서 수행한 작업 내용을 정리하여, JIRA 티켓 등록용과 git PR용 두 가지 형태로
일별 task history 파일에 append하는 스킬.

- **스킬 이름**: `write-task-history`
- **호출**: `/write-task-history [설명]`
- **적용 범위**: 모든 프로젝트 (dotfiles, rca-knowledge 등)
- **저장 위치**: `$TASK_HISTORY_DIR/YYYY-MM-DD-task-list.md` (Single Source)
- **기본 경로**: `~/para/archive/playbook/docs/task-history/`
- **환경변수**: `TASK_HISTORY_DIR`로 오버라이드 가능

## 2. 요구사항

### 핵심 요구사항

| ID | 요구사항 | 비고 |
|---|---|---|
| R1 | 현재 대화 내용을 분석하여 작업 내역 추출 | 대화 컨텍스트 기반 |
| R2 | JIRA 티켓 형태 출력 (text, 기호 활용) | JIRA가 마크다운 미지원이므로 |
| R3 | git PR 형태 출력 (마크다운) | 대화 중 커밋이 있는 경우만 |
| R4 | 일별 파일에 append (덮어쓰기 아님) | 하루에 여러 번 호출 가능 |
| R5 | 모든 프로젝트에서 사용 가능 | 프로젝트 비종속적 |
| R6 | 커밋 없으면 PR 섹션 생략 | 선택적 출력 |
| R7 | JIRA/PR 각각 코드블럭으로 감싸서 출력 | 복사/붙여넣기 용이하도록 |

### 출력 파일 규칙

- **경로**: `$TASK_HISTORY_DIR/YYYY-MM-DD-task-list.md`
- **기본값**: `TASK_HISTORY_DIR=~/para/archive/playbook/docs/task-history`
- **파일명 예시**: `2026-03-20-task-list.md`
- **동작**: 파일이 없으면 생성, 있으면 append (`---` 구분선 포함)
- **타임스탬프**: 각 항목에 HH:MM 표시
- **인코딩**: UTF-8

## 3. 데이터 소스

| 소스 | 용도 | 필수 여부 |
|---|---|---|
| 현재 대화 컨텍스트 | 작업 내역 추출 | 필수 |
| `git log` (현재 대화에서 생성된 커밋) | 커밋 목록, PR 내용 | 선택 |
| `git diff main...HEAD` | 변경 사항 요약 | 선택 (브랜치 있을 때) |
| `git remote -v` | 프로젝트명 추출 | 선택 |
| 사용자 인자 (`[설명]`) | 추가 컨텍스트 | 선택 |

## 4. 출력 형식

### 4-A. JIRA 티켓 형태

JIRA가 마크다운을 지원하지 않으므로, 기호를 활용한 텍스트로 작성.
가독성을 위해 섹션 구분에 >, 하위 항목에 - 기호 사용.

```text
[Title]
[프로젝트명] 작업 제목 요약

[Description]
> 배경
- 작업 배경 또는 원인 설명
- 추가 배경 설명

> 수행 내용
- 수행한 작업 1
- 수행한 작업 2
- 수행한 작업 3

> 결과
- 결과 요약 1
- 결과 요약 2

> 비고
- 참고 사항 (있을 경우)
```

### 4-B. git PR 형태

현재 대화에서 커밋이 있는 경우에만 작성. GitHub PR 마크다운 형식.

```markdown
## Title
작업 제목 요약 (70자 이내)

## Summary
- 변경 사항 요약 1
- 변경 사항 요약 2

## Changes
- `파일1`: 변경 내용
- `파일2`: 변경 내용

## Test plan
- [ ] 테스트 항목 1
- [ ] 테스트 항목 2
```

### 4-C. 파일 전체 구조

하루에 여러 번 호출 시 append되는 형태.
JIRA/PR 내용은 각각 코드블럭으로 감싸서
사용자가 바로 복사/붙여넣기할 수 있도록 한다.

```markdown
# Task History: 2026-03-20

---

## 13:30 | dotfiles | rm -rf ~ 복구 작업

### JIRA Ticket

\`\`\`text
[Title]
...

[Description]
> 배경
- ...
\`\`\`

### PR

\`\`\`markdown
## Title
...

## Summary
...
\`\`\`

---

## 15:00 | rca-knowledge | 분석 보고서 작성

### JIRA Ticket

\`\`\`text
...
\`\`\`

(현재 대화에서 커밋 없으므로 PR 섹션 생략)
```

## 5. 처리 흐름

```text
/write-task-history [설명]
        |
        v
[Step 1] 저장 경로 결정
         $TASK_HISTORY_DIR/YYYY-MM-DD-task-list.md
         (미설정 시 ~/para/archive/playbook/docs/task-history/)
        |
        v
[Step 2] 현재 대화 컨텍스트에서 작업 내역 분석
         - 무엇을 했는지 (작업 목록)
         - 왜 했는지 (배경/원인)
         - 결과가 무엇인지
        |
        v
[Step 3] git 정보 수집 (선택)
         - 현재 대화에서 생성된 커밋 파악
         - git remote: 프로젝트명
         - git diff main...HEAD: 변경 범위
        |
        v
[Step 4] JIRA 티켓 형태 생성
         - Title + Description (기호 활용 text)
        |
        v
[Step 5] 현재 대화에서 커밋이 있는가?
         ├─ YES → PR 형태 생성
         └─ NO  → PR 섹션 생략
        |
        v
[Step 6] 파일에 append
         - 파일 없으면: 헤더 + 내용 생성
         - 파일 있으면: 구분선(---) + 내용 append
        |
        v
[Step 7] 사용자에게 결과 요약 출력
```

## 6. 스킬 파일 구조

```text
claude/skills/write-task-history/
  SKILL.md          # 스킬 정의 (호출 조건, 설명)
  instructions.md   # 상세 구현 지침
```

### SKILL.md (초안)

```markdown
---
name: write-task-history
description: >
  Write task history from current conversation to daily task list file.
  Generates JIRA ticket (text) and git PR (markdown) formats.
  Use when user wants to document completed work for internal tracking.
triggers:
  - /write-task-history
---

# write-task-history

현재 대화의 작업 내용을 정리하여 일별 task history 파일에 기록합니다.

## 호출

/write-task-history [작업 설명]

## 출력

1. JIRA 티켓 형태 (text + 기호)
2. git PR 형태 (마크다운) — 현재 대화에서 커밋이 있는 경우만

## 저장 위치

$TASK_HISTORY_DIR/YYYY-MM-DD-task-list.md
기본값: ~/para/archive/playbook/docs/task-history/
```

## 7. 설계 결정 사항 (리뷰 확정)

### 결정 1: 파일명 형식 YYYY-MM-DD

- `2026-03-20-task-list.md`
- 이유: 검색 편의성, ISO 8601 표준 준수

### 결정 2: 저장 경로 외부화

- 환경변수 `TASK_HISTORY_DIR`로 오버라이드 가능
- 기본값: `~/para/archive/playbook/docs/task-history/`
- 이유: 다른 머신/사용자 계정에서도 동작 보장 (Finding #3 반영)

### 결정 3: JIRA 형태는 기호 텍스트

- `>`: 섹션 구분 (배경, 수행 내용, 결과, 비고)
- `-`: 하위 항목
- 마크다운 렌더링이 안 되는 JIRA에서도 시각적 구분 가능

### 결정 4: PR 섹션은 plain 마크다운

- 저장소 규칙에 따라 이모지를 사용하지 않음 (Finding #1 반영)
- Summary, Changes, Test plan 등 섹션명만 사용

### 결정 5: append 구분선 `---`

- 마크다운 표준 수평선
- 하루에 여러 프로젝트/작업을 기록할 때 시각적 분리

### 결정 6: 타임스탬프 HH:MM 표시

- 각 항목 헤더에 `## HH:MM | 프로젝트명 | 작업 제목` 형식
- 작업 시간대를 기록하여 추후 참조 용이

### 결정 7: PR 생성 기준은 대화 컨텍스트

- ~~기존안: `git log --since="today"`~~: 날짜 기반은 오탐/누락 발생 (Finding #2 반영)
- 확정: 현재 대화에서 실제로 수행한 커밋 유무로 판정
- 대화 컨텍스트에서 커밋 해시, 브랜치, PR 생성 여부를 파악
- 커밋 없는 작업(리서치, 문서 작성 등)에는 PR 생략

### 결정 8: 프로젝트 비종속

- `git remote -v`에서 프로젝트명 추출하여 자동 표시
- 어떤 프로젝트 디렉터리에서든 호출 가능

### 결정 9: 코드블럭 래핑

- JIRA: `` ```text `` 블럭으로 감쌈
- PR: `` ```markdown `` 블럭으로 감쌈
- 이유: 사용자가 그대로 복사/붙여넣기 가능

## 8. 엣지 케이스

| 케이스 | 처리 |
|---|---|
| task-history 디렉터리 미존재 | 자동 생성 (`mkdir -p`) |
| TASK_HISTORY_DIR 미설정 | 기본 경로 사용 |
| 같은 날 여러 번 호출 | `---` 구분선 후 append |
| 현재 대화에서 커밋 없음 | PR 섹션 생략, JIRA만 작성 |
| git repo 아닌 디렉터리에서 호출 | 프로젝트명 "N/A", PR 생략 |
| 사용자 설명 미제공 | 대화 컨텍스트에서 자동 추출 |
