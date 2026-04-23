# gh Skills Expansion Design

## Overview

기존에 만족도 높게 사용 중인 `gh:` 접두어 스킬군(gh:commit, gh:issue,
gh:pr, gh:pr-approve, gh:pr-merge-emergency, gh:pr-reply)에 이슈 기반
워크플로와 PR 머지 스킬을 추가한다.

**목표**:
- 이슈를 읽고 → 이해하고 → 구현하고 → PR 을 머지하기까지의 흐름을
  기존 원자 스킬 패턴을 유지하며 커버.
- 얇은 합성 스킬(composition skill) 패턴을 도입해 여러 원자 스킬을
  조합하는 방식을 표준화.

**비목표**:
- 기존 스킬의 내부 로직 변경 (gh:commit, gh:pr 는 그대로 사용).
- Agent 시스템 도입 (합성 스킬로 충분).

## Scope

### 추가/변경되는 스킬 (5개)

| 타입 | 이름 | 상태 |
|---|---|---|
| 원자 (rename) | `gh:issue-create` | 기존 `gh:issue` 리네임 |
| 원자 (신규) | `gh:issue-read` | 이슈 요약 |
| 원자 (신규) | `gh:issue-implement` | 이슈 → 구현 |
| 원자 (신규) | `gh:pr-merge` | approved PR 3전략 머지 |
| 합성 (신규) | `gh:issue-flow` | issue-implement → commit → pr 체인 |

### 영향받지 않는 스킬
`gh:commit`, `gh:pr`, `gh:pr-approve`, `gh:pr-merge-emergency`,
`gh:pr-reply` — 로직 변경 없음. 단, `gh:issue-flow` 가 `gh:commit`/`gh:pr`
를 호출하는 하류 의존성이 생김.

## 공통 설계 (모든 신규 스킬)

기존 `gh:` 스킬 패턴을 그대로 따른다:

- **디렉토리**: `claude/skills/<hyphenated-name>/`
  (예: `claude/skills/gh-issue-read/`)
- **Frontmatter `name:`**: 콜론 형식 `gh:foo`
  (예: `name: gh:issue-read`) — SSOT 컨벤션(MEMORY.md 참조)
- **`allowed-tools`**: `Bash, Read, Grep` 기본 (Glob 필요 시 추가).
  `gh:issue-implement` 는 `Edit, Write` 추가 필요.
- **`-h`/`--help`/`help`** 지원 → `references/help.md` verbatim 출력 후 stop.
- **Progressive Disclosure**: SKILL.md ~100줄 이내, 상세는 `references/`.
- **언어**: 사용자가 한국어로 대화 중이면 한국어 출력.
- **Target repo 해석**: arg 로 remote 받기 (default `origin`).
  없는 remote → `git remote -v` 리스트 출력 후 stop. 절대 silent fallback 금지.
- **최종 출력**: URL·번호 등 최소 정보. 서문/요약 금지.
- **Repo SSOT**: `~/dotfiles/claude/skills/` 에 작성.
  `~/.claude/skills/` 는 downstream 심볼릭 링크.

## 1. `gh:issue-create` (rename)

**변경 사항**: `claude/skills/gh-issue/` → `claude/skills/gh-issue-create/`.
Frontmatter `name: gh:issue` → `name: gh:issue-create`.
로직·references 내용 변경 없음.

**이유**: 신규 `gh:issue-read`, `gh:issue-implement` 와 함께 동사
(create/read/implement) 대칭이 생기고, "이슈 생성" 의미가 이름에서 명확.

**호환성**:
- 구버전 명령 `/gh:issue` 는 rename 후 동작하지 않음 (일회성 전환).
- 사용자가 혼자 쓰는 스킬이므로 deprecation alias 불필요.

## 2. `gh:issue-read` (신규)

### 목적
이슈 #N 을 fetch 해서 구조화된 요약을 출력. 구현 전 상황 파악용.

### 입력
```
/gh:issue-read <issue-number> [remote]
/gh:issue-read -h | --help | help
```

### 동작
1. Repo context 해석 (`origin` default).
2. `gh issue view <N> --repo $TARGET_REPO --json ...` 로 이슈 데이터 수집
   (title, body, author, labels, state, comments, assignees, createdAt,
   updatedAt).
3. 본문과 코멘트를 **압축하지 않고** 구조화하여 출력.
4. 다음 섹션 포함:
   - **Header**: `#N <title> by @author (state, labels)`
   - **Summary**: 이슈가 요구하는 것이 무엇인지 2-4줄.
   - **Body** (원문 그대로, 코드블록 유지)
   - **Discussion** (코멘트 시간순, 작성자·타임스탬프 포함)
   - **Meta**: created/updated, assignees, linked PRs 가 있으면 링크
5. 액션/결정/수락 조건이 명시돼 있으면 끝에 **Checklist** 섹션으로 추출.

### 비목적
- 이슈 상태 변경 (close/label 등) — `gh issue` 직접 쓰면 됨.
- PR 링크까지 자동 follow — 이슈 자체에 집중.

### 에러 케이스
- 이슈 없음 → `gh` 표준 에러 그대로 전달 후 stop.
- Private repo 접근 실패 → `gh auth status` 확인 안내.

## 3. `gh:issue-implement` (신규)

### 목적
이슈 #N 을 읽고 해당 요구사항을 코드로 구현. 테스트 실행까지.
**커밋·PR 은 하지 않음** (원자성 유지).

### 입력
```
/gh:issue-implement <issue-number> [mode] [remote]
/gh:issue-implement <issue-number>                  # mode=direct (default)
/gh:issue-implement <issue-number> plan
/gh:issue-implement <issue-number> brainstorming
/gh:issue-implement -h | --help | help
```

`mode`:
- `direct` (default) — 이슈 fetch → 관련 파일 탐색 → 바로 구현 → 테스트 실행.
  사람 개입 없음. 이게 `gh:issue-flow` 의 happy path 를 가능하게 함.
- `plan` — `superpowers:writing-plans` 스킬 invoke → plan 문서 작성 →
  사용자 승인 → 구현 → 테스트. 단, 아래 승격 조건 중 하나라도 만족하면
  **자동으로 `brainstorming` 으로 승격**:
  - 이슈 본문이 200자 미만 또는 body 가 비어 있음.
  - 액션 동사(추가/수정/삭제/구현/변경/fix) 가 title·body 에 없음.
  - "어떻게 할지 상의" / "논의 필요" / "아이디어" 등 설계 합의 요청 표현.
  - 상반되는 요구사항이 코멘트 간에 있음 (예: 어떤 코멘트는 A, 다른
    코멘트는 not-A).
- `brainstorming` — `superpowers:brainstorming` invoke → 설계 합의 →
  plan → 구현 → 테스트.

### superpowers 미설치 fallback
- **감지 방법**: `~/.claude/plugins/cache/superpowers-dev/` 경로 존재 확인.
  없으면 superpowers 플러그인 미설치로 판단.
- **동작**: `plan`/`brainstorming` mode 가 지정돼도 **무조건 `direct` 로 실행**.
  스킬 시작 시 1줄 경고:
  ```
  ⚠️  superpowers plugin not installed — falling back to direct mode.
  ```
- **이유**: 스킬이 팀원들 사이에서 공유되는데 각자 환경이 다름. 의존성
  결핍으로 스킬이 완전히 실패하는 것보다 기능 degradation 이 나음.

### 동작 (direct mode)
1. 선행 조건 검증:
   - Git repo 안인지 (`git rev-parse --show-toplevel`).
   - Base branch 가 아닌지 (현재 branch == default branch 면 stop.
     "feature branch 부터 만드세요" 안내). 사용자의 feedback 규칙 준수.
   - Working tree clean 인지 (dirty 면 stop + 확인).
2. `gh:issue-read` 와 동일 방식으로 이슈 fetch (내부 invoke 는 하지 않고
   로직만 재사용 — 둘 다 `gh issue view` 호출).
3. 이슈 본문·코멘트·연결된 파일 경로 추출. 프로젝트 구조 탐색 (기존
   AGENTS.md, CLAUDE.md 가 있으면 읽음).
4. 편집·생성 필요한 파일 식별 → Edit/Write.
5. 테스트 실행:
   - `tox`, `pytest`, `bats`, `npm test` 등 프로젝트의 표준 테스트
     러너 자동 탐지 (AGENTS.md, `pyproject.toml`, `package.json`,
     `tox.ini` 순으로 확인).
   - **실패 시 수정 루프** (최대 3회): 실패 출력 읽기 → 원인이 자신의
     편집인지 판별 → 해당 파일만 재편집 → 테스트 재실행. 3회 후에도
     실패면 stop + 진행 상태·남은 실패 테스트·마지막 편집 diff 를
     리포트. 기존 테스트가 원래부터 실패하던 경우(스킬 호출 전 상태)는
     고치지 않고 "pre-existing failure" 로 분리 리포트.
6. 최종 report: 변경 파일 목록 + 테스트 결과 + 다음 단계 힌트.

### 출력 예시
```
gh:issue-implement #16 complete
  Changes:
    claude/skills/gh-issue-read/SKILL.md  (new)
    claude/skills/gh-issue-read/references/help.md  (new)
  Tests: 12 passed, 0 failed
  Next: /gh:commit && /gh:pr
```

### 비목적
- 커밋·PR 생성. (`gh:issue-flow` 에서 체이닝.)
- Worktree 생성. (사용자가 사전에 `gwt` 로 생성 후 스킬 호출하는 흐름.)

## 4. `gh:pr-merge` (신규)

### 목적
Approved + mergeable 상태의 PR 을 지정된 전략으로 머지. GitHub 웹의
"Rebase and merge" / "Squash and merge" / "Create a merge commit"
3개 버튼에 대응.

### 입력
```
/gh:pr-merge <pr-number> [strategy] [remote]
/gh:pr-merge <pr-number>                       # strategy=rebase (default)
/gh:pr-merge <pr-number> rebase|squash|merge
/gh:pr-merge -h | --help | help
```

### 동작
1. Args parse. `strategy` default `rebase`. Invalid 값 → usage 출력 후 stop.
2. Pre-flight (병렬 fetch, confirm 없음):
   - PR JSON: `number, state, isDraft, mergeable, mergeStateStatus,
     reviewDecision, baseRefName, headRefName, author`.
   - `gh pr checks <N>`.
3. **Hard stops**:
   - `state != OPEN` → "already closed/merged".
   - `isDraft == true` → "draft PR".
   - `mergeable == CONFLICTING` → "resolve conflicts first".
   - `reviewDecision != APPROVED` → "not approved yet — `gh:pr-merge-emergency`
     를 쓰세요" 로 안내.
   - 필수 체크 중 실패/pending → stop.
4. `gh pr merge <N> --repo $TARGET_REPO --<strategy> --delete-branch`
   **확인 프롬프트 없이 즉시 실행**. 실패 시 gh 에러 메시지 그대로 전달.
5. 머지 후 `gh pr view <N> --json mergeCommit -q .mergeCommit.oid`
   로 머지 SHA 확인.

### 출력
```
PR #<N> merged (<strategy>)
  Merge SHA:  <sha>
  Branch:     <head> → <base> (deleted)
  URL:        https://github.com/owner/repo/pull/<N>
```

### 전략 선택 근거
- Default `rebase` — 사용자가 평소 GitHub 웹에서 누르는 버튼이
  "Rebase and merge" 이므로 일관.
- `squash`·`merge` 는 명시적 인자로만. 실수 방지.

### `gh:pr-merge-emergency` 와의 역할 분담
- `gh:pr-merge` — **approved 일 때만** 머지. 요구사항 전부 만족되어야 함.
- `gh:pr-merge-emergency` — approval 우회용 (admin bypass + audit).
  본 스킬이 approval 요구하고 거절하면 그 쪽으로 넘어가는 흐름이 의도됨.

## 5. `gh:issue-flow` (신규, 합성 스킬)

### 목적
`gh:issue-implement` → `gh:commit` → `gh:pr` 세 스킬을 순차 호출하는
얇은 오케스트레이터. "이슈 번호만 주면 PR 링크가 나온다" 가 happy path.

### 입력
```
/gh:issue-flow <issue-number> [remote]
/gh:issue-flow -h | --help | help
```

`mode` 인자는 **받지 않음** — 합성 스킬은 항상 `gh:issue-implement` 를
default (direct) 로 호출. 이유: happy path 단일화. plan/brainstorming
워크플로가 필요하면 원자 스킬을 수동 호출.

### 동작
1. Args parse + repo context 해석 (issue-number, remote).
2. Skill tool 로 체인 호출:
   ```
   Step 1: Skill(gh:issue-implement, "<N> [remote]")
   Step 2: Skill(gh:commit)        # step 1 성공 시에만
   Step 3: Skill(gh:pr <N>)        # step 2 성공 시에만
                                    # 이슈 번호를 PR 링크로 넘겨
                                    # "Closes #N" 자동 포함
   ```
3. 각 단계 완료 후 체크 표시. 실패하면 **즉시 stop** (재시도 안 함).
4. 최종 리포트 출력.

### 실패 처리 (approved)
- 중간 실패 시 `(a) 즉시 중단 + 상태 리포트`. 재시도·자동 복구 없음.
- 각 원자 스킬이 자체 에러 report 를 내므로 flow 는 전달만 함.

### 출력 — 성공
```
gh:issue-flow complete (#<N>)
  ✓ Step 1: gh:issue-implement  (tests passed, 2 files changed)
  ✓ Step 2: gh:commit            (abc1234 "feat(x): ...")
  ✓ Step 3: gh:pr                (PR #51)
  PR URL: https://github.com/owner/repo/pull/51
```

### 출력 — 실패
```
gh:issue-flow stopped at step 2/3 (gh:commit)
  ✓ Step 1: gh:issue-implement  (tests passed)
  ✗ Step 2: gh:commit            (pre-commit hook failed: shellcheck)
  ⊘ Step 3: gh:pr                (not reached)

Resume after fix:
  /gh:commit && /gh:pr
```

### Help 명시 요구사항
사용자 요청에 따라, `-h`/`--help`/`help` 출력에 다음을 **명시**:
> 이 스킬은 다음 3개의 스킬을 순차 호출합니다:
> 1. gh:issue-implement
> 2. gh:commit
> 3. gh:pr
>
> 각 단계는 앞 단계가 성공했을 때만 실행됩니다.

## 디렉토리 구조 최종

```
claude/skills/
├── gh-commit/                 (변경 없음)
├── gh-issue-create/           (기존 gh-issue/ 리네임)
│   ├── SKILL.md               (name: gh:issue-create 로 수정)
│   └── references/...
├── gh-issue-flow/             (신규)
│   ├── SKILL.md
│   └── references/
│       └── help.md
├── gh-issue-implement/        (신규)
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       ├── implementation-flow.md
│       └── superpowers-detection.md
├── gh-issue-read/             (신규)
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       └── output-format.md
├── gh-pr/                     (변경 없음)
├── gh-pr-approve/             (변경 없음)
├── gh-pr-merge-emergency/     (변경 없음)
├── gh-pr-merge/               (신규)
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       └── strategy-selection.md
└── gh-pr-reply/               (변경 없음)
```

## 테스트 전략

현재 `claude/skills/` 에 테스트 프레임워크가 없으므로, 스킬 자체의
자동 테스트는 범위 밖. 대신 수동 smoke test 체크리스트를 spec 에 포함:

1. **`gh:issue-create` rename**: 기존 `/gh:issue` 호출 경로가 끊기는지,
   `/gh:issue-create` 가 동일 결과를 내는지.
2. **`gh:issue-read`**: 공개된 실제 이슈(예: `dEitY719/dotfiles#N`)로
   요약 품질 확인.
3. **`gh:issue-implement` direct**: 간단한 docs-only 이슈로 시도 →
   파일 생성·테스트 통과 확인.
4. **`gh:issue-implement` plan**: superpowers 설치된 환경에서
   writing-plans 체인 동작 확인.
5. **`gh:issue-implement` fallback**: superpowers 디렉토리 임시
   이름변경 후 `plan` 지정 → direct 로 떨어지는지 + 경고 출력 확인.
6. **`gh:pr-merge`**: 테스트용 PR 을 만들어 rebase 로 머지, squash 로
   머지, merge 로 머지 각각 확인.
7. **`gh:pr-merge` 거절 경로**: approved 아닌 PR → 거절 + emergency-merge
   안내 확인.
8. **`gh:issue-flow` happy path**: 이슈 하나로 처음부터 끝까지 PR 까지.
9. **`gh:issue-flow` 실패 경로**: 의도적으로 test 가 실패하는 이슈로
   step 1 stop 리포트 확인.

## 롤아웃 순서

단일 PR 로 묶되, 커밋은 스킬 단위로 분리하면 리뷰가 수월:

1. `feat(skill): rename gh:issue to gh:issue-create`
2. `feat(skill): add gh:issue-read`
3. `feat(skill): add gh:pr-merge`
4. `feat(skill): add gh:issue-implement`
5. `feat(skill): add gh:issue-flow composition skill`

Branch: `wt/feat/1` (이미 생성됨).
