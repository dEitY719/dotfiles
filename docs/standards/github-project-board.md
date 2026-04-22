# GitHub Project 칸반 보드 워크플로우

## 목표

dotfiles 저장소의 모든 작업을 단일 칸반 보드에서 추적한다.
이 문서는 `dEitY719/dotfiles`의 GitHub Project v2 보드 운영 규칙의
SSOT이다.

## 적용 범위

- 저장소: `dEitY719/dotfiles` (repo-level project)
- 카드 종류: Issue만 (PR은 제외)
- 자동화 수단: GitHub Projects v2 빌트인 워크플로우 (별도 Action 없음)
- 관련 스킬: `gh:issue-create`, `gh:pr`, `gh:pr-merge`, `gh:issue-flow`

차용 원본: `skill-hub`의 `.claude/workflow.md`와 `github-integration.md`.
dotfiles는 동일 원칙을 따르되 범위(단일 repo)와 자동화 수준(빌트인만)
측면에서 최소화한 변형을 사용한다.

## 보드 구조

### 컬럼 (Status 필드)

```
Backlog -> Ready -> In progress -> In review -> Approved -> Done
```

### 컬럼별 의미

| 컬럼        | 의미                                          |
|-------------|-----------------------------------------------|
| Backlog     | 아이디어/요청만 등록된 상태                   |
| Ready       | 요구사항이 정리되어 누군가 집어가도 되는 상태 |
| In progress | 작업 중 (브랜치 생성됨, 커밋 진행 중)         |
| In review   | PR 생성됨, 리뷰 대기                          |
| Approved    | 리뷰 승인됨, 머지 대기                        |
| Done        | 머지 완료, Issue 닫힘                         |

## 카드 정책 (Open Question #1 결정)

**결정: Issue 카드만 등록한다 (Option A)**.

- 보드에는 Issue 카드만 존재하며, 관련 PR은 Issue 카드의
  "linked PR" 배지로 표시된다.
- Issue = 작업 단위 (SSOT), PR = 구현 단위. 1:N 대응이므로
  보드의 SSOT는 항상 Issue로 유지한다.
- 트레이드오프: PR 자체의 진행 상태(`In review` vs `Approved`)는
  보드에서 직접 보이지 않는다. 승인 여부는 CLI로 확인한다:
  `gh pr view <N> --json reviewDecision`.

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

GitHub Projects v2의 빌트인 워크플로우 세 개만 활성화한다.

| 전환 시점         | From        | To      | 트리거                                                       |
|-------------------|-------------|---------|--------------------------------------------------------------|
| Issue 등록        | —           | Backlog | `gh issue create` (Auto-add workflow)                        |
| PR 생성 (리뷰 대기) | Backlog/Ready | In review | PR 본문의 `Closes #N`으로 GitHub이 Issue를 PR에 linked로 추가 |
| PR 머지 → Done    | In review   | Done    | PR 머지 시 `Closes #N` 키워드로 Issue가 자동 close → Item closed workflow |

`Ready`, `In progress`, `Approved`는 **수동 이동**한다.
빌트인 워크플로우만으로는 커버하지 못하는 중간 상태이므로
작업자가 보드 UI에서 직접 옮긴다.

- `Backlog -> Ready`: 이슈 분석이 끝나고 구현 준비가 됐을 때.
- `Ready -> In progress`: 브랜치를 생성하고 작업을 시작할 때.
- `In review -> Approved`: 리뷰가 승인됐을 때
  (`gh pr view <N> --json reviewDecision`으로 확인한 뒤).

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

4. 저장소 연결 및 빌트인 워크플로우 활성화
   (Project 설정 > Workflows):
   - `Auto-add to project`: `dEitY719/dotfiles` 저장소의
     open Issue를 자동으로 `Backlog`에 추가.
   - `Item closed`: Issue가 close되면 카드를 `Done`으로 이동.

## 운영 상의 유의사항

- PR 본문에 `Closes #N`이 빠지면 머지 후에도 Issue가 열려 있고
  카드가 `Done`으로 가지 않는다. PR 템플릿과 `gh:pr` 스킬이
  이를 방지하지만, 사람이 수동으로 본문을 지울 경우를 대비해
  머지 전에 한 번 더 확인한다.
- 카드를 웹 UI에서 수동으로 옮긴 경우, 다음 자동 이벤트가 오면
  상태가 덮어써질 수 있다. 수동 이동은 `Ready`, `In progress`,
  `Approved`에만 사용한다 — 이 셋은 자동화가 건드리지 않는다.
- Project 보드 쿼리는 CLI로도 가능하다:
  ```bash
  gh project item-list <PROJECT_NUM> --owner dEitY719 --format json
  ```

## References

- 차용 원본: `skill-hub`의 `.claude/workflow.md` (60-68번 줄)와
  `.claude/github-integration.md` (Project 보드 상태 전환 정책).
- GitHub Projects v2 빌트인 워크플로우:
  <https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations>
- 관련 Issue: #169 (본 문서의 도입 근거).
- 관련 스킬:
  - `claude/skills/gh-issue-create/SKILL.md`
  - `claude/skills/gh-pr/SKILL.md`
  - `claude/skills/gh-pr-merge/SKILL.md`
  - `claude/skills/gh-issue-flow/SKILL.md`
- 관련 템플릿: `.github/pull_request_template.md`.
