# Discussion Body Templates

Default category is `Ideas` — use the RFC skeleton. Other categories
have their own variants in the second half of this file.

## Title format

| Category | Format | Example |
|---|---|---|
| `Ideas` | `<type>[(<scope>)]: <한 줄 요약>` | `feat(gh-discussion-create): 대화 -> Ideas RFC Discussion` |
| `Q&A` | `<질문 한 줄>` (no prefix) | `왜 gh:discussion-create 는 카테고리 ID 를 캐시하지 않는가?` |
| `Announcements` | `announce: <한 줄 요약>` | `announce: discussions-policy 도입 (#612)` |
| `Lessons` | `lesson: <한 줄 요약>` | `lesson: GraphQL createDiscussion 권한 요구사항` |

## Ideas — RFC body skeleton (default)

Mirrors `gh-issue-create/references/templates/feat.md` but moves
**Open Questions** to a more prominent slot and drops Acceptance
Criteria (RFC has not committed to the work yet).

```markdown
## TL;DR
<1~3 lines — what is being explored and why now>

## 배경 (Why / Context)
<motivation, current pain, link to triggering chats / SSOT>

## Goals / Non-Goals
### Goals
-
### Non-Goals
-

## 옵션 / Trade-offs
<핵심 의사결정 후보들. 각 옵션마다 pro/con 명시.>
- 옵션 A: ...
  - pro: ...
  - con: ...
- 옵션 B: ...

## 대안 (Alternatives Considered)
| 대안 | 거절 사유 (현재 시점) |
|---|---|
|  |  |

## Open Questions
<RFC 의 핵심. 답이 정해지면 Discussion -> Issue convert.>
-

## 영향 범위 (Impact, 예상)
<수정 대상 파일·인접 시스템·마이그레이션 가능성. RFC 단계라 추정 OK.>

## Dependencies
- 선행: <issue 또는 다른 Discussion>
- 동격: <관련 RFC 들>

## References
- 관련 파일·이슈·PR·외부 문서
- SSOT: docs/.ssot/discussions-policy.md (#612)
```

## Category variants

### Q&A — body skeleton

```markdown
## 질문
<재진술 — 제목보다 1~2 줄 더 풀어서.>

## Context
<왜 이 질문이 나왔나, 어떤 코드/결정이 트리거인가.>

## 현재까지 알고 있는 것
- <부분 답·관련 코드 링크·이미 시도한 검색>

## 후속 (Optional)
<답이 나오면 어디로 정리할지 — docs/learnings, SSOT 갱신, follow-up issue 등.>
```

### Announcements — body skeleton

```markdown
## 요약
<1~2 줄 — 무엇이 바뀌었나.>

## 배경
<왜 변경했나. 근거 issue/PR 링크.>

## 효력 발생
- 적용 시점: <YYYY-MM-DD 또는 PR merge 시점>
- 영향 범위: <어떤 워크플로우·스킬·문서가 바뀌나>

## Action Items
- [ ] <필요한 후속 작업이 있다면 체크리스트로>

## References
- 근거: #<N>
- 관련 SSOT: <경로>
```

### Lessons — body skeleton

`docs/.ssot/discussions-policy.md` -> "Lessons 카테고리 운영" 에 따르면
Lessons 는 Discussion-first 다. 짧은 단편 노트는 파일 없이 Discussion
만 유지한다 — 본문 상단에 출처를 둔다.

```markdown
## 출처
- <영상 URL / 문서 링크 / 강연 메모 — 1~2 줄>

## 핵심 요약
<3~5 줄. "결국 이거 한 줄" 이 무엇인가.>

## 재사용 포인트
- <언제 다시 꺼낼만한가 — 패턴, 체크리스트, cheat sheet 항목>
- <언제 안 꺼내도 되는가>

## 본문 / 노트
<자유 형식. 코드 스니펫·인용·자기 메모 모두 OK.>

## 후속 (Optional)
<docs/guide/learnings/ 로 승격할 임계치에 도달했나? — 본문/댓글 ≥ 300 줄,
3 회 이상 외부 참조, 또는 cheat sheet 형태로 재방문 빈도 高.>
```

## Detail-preservation contract

본문 골격은 **틀**일 뿐이다. 실제 본문은 대화 detail 을 잃지 않도록
풀어쓴다 — 200 줄 RFC 도 정상이다. `gh:issue-create` 와 동일한 정책.
