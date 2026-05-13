# GitHub Discussions 운영 정책

## 목표

`dEitY719/dotfiles` 레포에서 **Issue 와 별도로 GitHub Discussions 를
보조 SSOT** 로 운영한다. Issue 가 "to-do 의 SSOT" 라면 Discussion 은
"forum 의 SSOT" — lifecycle 이 다른 항목을 한 트래커에 섞지 않는다.
본 문서는 Discussion 의 카테고리·라우팅·변환·운영 원칙의 SSOT 다.

근거 이슈: #612.

## 적용 범위

- 저장소: `dEitY719/dotfiles` (단일 repo)
- 카테고리: 4종 (`Announcements`, `Ideas`, `Q&A`, `Lessons`)
- 변환: GitHub UI 의 양방향 `Convert to issue` / `Convert to discussion`
- 관련 정책: [`github-project-board.md`](./github-project-board.md) —
  Discussion 은 칸반 보드에 포함하지 않는다.

## 도입 배경

Issue 중심 워크플로우의 강점은 SSOT 단일성이지만 다음 그늘이 누적된다:

1. **탐색/RFC 도 issue 가 된다** — "할까말까" 단계의 아이디어가 issue
   로 등록되면 결정 안 난 채 close 되거나 보드를 오염시킨다.
2. **학습·회고가 issue tracker 외부에 격리** — 외부 학습 (YouTube
   /문서) 정리나 PR 회고는 `docs/learnings/` 파일로만 가는데, 파일은
   검색은 되지만 댓글·threaded 토론·반응이 불가능하고 작성 마찰이
   커서 모바일·짧은 노트에 부적합하다.
3. **자기참조 Q&A** — 6 개월 뒤 "왜 X 를 Y 방식으로 했지?" 를 찾을 때
   commit 메시지는 휘발성이고 closed issue 본문은 detail 검색이 어렵다.
4. **공지(announcement)** — `#317 ai-metrics`, `#575 skills/docs symlink`
   같은 SSOT 결정사항이 issue 본문에 묻혀 우연 발견된다.

Discussion 은 정확히 이 4 개 영역을 채우도록 설계된 forum 메커니즘이다.

## 카테고리 매트릭스

| 카테고리 | GitHub Format | 용도 | issue 전환 트리거 |
|---|---|---|---|
| `Announcements` | Announcement | SSOT/정책 변경 공지 | 공지만 — 변환 없음, transient |
| `Ideas` | Open-ended | RFC, "할까말까", 설계 탐색 | 결정(D-#) 발생 → issue convert |
| `Q&A` | Q&A (Answers enabled) | 자기참조 "왜 X 를 Y 방식?" + 외부 질문 | answered 표시 → pinned, archive |
| `Lessons` | Open-ended | 외부 학습·재사용 가능한 지식 정리 (YouTube/문서 학습, 패턴, PR 회고) — **Discussion-first** | 변환 없음 — 양 늘면 `docs/learnings/` 로 승격 |

카테고리 이름 옆 emoji icon 은 GitHub 카테고리 시스템이 강제하는 UI
메타데이터다. 본 정책의 "no emoji" 룰 범위 밖 — 텍스트 출력
(commit/code/docs) 이 아닌 picker 메타데이터로 간주한다.

## 라우팅 결정 트리

새 항목을 등록할 때 다음 순서로 분기한다.

```
결정된 작업(구현 가능한 to-do)인가?
  YES -> Issue 등록 (현재 워크플로우 유지)
  NO  v

"할까말까" 단계 / 결정 전 탐색인가?
  YES -> Discussion: Ideas
  NO  v

SSOT/정책 변경 공지인가?
  YES -> Discussion: Announcements
  NO  v

자기참조용 "왜 이렇게 했지?" 인가?
  YES -> Discussion: Q&A
  NO  v

재사용 가능한 지식 정리 (외부 학습/패턴/회고) 인가?
  YES -> Discussion: Lessons (Discussion-first, 양 늘면 docs/learnings/ 승격)
  NO  -> 다시 위로 -- 분류 모호하면 Issue 우선
```

## 운영 원칙 4 개조

1. **Issue 가 default**.
   Discussion 은 issue 가 되기엔 너무 이르거나(RFC), 너무 늦은
   (announcement / lessons) 항목 전용. 의심되면 Issue 로 등록한다.

2. **결정되면 즉시 Issue convert**.
   Discussion 이 limbo 상태로 누적되지 않게 한다. Ideas 카테고리의
   토론이 결정에 도달하면 GitHub UI 의 `Convert to issue` 로 즉시
   승격시킨다.

3. **Kanban 보드에 Discussion 미포함**.
   보드는 work-in-progress only — `github-project-board.md` 와 정합.
   `Auto-add to project` 워크플로우의 필터는 `is:issue,pr` 만 매칭하므로
   Discussion 은 자동 추가되지 않는다. 수동 추가도 하지 않는다.

4. **변환 시 양방향 백링크 유지**.
   SSOT chain 이 끊기지 않게 한다 (아래 변환 규약 참조).

## Discussion → Issue 변환 규약

Ideas 카테고리에서 결정이 났을 때 사용한다.

1. GitHub UI 의 `Convert to issue` 버튼 사용. GitHub 은 변환 직후
   원본 Discussion 을 자동으로 close 처리하고 "transferred to issue"
   배너를 남긴다 — 별도 close 조작 불필요.
2. 변환된 Issue 본문 첫 줄에 백링크 추가:
   ```
   Originated from discussion #<N>
   ```
3. (선택) 자동 close 된 원본 Discussion 에 다음 코멘트를 남겨 양방향
   참조를 명확히 한다:
   ```
   Linked to issue #<M> -- decision tracked there.
   ```
4. (선택) 원본 Discussion 을 `Lock conversation` (Resolved 사유) 으로
   잠가 추가 토론을 새 Issue 로 유도한다. 토론 흔적은 closed 상태로
   forum 에 보존된다.

## Issue → Discussion 변환 규약 (역방향)

기존 Issue 가 RFC 성격으로 잘못 등록됐다고 판단되면 사용한다.

1. GitHub UI 의 Issue 페이지에서 `Convert to discussion` 사용.
2. 카테고리는 `Ideas` 선택.
3. 변환된 Discussion 본문 첫 줄:
   ```
   Originated from issue #<N> (re-classified as RFC).
   ```
4. 원본 Issue 는 GitHub 이 자동 close 한다 — 별도 조치 불필요.
5. 보드 카드는 `Item closed` 빌트인 워크플로우가 `Done` 으로 이동시킨다.
   "Done by re-classification" 으로 해석되며 노이즈 방지를 위해
   필요 시 카드를 수동 archive 한다.

## Lessons 카테고리 운영

**Discussion-first** — Lessons Discussion 이 1 차 SSOT 다. 양·재사용
가치가 충분히 커지면 `docs/learnings/<slug>.md` 로 승격한다. 파일을
먼저 쓰지 않는다.

배경: 외부 학습 (YouTube/블로그/공식 문서) 을 정리할 때 file-first 흐름은
"파일 작성 → mirror" 두 번 쓰기 비용이 크고 모바일에서 부담된다.
Discussion 한 곳에서 캡처하고 가치가 검증되면 영구화하는 흐름이
실용적이다.

### 신규 정리 시

- Lessons 카테고리에 바로 Discussion 작성. 출처 (영상 URL, 문서 링크,
  강연 메모) 를 본문 상단에 둔다.
- 짧은 단편 노트는 Discussion 만 유지한다 (파일 없음). 검색은 GitHub
  UI 의 Discussions 필터·라벨에 의존.
- `docs/learnings/` 와 중복 작성 금지 — 둘 다 만들면 SSOT 가 분산된다.

### 승격 (Discussion -> docs/learnings/)

다음 중 둘 이상이면 `docs/learnings/<slug>.md` 로 추출 후 Discussion
본문 첫 줄에 파일의 절대 URL 링크를 추가한다.

- (a) Discussion 본문/댓글 누적 ≥ 300 줄
- (b) 외부 코드·PR·다른 Discussion 에서 3 회 이상 참조
- (c) checklist / reference / cheat sheet 형태로 재방문 빈도가 높음

승격 후에도 Discussion 은 close 하지 않는다 — forum 흔적 + 후속 댓글
통로 유지. 파일 갱신 시 Discussion 본문은 동기화하지 않는다 (overhead
회피, 파일이 canonical 이라는 점만 본문 첫 줄에서 명시).

### 정리 안 함 (out of scope)

- 결정·RCA 처럼 frozen artifact 가 필요한 항목 → `docs/learnings/`
  대신 적절한 위치 (예: `docs/incidents/` 등) 에 file-first 로 작성.
  Lessons 카테고리에 그대로 두지 않는다.
- 프로젝트 작업 to-do 와 섞이는 학습 노트 → Issue 가 우선 (라우팅
  결정 트리 1 단계).

## 대안 검토 (Alternatives Considered)

| 대안 | 거절 사유 |
|---|---|
| Discussion 없이 issue label 만으로 분리 (`type:rfc` 등) | RFC 가 여전히 보드에 노출. lifecycle 충돌 — RFC 는 open-ended, issue 는 close 기본. |
| `docs/rfc/<slug>.md` 파일로 RFC 관리 | 댓글·반응·threaded 토론 불가. future-self 검색성에서 GitHub UI 가 우월. |
| 카테고리 6 종 default 유지 (General/Polls/Show and tell 포함) | 솔로 개발 환경에서 community feature 가치 = 0. 카테고리 ≥ 5 면 라우팅 결정 비용만 증가. YAGNI. |
| Discussions 대신 외부 forum (Notion/Discord) | gh-* 스킬 체인과의 통합성 상실. Issue ↔ Discussion 양방향 convert 불가. |

## 운영 상의 유의사항

- 기존 issue 와 카테고리 라우팅 충돌 시 (이미 등록된 RFC 성격 issue)
  강제 마이그레이션하지 않는다. **신규 항목부터** 정책 적용.
- 카테고리 4 종 외 신규 카테고리 신설은 본 SSOT 갱신을 동반해야 한다.
  Discussion UI 에서 즉흥적으로 만들지 않는다.
- 외부 contributor 발생 시 Q&A 카테고리 정책 보강 — 현재는 future-self
  우선, 외부 진입 시점에 별도 issue 로 정리한다.
- 알림 noise: 솔로 개발이라 수신자가 본인 1 명 — watch 설정은 default
  유지.

## 후행 작업 (별도 이슈)

본 정책 도입 후 다음 보강을 별도 이슈로 분리한다:

- `feat(gh-discussion-create)`: 현재 대화를 Ideas RFC Discussion 으로
  등록하는 스킬.
- `feat(gh-discussion-convert)`: Discussion → Issue 변환 + 백링크 자동화.
- `feat(gh-issue-create)`: `--as-discussion` 라우팅 플래그.
- `chore(docs/learnings)`: 기존 learnings 일부를 Lessons 카테고리로 미러링.

## References

- 근거 이슈: #612
- 관련 정책: [`github-project-board.md`](./github-project-board.md)
- 관련 디렉토리: `docs/learnings/`
- GitHub 공식:
  - About discussions:
    <https://docs.github.com/en/discussions/collaborating-with-your-community-using-discussions/about-discussions>
  - Best practices for community conversations:
    <https://docs.github.com/en/discussions/guides/best-practices-for-community-conversations-on-github>
  - Managing categories:
    <https://docs.github.com/en/discussions/managing-discussions-for-your-community/managing-categories-for-discussions>
