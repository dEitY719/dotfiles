# GitHub Project 칸반 보드 워크플로우

## 목표

dotfiles 저장소의 모든 작업을 단일 칸반 보드에서 추적한다.
이 문서는 `dEitY719/dotfiles`의 GitHub Project v2 보드 운영 규칙의
SSOT이다.

## 적용 범위

- 저장소: `dEitY719/dotfiles` (repo-level project)
- 카드 종류: Issue와 PR 모두 (보드에서 함께 추적)
- 자동화 수단: GitHub Projects v2 빌트인 워크플로우 + dotfiles 스킬 보정
- 관련 스킬: `gh:issue-create`, `gh:pr`, `gh:pr-merge`,
  `gh:pr-merge-emergency`, `gh:issue-flow`

차용 원본: `agent-toolbox`의 `.claude/workflow.md`와 `.claude/github-integration.md`.
dotfiles는 동일 원칙을 따르되 범위(단일 repo)와 자동화 수준(별도
Action 없음) 측면에서 최소화한 변형을 사용한다.

## 보드 구조

### Status 필드 옵션 (6개)

Status 필드는 아래 6개 옵션을 이 순서로 가진다:

`Backlog`, `Ready`, `In progress`, `In review`, `Approved`, `Done`.

### 카드 타입별 라이프사이클

같은 Status 필드를 공유하지만 Issue와 PR 카드가 실제로 방문하는
컬럼은 다르다 (2026-04-24 확정).

- **Issue 카드 (4단계)**: `Backlog → In progress → In review → Done`
- **PR 카드 (기본 4단계)**:
  `Backlog → In review → Approved → Done`.
  리뷰에서 `Changes requested`가 제출되면 `Code changes requested`
  워크플로우가 PR 카드를 `In progress`로 되돌린다 — 수정·재푸시
  후 `In review`로 수동 복귀시킨 뒤 이어서 `Approved → Done`
  으로 진행한다.

`Ready`는 두 카드 타입 모두 방문하지 않는다. 미래 확장(예:
"분석 완료·착수 대기" 단계가 필요해지는 시점) 여지로 남겨둔다.

### 컬럼별 의미

| 컬럼        | Issue 카드                         | PR 카드                     |
|-------------|------------------------------------|-----------------------------|
| Backlog     | 신규 등록, 미착수                   | 신규 PR, 리뷰 시작 전        |
| Ready       | (사용 안 함)                        | (사용 안 함)                 |
| In progress | 작업 중 (브랜치 생성, 커밋 진행)     | 리뷰 피드백 반영 중 (Changes requested 루프) |
| In review   | 연결된 PR이 열려 리뷰 대기           | 본인의 리뷰 대기             |
| Approved    | (사용 안 함 — Issue는 도달하지 않음) | 리뷰 승인됨, 머지 대기        |
| Done        | 연결된 PR 머지로 close됨             | 머지 완료                   |

## 카드 정책 (Open Question #1 결정)

**결정: Issue와 PR 카드를 모두 등록한다 (Option B)**.
2026-04-24 Option A(Issue-only)에서 전환 — 운영자의 다른
Project 보드와 일관된 운영 방식 확보가 목적.

- 보드에는 Issue 카드와 PR 카드가 동시에 존재한다.
- Issue = 요구사항·상태의 SSOT, PR = 리뷰·머지 진행의 SSOT.
  각각 별도 카드로 보드에 노출된다.
- 1개 Issue에 여러 PR이 붙는 경우 각 PR이 별도 카드로 올라온다.
- 장점: PR 리뷰 단계(In review → Approved → Done)를 별도 도구
  없이 보드에서 직접 관찰·조작할 수 있고, `Code review approved`·
  `Pull request merged` 빌트인 워크플로우를 자연스럽게 활용한다.
- 트레이드오프: 카드 수가 대략 2배가 되고 Issue/PR이 중복
  노출된다. 혼잡을 감수하는 대신 투명성을 얻는 선택.
  필요 시 View를 분리(`Issues only`, `PRs only`)해 가시성을
  보완한다.

## 프로젝트 범위 (Open Question #2 결정)

**결정: repo-level project (`dEitY719/dotfiles` 전용)**.

- 사용자 레벨 프로젝트(`dEitY719` 소유)는 쓰지 않는다.
- 이유: dotfiles 자체에만 집중하는 좁은 스코프가 운영 부담이 적다.
  여러 저장소를 한 보드에서 추적할 필요가 생기면 그때
  user-level로 이전한다.

## Closing Keyword 강제 (Open Question #3 결정)

**결정: 두 가지 경로로 강제한다**.

1. **PR 템플릿** (`.github/pull_request_template.md`)에
   `Closes #` 자리표시자를 포함한다. 사람이 웹/CLI로 직접 PR을
   만들어도 템플릿이 채워진다.
2. **`gh:pr` 스킬의 PR 본문 템플릿**
   (`claude/skills/gh-pr/references/pr-body-template.md`)은 이슈
   번호가 해결된 경우 `## Related` 섹션에 `Closes #<N>` 줄을
   **반드시** 포함한다. 누락되면 Done 자동 전환이 끊긴다.

허용 키워드: `Closes #N` (기본) · `Fixes #N` (버그) ·
`Resolves #N` (기타 해결). GitHub은 세 키워드 모두 Issue 자동
종료를 트리거한다.

## 마이그레이션 범위 (Open Question #4 결정)

**결정: 신규 Issue부터 적용한다**.

- 보드 도입 시점 이후 생성되는 Issue만 자동으로 `Backlog`에
  추가된다 (Auto-add 워크플로우).
- 기존 열린 Issue는 필요 시 수동으로 보드에 추가한다
  (`gh project item-add`). 일괄 마이그레이션은 수행하지 않는다.

## 자동 전환 규칙

GitHub Projects v2의 빌트인 워크플로우 10개 중 9개가 `enabled`
상태로 운영되고, `Auto-archive items`(#10)는 `disabled` 기본값에서
명시적으로 enable 해 Done 컬럼 정리용으로 활용한다. 카드 타입에
따라 영향 범위가 다르다.

### Status를 변경하는 워크플로우

| # | 워크플로우                     | 트리거                                            | 대상 카드 | Status          |
|---|--------------------------------|---------------------------------------------------|-----------|-----------------|
| 1 | `Auto-add to project`          | 필터(`is:issue,pr is:open` + repo `dotfiles`) 일치 | 둘 다     | —  (추가만)      |
| 2 | `Item added to project`        | 카드가 보드에 추가됨                                | 둘 다     | `Backlog`       |
| 3 | `Pull request linked to issue` | PR이 `Closes/Fixes/Resolves #N`으로 Issue 연결     | Issue     | `In review`     |
| 4 | `Code review approved`         | PR에 Approve 리뷰 제출                            | PR        | `Approved`      |
| 5 | `Code changes requested`       | PR에 Changes requested 리뷰 제출                   | PR        | 선호 컬럼 (기본 `In progress`) |
| 6 | `Pull request merged`          | PR 머지                                           | PR        | `Done`          |
| 7 | `Item closed`                  | 카드 아이템이 close됨                               | 둘 다     | `Done`          |

### Status를 변경하지 않는 구조적 워크플로우

| #  | 워크플로우                          | 동작                                              |
|----|-------------------------------------|---------------------------------------------------|
| 8  | `Auto-close issue`                  | 부모 Issue의 모든 sub-issue가 close되면 부모를 auto-close |
| 9  | `Auto-add sub-issues to project`    | 부모 Issue가 보드에 있으면 sub-issue도 자동 추가      |
| 10 | `Auto-archive items`                | 필터 매칭 카드를 주기적으로 archive (Done 컬럼 정리용). 기본 `disabled` — 수동 enable 필요. dotfiles 채택 필터: `is:issue,pr is:closed updated:<@today-2d` |

### 자동 전환 규칙 (스킬 경유)

GitHub 빌트인이 커버하지 않거나 누락 시 보강해야 하는 네 전환은
dotfiles 의 스킬이 공용 헬퍼 `_gh_project_status_sync`
(`shell-common/functions/gh_project_status.sh`) 를 통해 자동화한다.
보드가 없는 repo (예: `dotfiles` 이외의 사이드 프로젝트) 에선 헬퍼가
`projectItems` 0건을 감지하고 조용히 no-op 하므로 추가 분기가 필요
없다.

- **Issue 카드 `Backlog → In progress`**: `/gh-flow` 워커 또는
  `/gh-commit` 단독 실행이 커밋 메시지에서 `Closes|Fixes|Refs #N` 을
  찾으면 자동 전환한다. 단, `--only-from Backlog` 가드가 적용되어
  같은 이슈에 대해 follow-up 커밋이 들어와도 `In review` 상태를
  되돌리지 않는다. raw `git commit` 으로 진행하는 경로에선 작업자가
  수동으로 옮긴다.
- **PR 카드 `Backlog → In review`**: `/gh-flow` 워커 또는 `/gh-pr`
  단독 실행이 PR 생성 직후 자동 전환한다. raw `gh pr create` 로
  PR 을 만든 경우엔 수동 이동이 필요하다.
- **PR 카드 `In review → Approved`**: `/gh-pr-reply` 가 reply 라운드
  종료 후 자동 전환한다. GitHub 빌트인 `Code review approved` 는
  누군가 `APPROVED` 상태의 review 를 제출해야만 트리거되는데,
  GitHub 정책상 **PR 작성자는 자기 PR 을 Approve 할 수 없으므로**
  1인 repo (`dotfiles` 처럼 단독 운영하는 저장소) 에서는 빌트인이
  영원히 작동하지 않는다. `/gh-pr-reply` 가 그 갭을 메운다 — reply
  라운드가 닫혔다는 것은 의미적으로 "리뷰 사이클 종료, 머지 대기"
  이므로 `Approved` 와 정합한다. `--only-from "Backlog,In progress,In
  review"` 가드를 적용해 머지된 PR (`Done`) 에 잘못 호출되었을 때
  카드가 `Approved` 로 되돌아가는 regression 을 막는다.
- **PR 카드 `Approved → Done`**: 두 갈래로 보정한다.
  - `/gh-pr-merge` / `/gh-pr-merge-emergency` 경유 머지: 스킬이 머지
    성공 직후 in-skill Step 4(a) 에서 직접 전환한다.
  - 웹 UI / 모바일 / raw `gh pr merge` 경유 머지 (#266): GitHub Actions
    워크플로우 `.github/workflows/project-board-sync.yml` 가
    `pull_request.closed && merged == true` 에 자동 fire 하여 동일
    헬퍼 (`_gh_project_status_sync pr <N> "Done"`) 를 호출한다. 즉
    머지 경로가 무엇이든 PR 카드는 `Done` 으로 수렴한다.

  GitHub Projects 빌트인 `Pull request merged` (#6) 는 enabled 이지만
  저장소·보드 설정 차이로 fire 가 누락되는 사례가 #265 머지에서
  관측되어 (#266) 위 두 보정 경로가 안전망 역할을 한다. 워크플로우는
  `secrets.PROJECT_BOARD_PAT` (project 스코프 PAT) 를 사용한다 — PAT
  미설정 시엔 워크플로우가 warning 을 남기고 no-op 으로 종료하므로
  포크 PR 도 안전하다.
- **PR 카드 `In progress → In review` (재리뷰 요청 시)**:
  `Changes requested` 루프에서 수정·재푸시 후 리뷰가 다시 달리기를
  기대할 때 **수동**으로 복귀시킨다. Projects v2 빌트인에도 dotfiles
  스킬에도 이 전환을 자동화하는 경로가 없다. 이 외의 PR 전환
  (`→ Done`) 은 빌트인 `Pull request merged` / `Item closed` 가
  자동 처리한다.
- **Issue 카드 `In review → Done` (PR-Closes 경로 보강)**:
  `/gh-pr-merge` 와 `.github/workflows/project-board-sync.yml` 둘 다
  머지 직후 PR 의 `closingIssuesReferences` 를 순회하며 각 Issue
  카드를 `Done` 으로 강제 이동한다. 빌트인 `Item closed` 워크플로우는
  best-effort delivery 이므로 드물게 Status 업데이트 이벤트가
  누락되어 Issue 카드가 `In review` 에 잔류하는 케이스가 관측된다
  (#239 / #250). 본 보강 전환은 그 갭을 메우며 `--only-from
  "Backlog,In progress,In review"` 가드로 이미 `Done` 상태인 카드를
  다시 건드리지 않는다. 머지 경로가 스킬이든 웹 UI 든 동일 헬퍼
  (`_gh_pr_closing_issue_numbers` + `_gh_project_status_sync`) 가
  호출되므로 동작이 수렴한다.

### 용어 교정 (2026-04-24)

이전 문서 리비전에서 "PR open (linked) → Issue In review" 전환을
"Workflows 페이지에 노출되지 않는 암묵적 훅"이라 기술했으나
**이는 오기**다. 해당 전환은 `Pull request linked to issue`
(위 표 #3)라는 명시적 워크플로우가 수행하며 Workflows 페이지에
정확히 노출된다. 2024년 UI 변경으로 `Auto-add to project`가
Status 세팅을 직접 하지 않게 된 이후, Status 세팅 책임은
`Item added to project`(#2) · `Pull request linked to issue`(#3)
등 각 이벤트 대응 워크플로우로 분산됐다.

## 보드 초기 셋업

한 번만 수행한다. `gh` 토큰에 `project` 스코프가 필요하다:

```bash
gh auth refresh -s project
```

1. 저장소 Project 생성:
   ```bash
   gh project create --owner dEitY719 --title "dotfiles"
   ```

2. 생성된 Project의 번호를 확인:
   ```bash
   gh project list --owner dEitY719
   ```

3. Status 필드에 아래 옵션을 이 순서로 추가
   (웹 UI가 가장 편함):
   `Backlog`, `Ready`, `In progress`, `In review`,
   `Approved`, `Done`.

4. 빌트인 워크플로우 설정 (Project > Workflows):
   신규 Project는 10개 워크플로우 중 9개가 `enabled`, `Auto-archive
   items`만 `disabled` 상태로 생성된다. 아래 Status 값·필터가
   올바른지 확인한다 (위 "자동 전환 규칙" 표와 동일).

   - `Auto-add to project`: repo 드롭다운에서 `dotfiles` 선택,
     필터 `is:issue,pr is:open`.
   - `Item added to project`: `issues` + `pull requests` 체크,
     Status=`Backlog`.
   - `Pull request linked to issue`: Status=`In review` (Issue
     카드의 `In progress → In review` 자동 전환 담당).
   - `Code review approved`: Status=`Approved`.
   - `Code changes requested`: Status=`In progress` (기본값;
     선호 시 변경 가능).
   - `Pull request merged`: Status=`Done`.
   - `Item closed`: `issues` + `pull requests` 체크,
     Status=`Done`.
   - `Auto-close issue`, `Auto-add sub-issues to project`:
     Status를 건드리지 않는 구조적 워크플로우로 기본 설정 유지.
   - `Auto-archive items`: 수동 enable + 필터
     `is:issue,pr is:closed updated:<@today-2d` 입력 — Done 컬럼을
     그제 이전 분부터 자동 archive 하여 최근 2일분만 유지한다.

## 운영 상의 유의사항

- PR 본문에 `Closes #N`이 빠지면 머지 후에도 Issue가 열려 있고
  Issue 카드가 `Done`으로 가지 않는다 (PR 카드는 `Pull request
  merged`로 Done 이동). PR 템플릿과 `gh:pr` 스킬이 이를 방지하지만,
  사람이 수동으로 본문을 지울 경우를 대비해 머지 전에 한 번 더
  확인한다.
- Issue 카드의 `Backlog → In progress` 는 dotfiles 스킬
  (`/gh-flow`, `/gh-commit`) 사용 시 자동, raw `git commit` 사용
  시에만 수동이다. `/gh-commit` 은 `--only-from Backlog` 가드를
  사용하므로 PR 오픈 후 follow-up 커밋이 들어와도 `In review` 상태를
  되돌리지 않는다.
- PR 카드 `Backlog → In review` 는 dotfiles 스킬 (`/gh-flow`,
  `/gh-pr`) 사용 시 자동, raw `gh pr create` 사용 시에만 수동이다.
  `In review → Approved` 는 `/gh-pr-reply` 가 자동 처리한다 (1인
  repo 에서 self-approve 불가로 빌트인 `Code review approved` 가
  영원히 트리거되지 않는 갭을 메우기 위함). `In progress → In
  review` (`Changes requested` 루프 탈출 시) 전환만 항상 수동이다
  — 빌트인·스킬 모두 이 경로를 자동화하지 않는다.
- 보드가 없는 repo 에서 `/gh-pr`, `/gh-commit`, `/gh-pr-reply`,
  `/gh-pr-merge`, 또는 `/gh-pr-merge-emergency` 를 실행하면 공용 헬퍼
  `_gh_project_status_sync` 가 `projectItems` 가 0건임을 자동
  감지하고 조용히 no-op 한다 (별도 분기 불필요).
- Projects v2 빌트인 워크플로우는 best-effort delivery 라 드물게
  Status 업데이트 이벤트가 누락된다. PR-Closes 경로 (PR 머지로 Issue
  가 auto-close 되는 경로) 는 `/gh-pr-merge` 의 Step 4 post-merge
  reconciliation 이 자동 보강한다. 그 외 경로 (수동 close, 다른 도구로
  close) 에서 Issue 카드가 `In review` 등에 잔류하면 카드를 수동으로
  `Done` 으로 옮긴다.
- 수동으로 카드를 옮긴 경우 다음 자동 이벤트가 상태를 덮어쓸
  수 있다. 특히 Issue 카드를 `Approved`로 옮겨도 `Item closed`가
  PR 머지 시점에 곧바로 `Done`으로 이동시키므로 의미가 없다
  (Issue는 설계상 `Approved`를 방문하지 않는다).
- Issue와 PR 카드가 보드에서 중복되어 보이는 현상은 Option B의
  의도된 결과다. 혼잡하다면 `Issues only` / `PRs only` View를
  분리해 관리한다.
- Project 보드 쿼리는 CLI로도 가능하다:
  ```bash
  gh project item-list <PROJECT_NUM> --owner dEitY719 --format json
  ```

## References

- 차용 원본: `agent-toolbox`의 `.claude/workflow.md` (60-68번 줄)와
  `.claude/github-integration.md` (Project 보드 상태 전환 정책).
- GitHub Projects v2 빌트인 워크플로우:
  <https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations>
- 관련 Issue: #169 (본 문서의 도입 근거).
- 관련 스킬:
  - `claude/skills/gh-issue-create/SKILL.md`
  - `claude/skills/gh-commit/SKILL.md`
  - `claude/skills/gh-pr/SKILL.md`
  - `claude/skills/gh-pr-reply/SKILL.md`
  - `claude/skills/gh-pr-merge/SKILL.md`
  - `claude/skills/gh-issue-flow/SKILL.md`
- 관련 헬퍼: `shell-common/functions/gh_project_status.sh` (공용
  `_gh_project_status_sync` — `/gh-flow`, `/gh-pr`, `/gh-commit`,
  `/gh-pr-reply`, `/gh-pr-merge` 가 모두 호출).
- 관련 템플릿: `.github/pull_request_template.md`.
