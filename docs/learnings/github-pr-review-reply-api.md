# GitHub PR 리뷰 답글 API 엔드포인트 분기

## Context

- **출처**: [PR #130](https://github.com/dEitY719/dotfiles/pull/130) 리뷰 처리 중
- **관련 스킬**: [`~/.claude/skills/gh-pr-reply/SKILL.md`](../../claude/skills/gh-pr-reply/SKILL.md)
- **실제 답글 URL 예시**:
  - inline reply: `https://github.com/dEitY719/dotfiles/pull/130#discussion_r3077014914`
  - top-level reply: `https://github.com/dEitY719/dotfiles/pull/130#issuecomment-4241171344`

PR 리뷰 코멘트에 답글을 남길 때, **코멘트 종류에 따라 POST 해야 하는 엔드포인트가 다릅니다.**
잘못 선택하면 답글이 원하는 스레드에 붙지 않아 리뷰어가 답글을 놓치거나,
top-level 이어야 할 답글이 inline 으로 붙어 맥락이 깨집니다.

## Pattern

PR 에는 세 종류의 "코멘트" 가 있으며 각각 다른 엔드포인트를 씁니다.

| 종류 | 조회 엔드포인트 | 답글 엔드포인트 | 스레드 유지 |
|---|---|---|---|
| inline diff 코멘트 | `/pulls/{n}/comments` | `/pulls/{n}/comments/{id}/replies` | O |
| 리뷰 요약 body | `/pulls/{n}/reviews` | `/issues/{n}/comments` (top-level) | X |
| 이슈 레벨 PR 코멘트 | `/issues/{n}/comments` | `/issues/{n}/comments` (top-level) | X |

**핵심 직관**:
- 코멘트가 **diff 의 특정 라인에 고정**되어 있으면 inline → replies 엔드포인트
- 코멘트가 **PR 전체에 대한 것**이면 top-level → issues/comments

## Code

```sh
# 1. inline diff 코멘트에 스레드 답글
gh api -X POST "repos/OWNER/REPO/pulls/N/comments/COMMENT_ID/replies" \
  -f body="Accepted — fixed in abc1234."

# 2. 리뷰 요약·이슈 코멘트에 top-level 답글
gh api -X POST "repos/OWNER/REPO/issues/N/comments" \
  -f body="@reviewer Thanks — ..."
```

## 실전 팁

- 코멘트 ID 추출 — `--jq` 로 바로 파이프 가능:
  ```sh
  gh api "repos/OWNER/REPO/pulls/N/comments" --jq '.[] | {id, user: .user.login, path, line, body}'
  # 또는 미답변 스레드만 필터
  gh api "repos/OWNER/REPO/pulls/N/comments" --jq '.[] | select(.in_reply_to_id == null) | .id'
  ```
- `pull_request_review_id` 는 리뷰 전체 ID 이지 개별 코멘트 ID 가 **아님** — 혼동 주의
- 답글은 리뷰어의 언어로 (영어 리뷰 → 영어 답글, 한국어 리뷰 → 한국어 답글)
- 봇 리뷰도 동일 정책으로 답글을 남김 — 마케팅 메시지도 "Declined: non-actionable" 한 줄 기록해야 감사 이력이 깔끔

## 주의: 리뷰 요약(summary) 답글은 직접 API 가 없음

`/pulls/{n}/reviews` 의 리뷰 바디(gemini-code-assist 가 남기는 "## Code Review" 같은
전체 요약)에는 **직접 답글 API 가 존재하지 않습니다.** 대응 방법:

1. 요약의 개별 항목이 inline 코멘트로도 존재한다면, 각 inline 스레드에 답글
   (가장 흔한 경우 — 요약은 자동으로 맥락이 커버됨)
2. 요약 자체에 actionable 내용이 있고 inline 이 없다면, `/issues/{n}/comments`
   로 top-level 답글을 남기면서 `> blockquote` 로 요약 발췌를 인용
3. Non-actionable (마케팅, 인사, 저작권 등) → 간단한 Declined 라벨 한 줄만

이 문서의 "Pattern" 표에서 `/issues/{n}/comments` 를 답글 엔드포인트로 적은
것이 바로 이 우회 방법입니다.

## When to use

**적용**
- PR 리뷰에 답글을 작성하는 모든 상황 (사람·봇 무관)
- `/gh-pr-reply` 스킬 실행 중 수동 개입이 필요할 때
- `gh` CLI 만으로 리뷰를 처리하는 자동화 스크립트 작성 시

**불필요**
- 웹 UI 에서 직접 답글 작성 — GitHub 이 알아서 올바른 엔드포인트로 보냄
- 새 PR·이슈 생성 — `gh pr create` / `gh issue create` 는 별도 엔드포인트

## 함정 사례

- `gh pr comment <N> -b "..."` 은 **항상 top-level** 로 붙음 — inline 답글을 의도했다면 사용 금지
- `/pulls/{n}/comments` 엔드포인트로 **POST** 하면 신규 inline 리뷰 코멘트 생성(기존 스레드에 답글이 아님) — 반드시 `/replies` 경로를 붙여야 함

## Related

- **스킬**: `claude/skills/gh-pr-reply/references/comment-fetching.md`, `reply-templates.md`
- **GitHub API 문서**: [Review comments](https://docs.github.com/en/rest/pulls/comments), [Issue comments](https://docs.github.com/en/rest/issues/comments)
- **관련 작업**: PR #130 의 gemini / sourcery 리뷰 답글 처리
