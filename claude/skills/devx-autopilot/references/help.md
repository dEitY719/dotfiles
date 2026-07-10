# devx:autopilot — Usage

    /devx:autopilot [spec-path] [--mode auto|sdd|inline] [remote]

Stage-B 를 spec 으로부터 자율 실행: 구현계획 → 신규 이슈 → 구현 → PR → /simplify → /gh-pr-reply.
승인 없이 끝까지 진행하며 PR 머지는 하지 않는다(사람 몫).

## Arguments
- spec-path   구현할 spec 파일. 생략 시 docs/superpowers/specs/ 최신 *-design.md 자동 감지.
- --mode      auto(기본)|sdd|inline. auto 는 계획 복잡도로 자동 판정.
- remote      git remote (기본 origin).
- -h/--help   이 도움말.

## Precondition
전용 worktree 의 feature 브랜치에서 실행(디폴트 브랜치 금지). 승인된 spec 이 있어야 한다.

## 하지 않는 것
Stage-A(brainstorming/spec 작성) · PR 머지 · 릴리스 · 디폴트 브랜치 작업.

## 관련
gh:issue-flow(이슈→PR 사촌) · subagent-driven-development · simplify · gh-pr-reply · devx:restart(중단 재개)
