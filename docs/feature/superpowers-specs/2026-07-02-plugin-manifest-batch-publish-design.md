# claude/plugin/publish-sync.sh — 매니페스트 배치 publish 설계

## 배경

PR #1069(`claude/hooks/plugin-sync.sh`)는 `claude plugin install/uninstall`,
`marketplace add/remove`를 PostToolUse 훅으로 감지해 `claude/plugin/*.json`
(공용) / `claude/plugin/company/*.json`(사내 전용, 별도 GHES private repo)을
갱신하고 **로컬 커밋**까지 자동으로 한다. 이슈 #1070, #1072를 거치며 로컬
커밋 자체는 `main`에서도 정상 동작한다(`ALLOW_MAIN_COMMIT=1`로 로컬
`pre-commit`의 protected-branch 가드를 우회).

문제는 그 다음 단계다: dotfiles 공용 레포(github.com)에는 `refs/heads/main`에
대해 **"변경은 반드시 PR을 통해서만" + "필수 status check 2개"**를 요구하는
서버사이드 ruleset이 걸려 있다. 로컬 `pre-commit`의 escape hatch는 로컬
훅에만 통하고 이 서버 ruleset과는 무관하므로, `git push origin main` 직접
push는 항상 `GH013: Repository rule violations`로 거부된다. 결과적으로
`chore(claude-plugin): sync manifest` 커밋들이 로컬 `main`에 계속 쌓이기만
하고 원격에 못 올라간다 — `restore.sh`가 신규 PC에서 참조하는 것도
결국 origin의 내용이므로, 이 상태로는 배치 기능의 최종 목적(신규 PC 일괄
복원)이 완성되지 않는다.

## 목표

- 로컬에 쌓인 매니페스트 변경분을 origin(및 사내 GHES private repo)에
  **PR을 거쳐** 반영한다 — ruleset을 우회하지 않고 정공법으로 통과시킨다.
- 매번 사람이 브랜치 파고 PR 올리고 머지하는 수고를 없앤다 — 명령 하나로
  끝나게 한다.
- `plugin-sync.sh`(PostToolUse 훅)는 건드리지 않는다 — 훅은 계속 "빠르게,
  항상 exit 0, 네트워크 I/O 없이"라는 기존 설계 원칙을 유지한다. push/PR
  생성처럼 느리고 실패 가능한 작업은 훅 밖의 별도 도구로 분리한다.

## 비목표

- 자동 스케줄링(cron 등)은 이번 스코프에 넣지 않는다 — 사용자가 명시적으로
  선택한 트리거 방식은 "수동 실행"이다 (아래 참조).
- `plugin-sync.sh`의 매니페스트 분류 로직(공용 vs 사내) 자체는 이 설계의
  대상이 아니다 — 이미 검증 완료된 것으로 간주한다(2026-07-01 설계 문서
  Open Questions 항목 참조: GHES 전체 URL로 추가한 마켓플레이스는
  `source.source == "git"`로 기록되어 사내 전용으로 정확히 분류됨).

## 트리거

**수동 실행 전용.** Claude 스킬이 아니라 `claude/plugin/restore.sh`와
동일한 관례를 따르는 독립 셸 스크립트 — 사용자가 필요할 때 셸에서 직접
실행한다:

```bash
./claude/plugin/publish-sync.sh          # 실제 publish
./claude/plugin/publish-sync.sh --dry-run  # 무엇을 할지만 출력, 변경 없음
```

`claude-help plugin` 섹션(`shell-common/functions/ai_tools_help.sh`)에
`restore.sh`와 나란히 등록한다.

## 핵심 아이디어: 커밋을 고르지 않고 "최종 상태"만 옮긴다

로컬 `main`에 쌓인 여러 `chore(claude-plugin): sync manifest` 커밋을
개별적으로 골라내거나(cherry-pick) 합치는(squash) 방식은 채택하지 않는다.
매니페스트 JSON 파일은 히스토리가 아니라 **현재 최종 상태**만 의미가
있으므로(중간 커밋들은 서로 덮어쓰는 스냅샷일 뿐), 다음과 같이 단순화한다:

1. 로컬 `main`의 `claude/plugin/{marketplaces,plugins}.json` 현재 내용과
   `origin/main`의 내용을 diff한다.
2. 다르면: `origin/main` 기준으로 `chore/plugin-sync-publish-<label>-<YYYYMMDD-HHMMSS>`
   이름의 새 브랜치를 만들고(같은 날 여러 번 실행해도 이름 충돌 없게 타임스탬프
   포함), 로컬 `main`의 현재 파일 내용을 그 브랜치에 그대로 얹어 **새 커밋
   하나**로 만든다.
3. 그 브랜치를 push하고 PR을 연다.

이 방식은 로컬 `main`에 sync 커밋 외의 다른 무관한 커밋이 섞여 있어도
전혀 건드리지 않는다 — 기존 커밋 히스토리를 재배열(rebase/cherry-pick)할
필요 자체가 없기 때문이다.

## 다중 레포 지원

`claude/plugin/company/`는 dotfiles 작업 트리 안에 있지만 **완전히 별도의
`.git`을 가진 사내 GHES private repo**다(2026-07-01 설계 문서 참조). 이
독립성 덕분에 스크립트는 GHES 전용 분기 로직이 전혀 필요 없다 — 핵심
로직을 저장소 디렉터리를 인자로 받는 함수로 한 번만 작성하고, 두 레포에
대해 그대로 재사용한다:

```
_publish_manifest_diff <repo_dir> <label> <file...>
```

- `$MAIN_ROOT`("$HOME/dotfiles")에 대해 항상 1회 실행.
- `[ -d "$PRIV_DIR/.git" ]`(사내 PC + company/ clone 완료)일 때만
  `$PRIV_DIR`("$MAIN_ROOT/claude/plugin/company")에 대해 추가로 1회 실행 —
  `plugin-sync.sh`가 이미 쓰는 것과 정확히 같은 가드 조건.
- 각 레포 디렉터리 안에서 실행되는 `git`/`gh` 명령은 그 레포 자체의
  `origin` remote(공용 레포는 github.com, company/는 GHES)를 자동으로
  타므로, 호스트를 스크립트가 직접 판별할 필요가 없다. 전제조건은 `gh`가
  두 호스트 모두에 이미 인증돼 있다는 것뿐이다.

## PR 병합: self-authored PR 처리

이 스크립트가 여는 PR은 항상 스크립트를 실행한 사용자 본인이 author다.
GitHub는 self-approval을 서버사이드에서 차단하므로 일반적인
`gh pr review --approve` → merge 흐름이 성립하지 않는다. 이 스크립트는
Claude 밖에서 순수 셸로 동작하므로 `gh-pr-approve` **스킬을 호출하지는
않지만**, 그 스킬이 이미 이 케이스를 위해 문서화해 둔 것과 동일한 `gh`
명령 패턴을 그대로 셸 스크립트 안에 재현한다
(`claude/skills/gh-pr-approve/references/self-pr-handling.md` 참조):

```bash
gh pr merge <N> --repo "$TARGET_REPO" --admin
```

`--admin`은 관리자 권한으로 branch protection 전체(리뷰 요구 + 필수
status check 포함)를 우회할 수 있지만, 이 스크립트는 **의도적으로
그 능력을 리뷰 요구 우회 용도로만 쓴다** — status check는 실제로 통과할
때까지 폴링해서 기다린 뒤에만 `--admin` 병합을 시도한다(체크가 실패하면
병합하지 않고 중단). 이렇게 하면 "리뷰만 우회, 품질 게이트는 그대로
존중"이라는 안전한 절충이 된다.

## 병합 후 로컬 정리

병합이 성공하면 로컬 `main`을 최신 `origin/main`으로 맞춘다 — 이미 원격에
반영된 내용과 동일한, 오래된 로컬 전용 sync 커밋들을 계속 남겨둘 이유가
없기 때문이다. 단, 안전을 위해 다음 조건을 모두 만족할 때만 자동 정리한다:

- `origin/main` 대비 앞서 있던 로컬 커밋 **전부**가 `chore(claude-plugin):
  sync manifest` 메시지이고, 그 커밋들이 건드린 파일이 정확히 대상
  매니페스트 파일들뿐인 경우 → 로컬 `main`을 `origin/main`으로 갱신.
- 그 외(사용자의 다른 무관한 커밋이 섞여 있는 경우) → 자동 정리를
  건너뛰고, "로컬 main이 origin보다 앞서 있으니 직접 확인하세요" 메시지만
  출력. **어떤 경우에도 자동으로 rebase나 force-reset을 하지 않는다.**

## 에러 처리

| 상황 | 동작 |
|---|---|
| 대상 두 파일 모두 origin과 diff 없음 | "할 일 없음" 출력, exit 0 |
| push 실패(네트워크/인증) | 에러 출력 후 중단, 로컬 상태 변경 없음 |
| PR 생성 실패 | 에러 출력 후 중단 — 브랜치는 이미 push된 상태로 남겨서 수동 재시도/확인 가능 |
| status check 실패 또는 타임아웃 | 병합하지 않고 중단, PR 링크와 실패한 체크 목록 출력 |
| `$PRIV_DIR/.git` 없음 | 사내 단계는 조용히 skip (external/public PC이거나 internal인데 아직 clone 전) |
| 로컬 main에 무관한 커밋 혼재 | 위 "병합 후 로컬 정리" 표 참조 — 정리만 skip, publish 자체는 정상 진행 |

## 테스트 계획

- **git 로직(diff 감지, 브랜치 생성, 정리 조건 판단)**: 이번 대화에서 PR
  #1069/#1072 검증에 썼던 것과 동일한 격리 샌드박스 패턴(fake `$HOME` +
  자체 git repo, 실제 `git/hooks/pre-commit` 이식)으로 bats 커버. 케이스:
  diff 없음, 공용만 diff, 공용+사내 둘 다 diff, 무관한 커밋 혼재 시 정리
  skip.
- **`gh` 연동(push/PR 생성/status check 폴링/admin merge)**: bats로
  자동화하지 않는다 — 실제 GitHub/GHES 네트워크 호출이 필요해 PR
  #1069에서도 "실제 claude CLI 수동 스모크는 자동화 불가"로 명시했던 것과
  같은 카테고리다. 구현 후 실제 대기 중인 sync 커밋으로 라이브 스모크
  테스트 1회 필요.

## Open Questions

- `--admin` 병합이 status check를 실제로 기다려도 되는지(즉 "체크
  대기 후 admin 병합"이 GitHub API 상 자연스러운 흐름인지, 아니면 admin
  병합은 애초에 체크 상태를 무시하고 즉시 실행되는 게 기본 동작이라 폴링이
  무의미한지)는 구현 시 실제로 확인 필요.
- 사내 GHES `company/` private repo에도 공용 레포와 동일한 "PR 필수"
  ruleset이 걸려 있는지 미확인 — 걸려 있지 않아도 이 설계(PR 열고
  admin-merge 시도)는 안전하게 그대로 통과하므로 사전 확인 없이 진행
  가능하다고 판단했다.
