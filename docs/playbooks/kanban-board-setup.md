# Kanban Board Setup Playbook

GitHub Projects v2 기반 단일 저장소 칸반보드를 30분 안에 셋업
하는 실행 가이드. AI 에이전트(예: Claude)에게 이 문서를 그대로
전달하고 "이 문서대로 칸반보드 구성해"라고 지시하면 end-to-end
자동화된다.

본 문서는 dotfiles repo의 SSOT(`docs/standards/github-project-board.md`)에서
**재사용 가능한 실행 절차만 발췌**한 playbook이다. 의사결정 맥락이
필요하면 SSOT 원본을 참고.

## 1. 목표 결과물

- Project v2 보드 1개, 특정 repo에 연결.
- Status 필드 6 옵션: `Backlog`, `Ready`, `In progress`, `In review`,
  `Approved`, `Done`.
- 10개 빌트인 워크플로우 중 9개 기본 `enabled`, `Auto-archive items`는
  기본 `disabled` — 본 playbook §4.5 필터 적용 후 수동 enable.
- **Issue 4단계**: `Backlog → In progress → In review → Done`.
- **PR 4단계**: `Backlog → In review → Approved → Done`
  (+ Changes requested 발생 시 `In progress`로 일시 루프).
- 개인 repo 사용 시 `Approved`·`Ready` 컬럼은 view-level hide 권장.

## 2. Prerequisites

```bash
gh auth refresh -s project
gh auth status   # Token scopes 에 'project' 가 포함돼야 함
```

## 3. 변수 (실행 전 export)

bash 코드 블록에서 `<PLACEHOLDER>` 형식은 쉘 리다이렉션으로 오해될
위험이 있어 모두 `$VAR` 형식으로 사용한다. 아래 블록을 먼저 실행해
세션에 변수를 export 해두고, 이후 섹션의 명령을 그대로 복사-실행.

```bash
export OWNER="dEitY719"           # GitHub user/org 슬러그
export REPO="my-project"          # 대상 저장소 이름
export PROJECT_TITLE="$REPO"      # 보드 제목 (대개 $REPO 와 동일)
```

`$PROJECT_ID`, `$PROJECT_NUMBER`, `$STATUS_FIELD_ID`는 4.1/4.2 에서
명령을 실행한 뒤 반환값으로 export 한다.

## 4. 셋업 단계

### 4.1 Project 생성

```bash
gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json
```

반환 JSON에서 다음 두 값을 export:

- `id` → `PROJECT_ID` (예: `PVT_xxx...`) → `export PROJECT_ID=PVT_xxx...`
- `number` → `PROJECT_NUMBER` (예: `3`) → `export PROJECT_NUMBER=3`

### 4.2 Status 필드 ID 조회

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

`name: "Status"` 인 필드의 `id` → `STATUS_FIELD_ID` export
(예: `export STATUS_FIELD_ID=PVTSSF_xxx...`)

### 4.3 Status 필드 옵션 6개로 교체

기본 옵션(`Todo / In Progress / Done` 3개)을 전면 교체한다.

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

### 4.4 PR 템플릿 생성

`.github/pull_request_template.md` 파일을 repo에 추가
(이미 있으면 `Closes #<N>` 자리표시자만 포함되면 됨):

```markdown
<!--
Closes #<N> 키워드가 반드시 포함되어야 Project 보드의 Done
자동 전환이 동작합니다. 이슈를 완전히 해결하지 않는 PR은
Closes 대신 Refs 를 사용하세요.
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

### 4.5 빌트인 워크플로우 설정 (웹 UI)

URL: `https://github.com/users/<OWNER>/projects/<PROJECT_NUMBER>/workflows`

(org 소유면 `/users/`를 `/orgs/`로 교체.)

신규 Project는 10개 워크플로우 중 `Auto-archive items`만 `disabled`,
나머지 9개는 `enabled` 상태로 생성된다. 아래 Status 값·필터만
확인·조정하면 된다.

| #  | 워크플로우                      | When                       | Set Status / Filter |
|----|---------------------------------|----------------------------|---------------------|
| 1  | `Auto-add to project`           | Filter: `is:issue,pr is:open` + repo: `<REPO>` | —          |
| 2  | `Item added to project`         | issues + pull requests     | `Backlog`           |
| 3  | `Pull request linked to issue`  | —                          | `In review`         |
| 4  | `Code review approved`          | —                          | `Approved`          |
| 5  | `Code changes requested`        | —                          | `In progress`       |
| 6  | `Pull request merged`           | —                          | `Done`              |
| 7  | `Item closed`                   | issues + pull requests     | `Done`              |
| 8  | `Auto-close issue`              | — (구조적; 기본 유지)       | (Status 미설정)     |
| 9  | `Auto-add sub-issues to project`| — (구조적; 기본 유지)       | (Status 미설정)     |
| 10 | `Auto-archive items`            | Filter 매칭 카드 주기적 archive | **수동 enable** + Filter: `is:issue,pr is:closed updated:<@today-2d` |

**#10 `Auto-archive items` 설정 상세**:

- 기본 disabled — 명시적으로 enable 해야 한다.
- Filter 문법은 Issue/PR search query 문법을 따른다:
  - `is:issue,pr` — Issue·PR 카드 모두 (Option B 운영 전제)
  - `is:closed` — 닫힌(=머지된) 카드만. 본 문서 라이프사이클에서
    Done 컬럼과 동치.
  - `updated:<@today-2d` — 그제(2일 전) 자정 이전에 업데이트된
    카드. 기간은 운영 취향에 따라 `<@today` (당일분만), `<@today-1w`
    (1주분) 등으로 조정. dotfiles는 `<@today-2d` 채택 (Done 컬럼을
    최근 2일분만 유지하여, 어제 머지된 카드도 오늘 시점에 보드
    상에서 즉시 확인 가능).
- archive 된 카드는 삭제가 아니라 기본 뷰에서 숨김 — 필터 바에
  `is:archived` 입력 시 재조회, 카드 우클릭 `Restore from archive`로
  복원 가능.

### 4.6 `Approved`·`Ready` 컬럼 hide (solo repo 권장)

개인 repo에서는 다음 두 컬럼이 라이프사이클에서 방문되지 않아
dead column이 된다. Board 뷰에서 컬럼 헤더 옆 `⋯` →
`Hide from view`로 숨긴다.

- **`Approved`**: `Code review approved` 워크플로우가 거의 발화하지
  않아 PR 카드가 도달하지 않음.
- **`Ready`**: Issue·PR 두 라이프사이클 모두 방문하지 않는 예약
  컬럼 (미래 확장용). SSOT §컬럼별 의미 참고.

- 중요: 이는 **view-level 설정**이며 Status 옵션 자체는 유지된다.
  따라서 카드가 해당 컬럼에 들어가는 일이 생기면(예: 협업자 합류로
  Approved 발화, 또는 Ready 단계 도입) 데이터는 건재하고, hide만
  해제하면 즉시 가시화된다.

## 5. 라이프사이클 (한눈에)

```
Issue:
    Backlog ─[/gh-commit]──▶ In progress ─[PR open via Closes #N]──▶ In review ─[PR merge]──▶ Done

PR:
    Backlog ─[/gh-pr]──▶ In review ─[Approve]──▶ Approved ─[merge]──▶ Done
                            ▲                        │
                            └─ [수동 재리뷰] ── In progress ◀─ [Changes requested]
```

`/gh-flow`, `/gh-pr`, `/gh-commit` 가 호출되면 위 두 진입 전환은
자동으로 발생한다 (보드가 없는 repo 에서는 헬퍼가 자동으로 no-op).
raw `git commit` / `gh pr create` 를 직접 사용하는 경로에서만 수동
이동이 필요하다.

## 6. 자동 vs 수동

- **Issue `Backlog → In progress`**: `/gh-flow`·`/gh-commit` 자동 /
  raw `git commit` 사용 시 수동. `/gh-commit` 은 `--only-from Backlog`
  가드를 사용하므로 PR 오픈 후 follow-up 커밋은 역행시키지 않는다.
- **PR `Backlog → In review`**: `/gh-flow`·`/gh-pr` 자동 /
  raw `gh pr create` 사용 시 수동.
- **PR `In progress → In review`**: 수동 (Changes requested 루프
  탈출 시 — 자동화 미지원).
- **보드 미연결 repo**: 헬퍼 (`_gh_project_status_sync`) 가
  `projectItems` 가 0건이면 조용히 return 0 — 즉 `dotfiles` 외 다른
  프로젝트에서 `/gh-pr`·`/gh-commit` 을 써도 부작용이 없다.
- 그 외 모든 전환: 자동 (GitHub Projects v2 빌트인 워크플로우).

## 7. 검증 (smoke test)

```bash
# Test issue 생성
gh issue create --repo "$OWNER/$REPO" --title "[Test] kanban smoke" --body "ignore"
```

기대:

1. 수 초 내 보드 `Backlog` 컬럼에 새 카드 등장.
2. `gh issue close <N>` 후 카드가 `Done`으로 이동.
3. 확인 후 이슈 삭제: `gh issue delete <N>` (대화형).

## 8. Gotchas

- Free plan private repo는 branch protection API가 HTTP 403을 반환한다.
  merge에는 지장 없으나 `gh-pr-merge` 등 skill이 protection 존재 여부로
  분기할 수 있다는 점만 기억.
- PR 본문에 `Closes #N`이 빠지면 Issue 카드가 `Done`으로 가지 않는다.
  PR 템플릿으로 강제 + 머지 전에 본문 재확인.
- `Auto-add to project`의 필터 `is:issue,pr`은 GitHub Projects v2
  공식 지원 문법(콤마 복수 지정). 일부 봇이 "미지원"이라 주장해도
  실제로는 정상 동작.
- `Approved` 컬럼 hide는 본인의 view에만 적용된다. 다른 뷰/협업자
  화면에는 보임.

## 9. References

- 본 playbook 출처 SSOT: [docs/standards/github-project-board.md](../standards/github-project-board.md)
- GitHub Projects v2 빌트인 automations:
  <https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations>
- 관련 skills (본 repo): `gh-issue-create`, `gh-commit`, `gh-pr`,
  `gh-pr-merge`, `gh-pr-reply`, `gh-issue-flow`.
- 관련 헬퍼: `shell-common/functions/gh_project_status.sh`
  (공용 `_gh_project_status_sync` — `/gh-flow`, `/gh-pr`,
  `/gh-commit` 이 모두 호출).
