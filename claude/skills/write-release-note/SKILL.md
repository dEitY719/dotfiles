---
name: write:release-note
description: Use when generating structured release notes from git history between two releases — finding anchor commits, categorizing by conventional-commit prefix, grouping into user-facing themes, and formatting in Korean
allowed-tools: Read, Bash, Grep, Glob, Write, Edit
---

# Release Notes 작성

## 목적

git 히스토리를 분석해 **사용자 관점**의 릴리즈 노트를 생성한다.

**핵심 원칙**: 커밋은 *무엇이* 바뀌었는지 말해주고, 릴리즈 노트는 그것이 *사용자에게 어떤 의미인지* 말해준다.

## 사용 시점

- 새 버전 릴리즈 노트를 만들 때
- 이전 릴리즈 이후 변경사항을 요약할 때
- 마일스톤/태그 릴리즈를 준비할 때

## 워크플로

### 1. 앵커 커밋 찾기

이전 릴리즈의 경계 커밋을 찾는다. 우선순위:

1. **git 태그** (있으면 가장 신뢰할 수 있음)
2. **이전 릴리즈 노트 문서의 커밋** (태그가 없는 프로젝트의 관례)
3. **사용자에게 시작점 확인**

구체적인 git 명령어는 `references/git-commands.md` 참고.

### 2. 커밋 수집 및 분류

`<anchor>..HEAD` 범위의 커밋을 수집하고 conventional commit prefix별로 분류:
`feat`, `fix`, `refactor`, `docs`, `chore`, 그리고 **비관례 커밋**.

⚠️ 비관례 커밋(`grep -vE`)을 반드시 확인 — 놓치기 쉬움.

명령 모음은 `references/git-commands.md` 참고.

### 3. 테마로 그룹핑 (가장 중요)

**커밋을 1:1로 나열하지 말 것.** 관련 커밋을 **사용자 관점 테마**로 묶는다.

- 같은 컴포넌트의 여러 `feat:` → 하나의 테마 섹션
- `feat:` + 관련 `fix:` + `refactor:` → 기능 개발 전체를 묶는 섹션
- 독립 `fix:` → "버그 수정" 섹션
- 독립 `refactor:` → "리팩토링" 섹션

그룹핑 휴리스틱과 **테마 네이밍 규칙**은 `references/grouping-heuristics.md` 참고.

### 4. 릴리즈 노트 작성

프로젝트의 기존 관례를 먼저 확인한다:

```bash
# 이전 릴리즈 노트 파일이 있으면 그 포맷을 따르는 것이 최우선
ls docs/release-notes/ 2>/dev/null || ls CHANGELOG* 2>/dev/null
```

없으면 `references/template.md`의 기본 템플릿을 사용.

### 5. 저장 및 커밋

```bash
git add "<release-notes-path>"
git commit -m "docs: add <version> release notes"
```

## 빠른 레퍼런스

| 단계 | 핵심 |
|------|------|
| 앵커 | 태그 → 이전 릴리즈 노트 커밋 → 사용자 확인 |
| 수집 | `git log --oneline --reverse <anchor>..HEAD` |
| 분류 | conventional prefix별 grep + 비관례 확인 |
| 그룹핑 | 사용자 관점 테마로 묶기 (구현 용어 금지) |
| 작성 | 프로젝트 관례 먼저, 없으면 템플릿 |

## 흔한 실수

| 실수 | 수정 |
|------|------|
| 커밋 1:1 나열 | 관련 커밋을 테마로 그룹화 |
| 구현 용어로 섹션 제목 | 사용자 기능명으로 교체 |
| 비관례 커밋 누락 | `grep -vE` 반드시 확인 |
| 기능 관련 버그를 "버그 수정"에 배치 | 해당 기능 테마 섹션으로 이동 |
| 개요를 커밋 나열로 작성 | 릴리즈 성격을 1-2문장 요약으로 |

## 참고 파일

- `references/git-commands.md` — 앵커 찾기, 커밋 수집, prefix별 필터 명령어
- `references/grouping-heuristics.md` — 테마 그룹핑 규칙과 네이밍 가이드
- `references/template.md` — 마크다운 템플릿과 작성 팁
