# Local Test Policy

이 문서는 dotfiles 프로젝트의 **테스트 실행 위치 정책 SSOT** 다. CI 와
로컬 사이에서 어느 검사를 어디서 돌릴지를 한 곳에서만 정의한다.

발효: 2026-05-27 (이슈 #754). 개정: 2026-10-06 (이슈 #2046 — Layer 0 smoke 화).

## 한 줄 요약

- **Lint (mise / shell)** → GitHub Actions 에서 실행. 30 초 이내, 외부
  환경 보증 가치 있음.
- **Smoke (`mise run test-smoke`)** → 로컬 `pre-push` git hook Layer 0
  에서 push 범위만 대상으로 실행. 목표 < 60 s, 실패 시 push 차단.
- **전체 스위트 (`mise run test`)** → GitHub Actions `test.yml` 의
  `Test (mise, non-blocking)` job 에서 main push 후 / nightly / 수동 실행.
  pull_request 에서는 돌지 않으며 required check 가 아니다 (push·merge
  대기 경로 밖). 로컬에서는 `PRE_PUSH_FULL_TEST=1 git push` 로 opt-in.

## #2046 개정 근거

#754 이후 스위트가 커져 (bats 192 files + pytest 1628) 사내 PC 실측
`mise run test` 가 15~30 분으로 늘었다. `git sync` 의 push 단계가 매번
15 분 이상 묶이고 `Ctrl+C` / `SKIP_LOCAL_PYTEST=1` 우회가 일상화되어
Layer 0 이 사실상 무력화됐다. 그래서 push 경로에는 변경과 관련된 검사만
남기고, 전체 스위트는 push 를 막지 않는 CI 로 옮긴다.

### smoke 구성 (`scripts/test_smoke.sh`, 규칙 SSOT 는 스크립트 헤더)

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

Layer 0 (per-push, 1회만) 으로 `mise run test-smoke` (`PRE_PUSH_FULL_TEST=1`
이면 `mise run test`) 가 실행된다. 실패 시 push 가 차단된다 (rc=1). 아래
요약은 #754 당시 형태이며 실제 구현은 `git/hooks/pre-push` 가 SSOT 다.

```sh
# git/hooks/pre-push 에 추가된 분기 요약
case "${SKIP_LOCAL_PYTEST:-0}" in
    1)        # 명시 skip — WIP push 등
        ;;
    *)
        if command -v mise >/dev/null 2>&1; then
            mise run test </dev/null || exit 1
        else
            # mise 없는 환경 — silent skip
            ;
        fi
        ;;
esac
```

### 환경별 동작

| 환경 | mise 설치? | SKIP_LOCAL_PYTEST? | 결과 |
|------|-----------|-------------------|------|
| 정상 dev 머신 | ✓ | 미설정 | `mise run test-smoke` 실행, 실패 시 push 차단 |
| 전체 스위트 로컬 실행 | ✓ | 미설정 (`PRE_PUSH_FULL_TEST=1`) | `mise run test` 실행, 실패 시 push 차단 |
| WIP push / 의도된 fail | ✓ | `=1` | skip, 1 줄 로그만 |
| 외부 기여자 (mise 없음) | ✗ | 무관 | silent skip, reviewer 가 `mise run test` 수동 검증 |
| 모든 hook 우회 | 무관 | 무관 (`SKIP_PRE_PUSH=1`) | 전체 hook bypass |
| `--no-verify` | 무관 | 무관 | 모든 layer bypass — **사용 금지 (정책 위반)** |

## Opt-out 정책

| Flag | 의미 | 사용 케이스 | 금지 케이스 |
|------|------|-------------|-------------|
| `PRE_PUSH_FULL_TEST=1` | Layer 0 을 전체 `mise run test` 로 | 큰 리팩터링 push 전 전체 확인 | — |
| `PRE_PUSH_SMOKE_BUDGET=N` | smoke 예산 (초, 기본 60) | 느린 PC 에서 매핑 bats 가 잘릴 때 | — |
| `SKIP_LOCAL_PYTEST=1` | Layer 0 만 skip (호환용 유지) | WIP 큰 리팩터링 중간 push, 의도된 실패 push (다음 commit 에서 수정 예정) | 단순한 시간 절약 목적 |
| `SKIP_PRE_PUSH=1` | 전체 hook bypass | hook 자체 디버깅 | 일상 사용 |
| `--no-verify` | 모든 hook bypass | **사용 금지** — branch protection 우회와 동급 | — |

습관적으로 `SKIP_LOCAL_PYTEST=1` 를 사용한다면 정책 자체를 재평가해야
한다 — 이 문서를 갱신하거나 정책을 롤백한다.

## 검증

새 정책의 회귀 보호:
- `tests/bats/git/test_pre_push_pytest.bats` — skip / mise 미설치 / smoke
  성공·실패 / `PRE_PUSH_FULL_TEST=1` / push 범위 전달 + per-ref loop stdin 보존
- `tests/bats/scripts/test_smoke.bats` — 매핑 (gcp_scan.sh → gcp.bats),
  매핑 없음, 문법 오류 실패, bats 실패, 예산 초과 = 경고 + exit 0

Before/After 측정:
- CI `Test (mise)` 시간: 10~15 min → 0 min
- 로컬 `mise run test` 시간: ~3 min (변화 없음, 단 push 마다 자동 실행)
- 리뷰어 CI 대기: ~15 min → ~30 s (Lint 만)

## 리스크 및 롤백

| 리스크 | 완화 |
|--------|------|
| 외부 기여자 mise 미설치 → 회귀 누락 | reviewer 수동 `mise run test` (PR 머지 전 checklist) |
| 로컬 환경 차이 (Python/OS) 로 인한 위양성 | mise toolchain pinned in `mise.toml` |
| `pre-push` 통과 후 머지 직전 회귀 | `gh-pr:merge` skill 의 pre-merge 검증 옵션 (별도 이슈) |
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
- `git/hooks/pre-push` — Layer 0 구현
- `git/hooks/install-hooks.sh` — 사용자 안내 (`--no-verify` 경고)
- `git/AGENTS.md` — hook 모듈 라우터, 본 정책 링크
- `mise.toml` `[tasks.test]` — `uv run ./tests/test` 정의
- 이슈 #754 — 정책 결정 본문
