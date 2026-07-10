---
name: devx:autopilot
description: >-
  [Claude Code] 완성된 spec 으로부터 Stage-B(구현계획→신규 이슈→구현→PR→
  /simplify→/gh-pr-reply)를 사용자 승인 없이 끝까지 자율 실행하는 composition
  스킬. Use when the user runs /devx:autopilot, /devx-autopilot, or asks
  "spec 부터 PR까지 자동으로", "stage-B 자동 실행", "구현계획부터 pr-reply까지
  한방에", "autopilot 돌려", "내 승인 없이 끝까지 완수해". Stage-A(brainstorming·
  spec 작성)는 대상 아님 — spec 이 준비된 뒤 실행한다. 머지는 하지 않는다(사람 몫).
  Accepts `[spec-path] [--mode auto|sdd|inline] [remote]` and `-h`/`--help`/`help`.
  (원자 단계: gh:issue-create, subagent-driven-development, gh:pr, simplify,
  gh-pr-reply / 사촌: gh:issue-flow)
allowed-tools: Bash, Read, Edit, Write, Grep, Skill, Agent, TaskCreate, TaskUpdate, TaskList
metadata:
  model_recommendation:
    tier: opus
    reason: "autonomous multi-stage orchestration + Advisor 검증 판단(계획 품질·inline/SDD·테스트 검증); opus worker 위임"
    claude: prefer
    non_claude: advisory-only
---

# devx:autopilot — Stage-B 자율 실행 (spec → PR)

## CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop between chained steps.** Three layered
guards prevent it — (1) `--no-next-hint` 계열 옵션으로 하위 스킬 trailing hint 억제,
(2) 체이닝된 `Skill()` 호출(Step 0a·0b·2·3·4·5) 사이 **대화 텍스트 0**,
(3) 하네스 Stop hook (`claude/hooks/devx_autopilot_stop_guard.py`) — 순서화된 단계
완료 마커 `[step:devx-autopilot/<id>] OK` 를 추적한다. **Do not remove any of them.**
전체 근거는 `references/critical-contract.md` — Step 편집 전 반드시 읽는다.

## Help

arg #1 이 `-h`/`--help`/`help` 이면 `references/help.md` 를 verbatim 출력 후 정지.
No API calls.

## Step 1 이전: Parse Args & Preconditions

| 인자 | 설명 | 기본 |
|---|---|---|
| `[spec-path]` | spec 파일 경로 | 최신 `docs/superpowers/specs/*-design.md` 자동 감지(+세션 교차확인) |
| `--mode auto\|sdd\|inline` | 구현 방식 | `auto` |
| `[remote]` | git remote | `origin` |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

`START_TS=$(date +%s)` 를 즉시 기록(리포트 elapsed 용). Preconditions(실패 시 즉시 정지):
전용 worktree 의 feature 브랜치(디폴트 브랜치면 정지) · 승인된 spec 존재(자동 감지 실패 시
`[spec-path]` 요청 후 정지) · 원자 스킬 설치 확인.

## Steps — 체이닝 사이 대화 텍스트 0 (CRITICAL CONTRACT)

각 단계는 이전 단계 성공 시에만 진행한다. 각 단계 완료 직후 그 단계의 완료 마커
`printf '[step:devx-autopilot/<id>] OK\n'` 를 출력하고, 바로 다음 `Skill()` 호출로 넘어간다.

- **Step 0a — 계획** — `Skill(superpowers:writing-plans)` — spec →
  `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`. 완료 후
  `printf '[step:devx-autopilot/plan] OK\n'`.
- **Step 0b — 이슈** — `Skill(gh:issue-create)` — host-aware(`references/host-resolution.md`)로
  추적 이슈 생성, `ISSUE_NUM`·URL 확보. 완료 후 `printf '[step:devx-autopilot/issue] OK\n'`.
- **Step 1 — 모드 선택** (`references/mode-heuristic.md`) — `auto` 면 계획을 읽어 판정,
  `mode=<sdd|inline> reason=...` 1줄 로그. `--mode` 우선. 완료 후
  `printf '[step:devx-autopilot/mode] OK\n'`.
- **Step 2 — 구현** — SDD: `Skill(superpowers:subagent-driven-development)`; inline: 계획대로
  직접 TDD 구현·논리 단위 커밋. **Advisor 검증(공통·비생략)**: 영향 범위 테스트·typecheck·lint
  를 직접 실행, 실패면 PR 진행 금지(수정 후 재검증). 완료 후
  `printf '[step:devx-autopilot/implement] OK\n'`.
- **Step 3 — PR** — `Skill(gh:pr, "<ISSUE_NUM>")`, `Closes #ISSUE_NUM` 보장, PR URL 에서
  `PR_NUM` 추출. 완료 후 `printf '[step:devx-autopilot/pr] OK\n'`.
- **Step 4 — /simplify** — `Skill(simplify, "<PR_NUM>")`. 품질 픽스 적용·커밋·push. 완료 후
  `printf '[step:devx-autopilot/simplify] OK\n'`.
- **Step 5 — /gh-pr-reply** — `Skill(gh-pr-reply, "<PR_NUM>")` **즉시**. 코멘트 없으면 no-op
  `[SKIP]` 보고. 코멘트 유무와 무관하게 항상 완료 후
  `printf '[step:devx-autopilot/pr-reply] OK\n'`.
- **Step 6 — 보고** — `references/report-template.md` 의 `[OK]/[FAIL]` 구조화(이슈·PR URL·선택
  모드·단계별 상태·검증 근거·남은 사람 몫=리뷰/머지) + AI metrics(soft-fail). 마지막에
  `printf '[step:devx-autopilot/report] OK\n'`.

## 자율성·안전

단계 간 승인/체크인 없음(사용자 사전 위임). **절대 금지**: PR 머지, 디폴트 브랜치 push,
`--force`/`--force-with-lease` push, `--no-verify`, 테스트 실패 상태 PR, spec 없는 자동 실행.
**정지 규칙**: 어느 단계든 하드 실패 시 그 지점에서 정지하고 재개 리포트 출력(이후 단계 자동
스킵). 전체 제약은 `references/constraints.md`, early-stop 가드는 `references/critical-contract.md`.
