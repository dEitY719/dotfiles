# Local Test Policy

이 문서는 dotfiles 프로젝트의 **테스트 실행 위치 정책 SSOT** 다. CI 와
로컬 사이에서 어느 검사를 어디서 돌릴지를 한 곳에서만 정의한다.

발효: 2026-05-27 (이슈 #754). 개정: 2026-10-06 (이슈 #2046 — Layer 0 smoke 화),
2026-10-07 (이슈 #2054 — push 경로 테스트 기본 off, PR 생성 시 `pr-gate`).

## 한 줄 요약

- **Lint (mise / shell)** → GitHub Actions 에서 실행. 30 초 이내, 외부
  환경 보증 가치 있음.
- **`git push` / `git sync`** → 테스트를 **돌리지 않는다** (pre-push Layer 0
  기본 off). 필요할 때만 `PRE_PUSH_TEST=1` (smoke, < 60 s) /
  `PRE_PUSH_FULL_TEST=1` (전체) 로 opt-in.
- **PR 생성 (`gh-pr:create`)** → lint 통과 후 `mise run pr-gate` (= 전체
  `mise run test`) 실행. 실패 시 PR 을 만들지 않는다. 우회
  `GH_PR_TEST_BYPASS=1`.
- **전체 스위트 (`mise run test`)** → GitHub Actions `test.yml` 의
  `Test (mise, non-blocking)` job 에서 main push 후 / nightly / 수동 실행.
  pull_request 에서는 돌지 않으며 required check 가 아니다.

## #2054 개정 — push 는 테스트 없음, PR 생성이 게이트

#2046 의 smoke 도 `git sync` 마다 push 단계를 붙잡았고, 사내 PC 에서는
`PRE_PUSH_FULL_TEST` 없이도 전체 스위트가 1 시간 넘게 걸린 사례가 나왔다.
push 는 동기화 수단이지 검증 지점이 아니므로 테스트를 빼고, 전체 테스트는
리뷰 대상이 확정되는 **PR 생성 시점**에 한 번 돌린다.

### push 경로 (`git/hooks/pre-push` Layer 0)

| 설정 | 동작 |
|------|------|
| 미설정 (기본) | 테스트 없음. stderr 1 줄: `[pre-push] tests skipped (run at PR creation; ...)` |
| `PRE_PUSH_TEST=1` | `mise run test-smoke` (아래 smoke 구성), 실패 시 push 차단 |
| `PRE_PUSH_FULL_TEST=1` | `mise run test` (위보다 우선), 실패 시 push 차단 |
| opt-in + `SKIP_LOCAL_PYTEST=1` | skip, 1 줄 로그 |
| opt-in + mise 없음 | silent skip, 1 줄 로그 |

Layer 1 (protected-branch) · Layer 2 (leak guard) 는 그대로다.

### PR 생성 게이트 (`shell-common/functions/gh_pr_lint.sh`)

`gh-pr:create` Step 4.5 의 `lint-guard.sh` 가 push 직전에
`_gh_pr_lint_run <base>` 를 호출한다. 이 함수가 lint 뒤에 test gate 를 돈다.
외부 스킬 repo 수정 없이 dotfiles SSOT 한 곳에서 끝난다.

1. `GH_PR_LINT_BYPASS=1` → lint + test 전체 skip (기존 동작).
2. base 대비 변경 파일 없음 → 전체 skip (만들 PR 이 없다).
3. lint 실행. 실패 → rc 1, test gate 는 돌지 않는다. lint 도구가 하나도
   없어도 ("no lint tools detected") test gate 는 계속 진행한다.
4. `GH_PR_TEST_BYPASS=1` → test gate 만 skip.
5. 대상 repo 가 `pr-gate` mise task 를 정의했을 때만 `mise run pr-gate`
   (stdin `/dev/null`). 실패 → rc 1 → PR 생성 중단. task 가 없는 repo 는
   기존 동작 그대로다 (repo 단위 opt-in).

task 감지는 `mise task info pr-gate` 를 쓰고, 실패하면 repo 루트의
`mise.toml` / `.mise.toml` 에서 `[tasks.pr-gate]` 를 grep 한다. mise 는
trust 되지 않은 설정에서 `task info` 가 에러를 내므로, grep 이 없으면
게이트가 조용히 꺼진다. grep 으로 잡힌 경우 `mise run` 이 trust 에러로
실패해 PR 이 막히고 원인이 로그에 남는다 (fail-closed).

dotfiles 는 `mise.toml` 에 `[tasks.pr-gate]` 를 `depends = ["test"]` 로
정의한다.

한계 (수용): 스킬을 거치지 않은 수동 `gh pr create` 는 게이트를 타지
않는다. `git sync` 는 PR 을 거치지 않으므로 테스트 대기가 없다. 머지 직전
회귀는 CI 비차단 스위트가 main push 후에 잡는다.

## #2046 개정 근거 (이력 — push 경로 부분은 #2054 가 우선)

#754 이후 스위트가 커져 (bats 192 files + pytest 1628) 사내 PC 실측
`mise run test` 가 15~30 분으로 늘었다. `git sync` 의 push 단계가 매번
15 분 이상 묶이고 `Ctrl+C` / `SKIP_LOCAL_PYTEST=1` 우회가 일상화되어
Layer 0 이 사실상 무력화됐다. 그래서 push 경로에는 변경과 관련된 검사만
남기고, 전체 스위트는 push 를 막지 않는 CI 로 옮긴다.

### smoke 구성 (`PRE_PUSH_TEST=1` 일 때, `scripts/test_smoke.sh`, 규칙 SSOT 는 스크립트 헤더)

1. push 범위의 변경 `.sh`/`.bash` → `bash -n`, `.zsh` → `zsh -n` (삭제 파일 제외)
2. 변경 파일 ↔ bats 매핑 (파일 stem, `-` → `_`, bats 쪽 `test_` 접두 제거 후
   일치 또는 `_` 단위 접두 관계) 으로 **관련 bats 만** 실행. 예:
   `shell-common/functions/gcp_scan.sh` → `tests/bats/functions/gcp.bats`.
   매핑 없으면 생략.
3. `pytest -m smoke` — 셸 로드 + help 표준 인터페이스 소수 (약 5 s)
4. 예산 `PRE_PUSH_SMOKE_BUDGET` (기본 60 s) 초과 시 남은 단계 생략 + 경고,
   **실패 아님** (exit 0). 단, 잘리기 전에 bats 가 출력한 `not ok` 는 실패로
   친다. 큰 bats 파일 (예: `gcp.bats` 143 케이스 ~90 s) 은 예산 안에서 앞부분만
   돌고, 나머지 회귀는 CI 전체 스위트가 잡는다.

범위: hook 이 ref 별 `remote_sha..local_sha` (새 브랜치는 leak guard 와 같은
`_resolve_scan_range` — `<remote>/main` merge-base) 를 `PRE_PUSH_SMOKE_RANGES`
로 넘긴다. 수동 실행 시 인자 > `PRE_PUSH_SMOKE_RANGES` > `@{upstream}..HEAD`.

아래 #754 원문은 이력으로 남긴다. 현재 동작과 다른 곳은 위 개정이 우선한다.

## 근거

| 검사 | 기간 | 로컬 비용 | CI 비용 | 가치 | 결론 |
|------|------|-----------|---------|------|------|
| Lint (mise) | ~30 s | 동일 | 동일 | 외부 기여자 환경 보증, 결정론 toolchain | **CI 유지** |
| Shell Lint (mise) | ~30 s | 동일 | 동일 | shellcheck / shfmt 셋업 가변 → CI 가 canonical | **CI 유지** |
| Test (mise) | ~3 min | xdist 8+ core | 10~15 min (single runner) | 회귀 탐지. 환경 의존성 낮음 (mise toolchain). 실패 분석은 로컬이 더 빠름 | **로컬 pre-push 로 이동** |

`tests/integration/test_help_*` 류 933 테스트 기준 측정:
- 로컬 (CPython 3.13, 20-worker xdist): 170.70 s
- GitHub Actions (ubuntu-latest, mise 3.x, bash+zsh matrix): 10~15 min

매 PR push 마다 CI 의 `Test (mise)` job 이 10~15 분 차지 → 리뷰어 대기
시간 증가, runner 분량 소비. 같은 코드가 로컬에서 1/5 시간에 끝나고,
실패 분석도 즉시 가능하므로 비용 대비 가치가 역전됨.

## 메커니즘

### CI 측 (`.github/workflows/ci.yml`)

```yaml
jobs:
  lint:        # 유지 — Lint (mise)
  shell-lint:  # 유지 — Shell Lint (mise)
  # test:      # 제거 — #754 (2026-05-27)
```

Branch protection 의 required-check 목록에서도 `Test (mise)` 를 제외해야
이 정책이 완전히 발효된다 (Settings → Branches → main → Required status
checks).

### 로컬 측 (`git/hooks/pre-push`)

Layer 0 은 기본 off 다 (#2054). `PRE_PUSH_TEST=1` 이면 `mise run test-smoke`,
`PRE_PUSH_FULL_TEST=1` 이면 `mise run test` 를 push 당 1 회 돌리고, 실패 시
push 를 차단한다 (rc=1). 분기 표는 위 "#2054 개정" 절, 실제 구현은
`git/hooks/pre-push` 가 SSOT 다.

### 환경별 동작

| 환경 | 설정 | 결과 |
|------|------|------|
| 일상 push / `git sync` | 미설정 | 테스트 없음, 1 줄 로그 |
| push 전 빠른 확인 | `PRE_PUSH_TEST=1` | `mise run test-smoke`, 실패 시 push 차단 |
| push 전 전체 확인 | `PRE_PUSH_FULL_TEST=1` | `mise run test`, 실패 시 push 차단 |
| PR 생성 (`gh-pr:create`) | 미설정 | lint 후 `mise run pr-gate`, 실패 시 PR 생성 중단 |
| PR 생성, 테스트 우회 | `GH_PR_TEST_BYPASS=1` | lint 만 |
| 외부 기여자 (mise 없음) | 무관 | silent skip, reviewer 가 `mise run test` 수동 검증 |
| 모든 hook 우회 | `SKIP_PRE_PUSH=1` | 전체 hook bypass |
| `--no-verify` | 무관 | 모든 layer bypass — **사용 금지 (정책 위반)** |

## Opt-in / Opt-out 정책

| Flag | 의미 | 사용 케이스 | 금지 케이스 |
|------|------|-------------|-------------|
| `PRE_PUSH_TEST=1` | Layer 0 opt-in: `mise run test-smoke` | push 전 변경 범위 빠른 확인 | — |
| `PRE_PUSH_FULL_TEST=1` | Layer 0 opt-in: 전체 `mise run test` | 큰 리팩터링 push 전 전체 확인 | — |
| `PRE_PUSH_SMOKE_BUDGET=N` | smoke 예산 (초, 기본 60) | 느린 PC 에서 매핑 bats 가 잘릴 때 | — |
| `SKIP_LOCAL_PYTEST=1` | opt-in 상태에서도 Layer 0 skip (호환용 유지) | 환경변수로 opt-in 을 켜 둔 채 WIP push | — |
| `GH_PR_TEST_BYPASS=1` | PR 생성 시 `pr-gate` 만 skip | 테스트와 무관한 문서 PR, 알려진 flaky 로 막혔을 때 | 실패하는 테스트를 덮으려는 목적 |
| `GH_PR_LINT_BYPASS=1` | PR 생성 lint + test 전체 skip | lint guard 자체 디버깅 | 일상 사용 |
| `SKIP_PRE_PUSH=1` | 전체 hook bypass | hook 자체 디버깅 | 일상 사용 |
| `--no-verify` | 모든 hook bypass | **사용 금지** — branch protection 우회와 동급 | — |

습관적으로 `GH_PR_TEST_BYPASS=1` 를 사용한다면 정책 자체를 재평가해야
한다 — 이 문서를 갱신하거나 정책을 롤백한다.

## 검증

새 정책의 회귀 보호:
- `tests/bats/git/test_pre_push_pytest.bats` — 기본 off (mise 미호출) /
  `PRE_PUSH_TEST=1` smoke 성공·실패 / `PRE_PUSH_FULL_TEST=1` /
  `SKIP_LOCAL_PYTEST=1` / mise 미설치 / push 범위 전달 + per-ref loop stdin
  보존 / 기본 off 에서도 protected-branch 차단
- `tests/bats/functions/gh_pr_lint.bats` — `pr-gate` 존재+통과 / 존재+실패 /
  부재 / trust 안 된 설정 (grep fallback) / `GH_PR_TEST_BYPASS=1` /
  `GH_PR_LINT_BYPASS=1` / lint 도구 없음에도 실행 / lint 실패 시 미실행 / zsh
- `tests/bats/scripts/test_smoke.bats` — 매핑 (gcp_scan.sh → gcp.bats),
  매핑 없음, 문법 오류 실패, bats 실패, 예산 초과 = 경고 + exit 0

Before/After 측정 (#754 당시):
- CI `Test (mise)` 시간: 10~15 min → 0 min
- 로컬 `mise run test` 시간: ~3 min (변화 없음, 단 push 마다 자동 실행)
- 리뷰어 CI 대기: ~15 min → ~30 s (Lint 만)

## 리스크 및 롤백

| 리스크 | 완화 |
|--------|------|
| 외부 기여자 mise 미설치 → 회귀 누락 | reviewer 수동 `mise run test` (PR 머지 전 checklist) |
| 로컬 환경 차이 (Python/OS) 로 인한 위양성 | mise toolchain pinned in `mise.toml` |
| PR 생성 후 추가 push 로 들어온 회귀 | CI 비차단 스위트 (main push / nightly), 필요 시 `PRE_PUSH_FULL_TEST=1` |
| 수동 `gh pr create` 로 게이트 우회 | `gh-pr:create` 스킬 사용 (수용된 한계, #2054) |
| `--no-verify` 남용 | `git/hooks/install-hooks.sh` 출력에 경고 추가, 코드 리뷰에서 차단 |

### 롤백 트리거 (이 정책을 뒤집을 신호)

1. 1 주일 내 회귀 머지 사례 2 건 이상 발생 → CI test job 복원
2. mise 환경 결정론 깨짐 (e.g. system Python 의존, 외부 도구 drift) 발견
   → CI 복원
3. 외부 기여 PR 빈도가 유의미하게 증가 → CI 복원 (현재는 사실상 솔로
   프로젝트)

롤백 절차:
1. `.github/workflows/ci.yml` 의 `test` job 부활 (이 PR 의 git revert
   1 회).
2. Branch protection required-check 에 `Test (mise)` 재추가.
3. `git/hooks/pre-push` 의 Layer 0 블록 제거 (또는
   `SKIP_LOCAL_PYTEST=1` 환경 기본화).
4. 이 문서 갱신 — 정책 변경 이력 추가.

## 관련 위치

- `.github/workflows/ci.yml` — lint
- `.github/workflows/test.yml` — shell lint + 전체 스위트 (비차단, #2046)
- `scripts/test_smoke.sh` — smoke 구현 (`mise.toml` `[tasks.test-smoke]`)
- `git/hooks/pre-push` — Layer 0 구현 (opt-in)
- `shell-common/functions/gh_pr_lint.sh` — PR 생성 lint + `pr-gate` 게이트
- `git/hooks/install-hooks.sh` — 사용자 안내 (`--no-verify` 경고)
- `git/AGENTS.md` — hook 모듈 라우터, 본 정책 링크
- `mise.toml` `[tasks.test]` — `uv run ./tests/test` 정의, `[tasks.pr-gate]` —
  PR 생성 게이트 (`depends = ["test"]`)
- 이슈 #754 — 정책 결정 본문, #2046 — smoke 화, #2054 — push 테스트 off + PR 게이트
