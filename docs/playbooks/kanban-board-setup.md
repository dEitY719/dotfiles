# Kanban Board Setup Playbook

GitHub Projects v2 기반 단일 저장소 칸반보드를 빠르게 셋업하는
실행 가이드다. 기본 경로는 `scripts/setup-kanban-board.sh` 1회 실행과
GitHub UI 체크 몇 단계이며, 수동 절차는 스크립트 미사용 시나
디버깅용 fallback 으로 남긴다.

본 문서는 dotfiles repo의 SSOT
(`docs/standards/github-project-board.md`)에서 **재사용 가능한 실행
절차만 발췌**한 playbook 이다. 운영 정책과 의사결정 배경은 SSOT를
참고한다.

## 1. 목표 결과물

- Project v2 보드 1개, 특정 repo에 연결.
- Status 필드 6 옵션:
  `Backlog`, `Ready`, `In progress`, `In review`, `Approved`, `Done`.
- Issue 4단계: `Backlog → In progress → In review → Done`.
- PR 4단계: `Backlog → In review → Approved → Done`
  (`Changes requested` 발생 시 `In progress`로 일시 루프).
- PR 템플릿에 `Closes #<N>` 자리표시자 포함.
- 최종 UX: 스크립트 1회 실행 + UI 확인 몇 단계로 30분짜리 수동 셋업을
  약 5분 경로로 단축.

## 2. Quick Start

### 2.1 Prerequisites

```bash
gh auth refresh -s project
gh auth status   # Token scopes 에 'project' 가 포함돼야 함
jq --version
```

- `gh`, `jq` 가 필요하다.
- 대상 repo (`OWNER/REPO`) 는 이미 존재해야 한다.
- 스크립트는 같은 title 의 보드가 이미 있으면 **정상 종료(0)** 하며
  중복 생성하지 않는다.

### 2.2 One-Click Setup

```bash
scripts/setup-kanban-board.sh \
    --owner "$OWNER" \
    --repo "$REPO"
```

옵션:

```bash
scripts/setup-kanban-board.sh \
    --owner "$OWNER" \
    --repo "$REPO" \
    [--title "$REPO"] \
    [--auto-archive-window 2d] \
    [--hide-columns] \
    [--dry-run] \
    [--skip-pr-template]
```

스크립트가 자동으로 수행하는 일:

1. `gh` / `jq` / auth scope / 대상 repo 존재 여부를 점검한다.
2. 같은 title 의 Project 가 이미 있으면 URL을 출력하고 정상 종료한다.
3. Project 를 생성한다.
4. repo 를 Project 에 링크한다.
5. Status 필드를 6옵션으로 교체한다.
6. `.github/pull_request_template.md` 가 없으면 원격 repo 에 생성한다.
   이미 있으면 `Closes #` 포함 여부만 확인하고, 없더라도 덮어쓰지 않는다.
7. 마지막에 Project URL, Workflows URL, UI 체크리스트, smoke test 명령을
   출력한다.

## 3. UI Checklist After Script

스크립트는 마지막에 아래 항목을 직접 URL과 함께 다시 출력한다.
현재 공개 API 경로 기준으로는 built-in workflow 상세 설정까지 완전 자동화하지
않고, 사용자가 UI에서 확인해야 한다.

- `Auto-add to project`:
  repo=`<OWNER>/<REPO>`, filter=`is:issue,pr is:open`
  신규 open Issue/PR 카드가 자동 유입되도록 한다.
- `Item added to project`:
  Status=`Backlog`
  새 카드의 초기 컬럼을 통일한다.
- `Pull request linked to issue`:
  Status=`In review`
  PR 이 연결된 순간 Issue 카드가 리뷰 단계로 이동한다.
- `Code review approved`:
  Status=`Approved`
  외부 approve 경로의 PR 카드 상태를 유지한다.
- `Code changes requested`:
  Status=`In progress`
  리뷰 피드백 반영 루프를 보드에 드러낸다.
- `Pull request merged`:
  Status=`Done`
  PR 카드 종료 상태를 맞춘다.
- `Item closed`:
  Status=`Done`
  Issue/PR close 와 보드 종료 상태를 맞춘다.
- `Auto-archive items`:
  enable + filter=`is:issue,pr is:closed updated:<@today-2d`
  Done 컬럼에서 오래된 카드를 자동 정리한다.
- `--hide-columns` 를 사용한 solo repo:
  Board view 에서 `Approved`, `Ready` 컬럼을 `Hide from view` 한다.

## 4. Manual Fallback (스크립트 미사용 시 / 디버깅 시)

### 4.1 변수

```bash
export OWNER="dEitY719"
export REPO="my-project"
export PROJECT_TITLE="$REPO"
```

### 4.2 Project 생성

```bash
gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json
```

반환 JSON에서 다음 값을 기록한다.

- `id` → `PROJECT_ID`
- `number` → `PROJECT_NUMBER`

### 4.3 repo ↔ project 링크

```bash
gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$OWNER/$REPO"
```

Project 생성만으로는 대상 repo 에서 카드가 유입되지 않는다. 이 링크가
`Auto-add to project`와 후속 built-in workflow의 전제다.

### 4.4 Status 필드 ID 조회

```bash
gh api graphql -f query='
query($pid: ID!) {
  node(id: $pid) {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField { id name }
        }
      }
    }
  }
}' -f pid="$PROJECT_ID"
```

`name: "Status"` 인 필드의 `id` 를 `STATUS_FIELD_ID` 로 저장한다.

### 4.5 Status 필드 옵션 6개로 교체

```bash
gh api graphql -f query='
mutation($fid: ID!) {
  updateProjectV2Field(input: {
    fieldId: $fid
    singleSelectOptions: [
      {name: "Backlog",     color: GRAY,   description: "Idea or request only"}
      {name: "Ready",       color: BLUE,   description: "Reserved — unused in normal flow"}
      {name: "In progress", color: YELLOW, description: "Issue: coding / PR: Changes requested loop"}
      {name: "In review",   color: ORANGE, description: "Awaiting review or merge decision"}
      {name: "Approved",    color: PURPLE, description: "PR only — review approved, awaiting merge"}
      {name: "Done",        color: GREEN,  description: "Merged and closed"}
    ]
  }) { projectV2Field { ... on ProjectV2SingleSelectField { options { id name } } } }
}' -f fid="$STATUS_FIELD_ID"
```

### 4.6 PR 템플릿 생성

`.github/pull_request_template.md` 가 없으면 아래 내용을 추가한다.
이미 있으면 `Closes #<N>` 자리표시자만 포함되면 된다.

```markdown
<!--
Closes #<N> 키워드가 반드시 포함되어야 Project 보드의 Done 자동 전환이
동작합니다. 이슈를 완전히 해결하지 않는 PR은 Closes 대신 Refs 를 사용하세요.
상세는 docs/standards/github-project-board.md 를 참고하세요.
-->

## Summary
-

## Changes
-

## Test plan
- [ ]

## Related
Closes #<N>
```

### 4.7 Built-in Workflows 설정 (웹 UI)

URL:

- user owner:
  `https://github.com/users/<OWNER>/projects/<PROJECT_NUMBER>/workflows`
- org owner:
  `https://github.com/orgs/<OWNER>/projects/<PROJECT_NUMBER>/workflows`

아래 값이 SSOT 와 맞는지 확인한다.

| #  | 워크플로우                      | Set Status / Filter |
|----|---------------------------------|---------------------|
| 1  | `Auto-add to project`           | Filter: `is:issue,pr is:open` + repo: `<REPO>` |
| 2  | `Item added to project`         | `Backlog` |
| 3  | `Pull request linked to issue`  | `In review` |
| 4  | `Code review approved`          | `Approved` |
| 5  | `Code changes requested`        | `In progress` |
| 6  | `Pull request merged`           | `Done` |
| 7  | `Item closed`                   | `Done` |
| 8  | `Auto-close issue`              | 기본 유지 |
| 9  | `Auto-add sub-issues to project`| 기본 유지 |
| 10 | `Auto-archive items`            | 수동 enable + Filter: `is:issue,pr is:closed updated:<@today-2d` |

### 4.8 `Approved`·`Ready` 컬럼 hide (solo repo 권장)

Board 뷰에서 컬럼 헤더 옆 `⋯` → `Hide from view`.

- `Approved`: 1인 repo 에서는 외부 Approve 가 거의 없어 dead column 이 되기 쉽다.
- `Ready`: 현재 dotfiles flow 에서는 방문하지 않는 예약 컬럼이다.

## 5. 라이프사이클 (한눈에)

```text
Issue:
    Backlog ─[/gh-commit]──▶ In progress ─[PR open via Closes #N]──▶ In review ─[PR merge]──▶ Done

PR:
    Backlog ─[/gh-pr]──▶ In review ─[/gh-pr-reply or 외부 Approve]──▶ Approved ─[merge]──▶ Done
                            ▲                                            │
                            └────────────── [수동 재리뷰] ── In progress ◀─ [Changes requested]
```

## 6. 자동 vs 수동

- Issue `Backlog → In progress`:
  `/gh-flow`·`/gh-commit` 자동, raw `git commit` 사용 시 수동.
- PR `Backlog → In review`:
  `/gh-flow`·`/gh-pr` 자동, raw `gh pr create` 사용 시 수동.
- PR `In review → Approved`:
  `/gh-pr-reply` 자동, 또는 외부 협업자 Approve 시 built-in workflow 자동.
  1인 repo 에서는 self-approve 불가라 `/gh-pr-reply` 가 사실상 갭을 메운다.
- PR `In progress → In review`:
  `Changes requested` 루프 탈출 시 수동.
- 보드 미연결 repo:
  `_gh_project_status_sync` 가 `projectItems == 0` 을 감지하고 조용히
  return 0 한다. 호출자:
  `/gh-flow`, `/gh-pr`, `/gh-commit`, `/gh-pr-reply`.
- 그 외 상태 전환:
  GitHub Projects v2 built-in workflow 가 자동 처리한다.

## 7. 검증 (smoke test)

```bash
gh issue create --repo "$OWNER/$REPO" --title "[Test] kanban smoke" --body "ignore"
```

기대:

1. 수 초 내 보드 `Backlog` 컬럼에 새 카드가 생긴다.
2. 연결된 PR 생성 시 Issue 카드가 `In review` 로 이동한다.
3. PR merge 또는 issue close 후 카드가 `Done` 으로 이동한다.

## 8. References

- 본 playbook 출처 SSOT:
  [docs/standards/github-project-board.md](../standards/github-project-board.md)
- GitHub Projects v2 built-in automations:
  <https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations>
- 관련 skills (본 repo):
  `gh-issue-create`, `gh-commit`, `gh-pr`, `gh-pr-reply`,
  `gh-pr-merge`, `gh-issue-flow`
- 관련 헬퍼:
  `shell-common/functions/gh_project_status.sh`
  (공용 `_gh_project_status_sync` — `/gh-flow`, `/gh-pr`,
  `/gh-commit`, `/gh-pr-reply` 가 모두 호출)
- 관련 템플릿:
  `.github/pull_request_template.md`
- 자동화 스크립트:
  `scripts/setup-kanban-board.sh`
