# GitHub 라벨 SSOT

## 목표

dotfiles 저장소를 포함한 임의의 GitHub repo 에 적용할 **10개 핵심
라벨**의 name/color/description 을 확정한다. 이 문서는 dotfiles 라벨
체계의 SSOT 이며, `gh:label-bootstrap` 스킬이 이 문서의 **plain feed**
블록을 직접 읽어 대상 repo 의 라벨을 동기화한다. 라벨 이름/색상/설명을
바꿔야 하면 이 문서만 고치면 되고, 스킬은 두 번째 하드코딩 사본을 두지
않는다.

## 적용 범위

- 대상: 이 저장소 및 다른 프로젝트(재사용형) — origin/upstream 양쪽.
- 소비자: `gh:label-bootstrap` (동기화 실행), `gh:kanban-bootstrap`
  (보드 셋업 중 라벨 부트스트랩 위임), `gh:issue-create`
  (`.gh-issue-defaults.yml` 매핑), `gh:issue-implement`
  (`reference` 라벨 차단), `gh:pr` (커밋타입 → 라벨 매핑).
- 범위 밖: `CI fail`(`gh:pr-resolve-ci-fail`), `conflict`
  (`gh:pr-resolve-conflict`) 등 별개 라벨 체계는 건드리지 않는다.

차용 근거 / 설계 논의: issue #1226.

## 확정 10개 라벨

| name | color | description |
|---|---|---|
| `feat` | `fbca04` | 신규 기능 또는 개선 (perf 흡수) |
| `fix` | `d73a4a` | 버그 수정 (구 `bug` 대체) |
| `docs` | `0075ca` | 문서 변경 (구 `documentation` 대체) |
| `refactor` | `8250df` | 동작 보존하며 구조 정리 |
| `test` | `2da44e` | 테스트 갭/추가/변경 (TDD red-green-blue의 green) |
| `ci` | `1d76db` | CI / GitHub Actions |
| `chore` | `bfbfbf` | 빌드·도구·deps·스타일 (구 `build` 대체) |
| `skill` | `d97757` | `claude/skills/**` 변경 (Claude 브랜드 컬러) |
| `TODO` | `d33cb5` | 처리 대기 항목 |
| `reference` | `0e8a8a` | 구현 불필요/참고용 — `gh:issue-implement`가 구현을 시작하지 않는 트리거 |

색상은 `#` 없이 6자리 hex 로 적는다 — GitHub label API (`POST`/`PATCH
/repos/{repo}/labels`) 가 `#` 없는 형식을 받고, 아래 plain feed 도 같은
형식을 쓴다.

## Alias 매핑 (rename 대상)

기존 이름이 대상 repo 에 존재하면 **삭제·재생성이 아니라 rename**
(`PATCH /repos/{repo}/labels/{old} -f new_name={new}`) 으로 처리한다 —
delete+recreate 는 이미 그 라벨을 달고 있는 모든 issue/PR 에서 라벨이
떨어져 나가므로 채택하지 않는다. rename 시 color/description 도 같은
호출에서 신규 SSOT 값으로 동기화한다.

| 기존 이름 (old) | 신규 이름 (new) |
|---|---|
| `bug` | `fix` |
| `documentation` | `docs` |
| `build` | `chore` |

기존 이름이 대상 repo 에 **없으면** rename 을 건너뛰고 신규 이름을 그냥
POST 한다 (에러 아님). 신규 이름이 이미 있으면 다른 SSOT 라벨과
동일하게 PATCH 로 동기화한다 (멱등).

## Prune allowlist (항상 보존)

GitHub 기본 제공 라벨은 삭제 후보에서 제외한다:

`enhancement`, `duplicate`, `good first issue`, `help wanted`,
`invalid`, `question`, `wontfix`

(alias 로 사라지는 `bug`/`documentation`/`build` 는 rename 후 자연히
없어지므로 allowlist 에 넣을 필요가 없다.)

## Prune 판정 원칙

- `--prune` 는 **기본 off** — 지정하지 않으면 어떤 라벨도 삭제되지
  않는다 (후보 나열 같은 부수효과도 없다). 라벨 삭제는 항상 opt-in 이다.
- `--prune` 지정 시, 다음 합집합에 **없는** 라벨만 삭제 후보다:
  (SSOT 10개) ∪ (alias 신규 이름 `fix`/`docs`/`chore`) ∪
  (prune allowlist 7종).
- 판정은 **alias rename 을 먼저 적용한 뒤의 최종 label 셋 기준**으로
  한다. 그래야 `bug` 같은 rename 대상이 (이미 `fix` 가 된 상태라)
  삭제 후보로 오판되지 않는다.

## 권한 부족 처리

대상 repo 에 write 권한이 없으면 (fork, readonly token 등) 해당 라벨
작업만 per-label stderr 경고를 남기고 다음 라벨로 계속한다 — 라벨 하나의
실패가 전체 실행을 중단시키지 않는다.

## Plain feed (스킬이 직접 파싱)

`gh:label-bootstrap` 의 `lib/label-bootstrap.sh` 가 아래 두 블록을
정규식으로 뽑아 쓴다. 표(위)와 값이 어긋나면 안 되므로 이 블록이 유일한
기계 판독 소스다.

### 10개 라벨 (`name|color|description`)

```
feat|fbca04|신규 기능 또는 개선 (perf 흡수)
fix|d73a4a|버그 수정 (구 bug 대체)
docs|0075ca|문서 변경 (구 documentation 대체)
refactor|8250df|동작 보존하며 구조 정리
test|2da44e|테스트 갭/추가/변경 (TDD red-green-blue의 green)
ci|1d76db|CI / GitHub Actions
chore|bfbfbf|빌드·도구·deps·스타일 (구 build 대체)
skill|d97757|claude/skills/** 변경 (Claude 브랜드 컬러)
TODO|d33cb5|처리 대기 항목
reference|0e8a8a|구현 불필요/참고용 — gh:issue-implement가 구현을 시작하지 않는 트리거
```

### Alias 매핑 (`old|new`)

```
bug|fix
documentation|docs
build|chore
```

## Related

- 스킬: `claude/skills/gh-label-bootstrap/SKILL.md`
- 보드 SSOT: `docs/.ssot/github-project-board.md`
- 소비 설정: `.gh-issue-defaults.yml`
- 소비 스킬: `claude/skills/gh-issue-implement/references/claim.md`
  (`GH_ISSUE_BLOCK_LABELS` 에 `reference` 포함),
  `claude/skills/gh-pr/references/pr-body-template.md` (커밋타입 매핑)
- 설계 논의: issue #1226
