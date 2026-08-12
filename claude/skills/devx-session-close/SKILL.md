---
name: devx:session-close
description: >-
  세션을 닫기 전 "남은 작업 없나"를 고정된 4개 항목으로 감사해
  `[OK]`/`[BLOCKED]` 판정을 내리는 read-only 스킬 — 저장소를 전혀 바꾸지
  않는다. Use when the user runs /devx:session-close, /devx-session-close,
  or says "세션 닫아도 되나", "종료 전 점검", "남은 작업 없는지 봐줘",
  "이제 끝내도 돼?", "audit this session before I close it". git 상태(미커밋
  변경 · 원격 미반영 커밋 · 진행중 merge/rebase/cherry-pick · stash) ·
  TodoList 잔여 · 임시 산출물 · 이번 세션이 만든 이슈/PR 을 점검하고,
  마지막 두 줄에 판정과 다음 행동만 남긴다. 그린이면 `/exit` 를 안내한다 —
  대신 실행하지 않고, 잔여 작업을 대신 처리하지도 않는다.
  (재개: devx:restart, handoff: devx:session-handoff)
allowed-tools: Bash, Read, Grep, TaskList
metadata:
  model_recommendation:
    tier: sonnet
    reason: "검사는 lib/ 스크립트가 결정적으로 수행하고 판단이 드는 지점은 '이번 세션이 건드린 저장소' 를 대화에서 추리는 Step 2 하나뿐이다"
    claude: prefer
    non_claude: advisory-only
---

# devx:session-close — 종료 전 잔여 작업 감사

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and
stop. No other tool calls.

## Step 1: Args (F-1)

`SKILL_DIR` = this file's directory. `--repos <path,...>` 는 자동 수집이
놓친 저장소를 **보태는** 용도다(치환 아님). `-h`/`--help`/`help` 는 위 Help.

## Step 2: 대상 저장소 수집 (F-2, 판단)

여기만 대화를 읽어야 한다. 다음을 모아 절대경로로 정규화하고 중복을 없앤다.

1. 현재 작업 디렉터리의 저장소 최상위 (`git rev-parse --show-toplevel`).
2. 이번 세션이 파일을 읽고 쓴 다른 저장소·워크트리 — 대화에 등장한 경로를
   그대로 쓴다(추측 금지).
3. `--repos` 로 받은 경로.

cwd 하나만 보고 끝내지 않는다 — 워크트리를 여러 개 띄운 세션이 기본이다.
목록이 0개면 Step 3 를 건너뛰지 말고 그대로 넘겨라. 스크립트가 "검사 대상
없음" 을 명시한다 (NF-6).

## Step 3: C-1 git 상태 (F-3)

```
bash "${SKILL_DIR}/lib/check-repos.sh" <repo> [repo...]
```

출력의 `BLOCKED:` / `NOTE:` / `WARN:` 줄을 그대로 집계한다. 판정 규칙과
NF-4 강등(사내PC + github.com 원격 → 원격 미반영 커밋은 NOTE)은
`references/checks.md` 에 있다.

## Step 4: C-2 TodoList (F-4)

`TaskList` 로 현재 todo 를 읽어 `in_progress` / `pending` 항목을 나열한다.
`in_progress` 는 BLOCKED, `pending` 은 NOTE. todo 가 아예 없으면 "TodoList
없음" 한 줄로 명시한다 — 조용히 넘어가지 않는다 (NF-6).

## Step 5: C-3 임시 산출물 (F-5)

```
bash "${SKILL_DIR}/lib/check-artifacts.sh" --scratchpad <this session's scratchpad> <repo>...
```

scratchpad 경로는 세션이 시스템 프롬프트로 받은 값을 그대로 넘긴다. 없으면
`--scratchpad` 를 생략한다. 결과는 전부 NOTE 다.

## Step 6: C-4 산출물 후속 (F-6)

이번 세션이 만든 이슈/PR 번호가 대화에 있으면
`gh issue view <N> --json state,title` / `gh pr view <N> --json state,title`
로 상태만 확인한다. 실패는 `[WARN]` 한 줄로 낮추고 판정을 뒤집지 않는다
(NF-3). 번호가 없으면 호출하지 않는다.

실행중인 백그라운드 작업·서브에이전트는 **검사하지 못한다** — 스킬 안에서
그것들을 열거하는 확인된 표준 수단이 없다. 경고 한 줄만 남기고 넘어간다
(`references/checks.md` 의 Open Question 참고).

## Step 7: 판정과 출력 (F-7~F-9)

`references/report.md` 의 형식으로 C-1~C-4 리포트를 찍고, **마지막 두 줄**에
`[OK]`/`[BLOCKED]` 판정과 `Next:` 한 줄만 남긴다. BLOCKED 의 원인이 미완
작업이면 `Next:` 는 devx:session-handoff 를 가리킨다.

## Constraints

- read-only 전용 — 파일을 만들거나 고치거나 지우지 않고, git 상태를 바꾸지
  않으며, 원격에 아무것도 보내지 않는다. 조치 명령은 출력만 하고 실행 여부는
  사용자가 정한다 (NF-1).
- `/exit` 를 대신 실행하지 않는다. 프로세스를 강제로 끝내지도, 대화 종료
  도구를 부르지도 않는다 — 안내 문자열만 찍는다 (NF-2).
- 네트워크는 C-4 만 쓴다 (NF-3). 잔여 작업을 대신 처리하지 않는다 — 인계
  문서는 devx:session-handoff, 세션 기록은 write:task-history /
  obsidian:session-clip 몫이다.
