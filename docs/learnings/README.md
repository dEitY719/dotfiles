# Learnings

## 개요

이 디렉토리는 **작업 중 얻은 재사용 가능한 패턴·스니펫**을 짧은 글 단위로
축적하는 지식 저장소입니다. 각 문서는 실제 PR·커밋·리뷰 경험에서 파생되며,
다른 작업에 그대로 복사해 적용할 수 있는 수준으로 정리합니다.

## 이웃 디렉토리와의 관계

| 디렉토리 | 성격 | 분량 기준 | 예시 |
|---|---|---|---|
| `docs/technic/` | 검증된 스택 중심 기술 문서 | 수백 줄 | `parallel-testing-with-xdist.md` |
| `docs/standards/` | 프로젝트 SSOT·의사결정 기록 | 중간 | `command-guidelines.md` |
| `docs/feature/<name>/` | 피처별 설계·분석 번들 | 다수 파일 | `skill-ai-worktree-teardown/` |
| **`docs/learnings/` (여기)** | **작업 중 얻은 재사용 패턴 스니펫** | **50–80줄 목표** | 아래 참조 |

`memory/`(Claude 비공개 작업 메모리)와는 다음 규칙으로 역할 분담:

- **`docs/learnings/`**: 공개·버전 관리되는 지식 — 개발자 동료도 읽는 곳
- **`memory/`**: Claude 세션 간 컨텍스트 — 사용자·AI 협업 선호도·피드백 중심
- 같은 내용을 양쪽에 중복 작성하지 않고, `memory/` 엔트리는 이 폴더의
  파일을 **포인터로 참조**

## 작성 규칙

### 파일 구조 템플릿

각 learning 문서는 다음 5개 섹션을 권장합니다.

```markdown
# <제목>

## Context

이 패턴이 어디서 나왔는지 — PR·이슈·커밋 링크 포함

## Pattern

핵심 원리를 1–3문장으로 요약

## Code

복붙 가능한 최소 예시 (언어 태그 포함)

## When to use

적용 조건 / 반대 조건

## Related

연결된 문서·코드 파일 경로, 참조 커밋·PR
```

### 참조 링크 지침

각 learning 은 **출처 추적 가능성**이 생명입니다. 다음을 가능한 범위에서 기록:

- **PR 번호**: `PR #130` — 가장 안정적인 참조 (병합 후에도 유지)
- **커밋 해시**: `de96848` — 특정 코드 예시를 가리킬 때
- **이슈 번호**: `#N` — 관련 discussion·bug 가 있을 경우
- **리뷰 코멘트 URL**: 봇·사람 리뷰에서 얻은 insight 일 때

불가능한 경우(로컬 실험·대화 중 발견 등)는 **생략**하되, 대신 Context 섹션에
"어떤 상황에서 발견했는지"를 구체적으로 기록합니다.

### 언어 정책

- **동료 개발자용 문서**: 한국어 (이 폴더의 기본)
- **AI 지침서 성격**(SKILL.md, system prompt 등): 영어

## 현재 문서 목록

### 1. UX 색 계층으로 "읽는 순서" 만들기

**파일**: [`ux-color-hierarchy.md`](./ux-color-hierarchy.md)

멀티라인 에러·가이드 메시지에서 **빨강 → 노랑 → 시안 → 파랑** 색 계층으로
사용자의 시선을 "문제 → 원칙 → 대안" 순서로 유도하는 설계 패턴.

### 2. Git worktree 컨텍스트 감지

**파일**: [`git-worktree-detection.md`](./git-worktree-detection.md)

`git rev-parse --git-dir` 와 `--git-common-dir` 비교로 현재 pwd 가 main
repo 인지 worktree 인지 감지하는 최소 코드 패턴. `||` early-exit 로
non-repo 케이스도 함께 처리.

### 3. GitHub PR 리뷰 답글 API 엔드포인트 분기

**파일**: [`github-pr-review-reply-api.md`](./github-pr-review-reply-api.md)

inline diff 코멘트는 `/pulls/{n}/comments/{id}/replies` (스레드 유지),
리뷰 요약·이슈 코멘트는 `/issues/{n}/comments` (top-level) 로 POST 해야
하는 이유와 선택 기준.

## 성장 전략

- 3–10개: 플랫 구조 유지 (현재)
- 10개 초과: `shell/`, `workflows/`, `ux/` 등 주제별 서브디렉토리로 분리
- 30개 초과 또는 한 문서가 150줄 초과: `technic/` 승격 검토
