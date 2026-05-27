# Dual-PR Deadlock Emergency Merge of PR #748 (2026-05-26)

- 인시던트 이슈: [#752](https://github.com/dEitY719/dotfiles/issues/752)
- 영향 PR: [#745](https://github.com/dEitY719/dotfiles/pull/745) (정상), [#748](https://github.com/dEitY719/dotfiles/pull/748) (admin bypass)
- 머지 SHA: `11edbc38b5b949f0f8cbc6fb54186230f932bfa0` (#748)
- 실행자: @dEitY719

## Issue

2026-05-26 기준 `main` 의 `Test (mise)` required check 가 **20건의 pytest fail**
(`gc_help` 16건 + `gwt_help` 4건) 로 빨강. 두 회복 PR — `#745` (gc_help fix) 와
`#748` (gwt_help fix) — 모두 머지 후의 main 상태를 시뮬레이션하는 required-check 평가에서
상속된 빨강을 보았다. 정상 리뷰 경로로는 어느 한쪽도 머지할 수 없는 chicken-and-egg
deadlock.

## Root Cause

PR #318 은 `_help` 함수에 표준 헬퍼 패턴을 도입하면서 일부 토픽만 마이그레이션했다.
누락된 토픽 (`gc_help`, `gwt_help`) 은 pytest 실패로 main 에 누적되었지만, 당시에는
`Test (mise)` 가 머지 차단 required check 가 아니어서 즉시 드러나지 않았다.

이후 CI 정책으로 `Test (mise)` 가 required check 가 되자, 누적된 16+4 = 20 건의 빨강이
**모든 PR 의 머지를 차단**하기 시작했다. 빨강을 해소할 두 PR 자신이 같은 빨강에 막히는
구조 — 즉 deadlock — 가 형성되었다.

## Decision Timeline

| UTC 시각 | 이벤트 | 머지 방식 |
|---|---|---|
| 04:49:03Z | PR #745 (`gc_help` fix, 16건 해소) 머지 | 정상 머지 (`merge_commit_sha=04bec8f7`) |
| 04:55:40Z | PR #748 (`gwt_help` fix, 4건 해소) 머지 | **admin bypass** (`gh pr merge --admin --squash`) |

PR #745 머지 후 6 분 만에 PR #748 을 admin bypass 한 이유: 그 6 분 구간에서 PR #748 의
required check 가 머지된 #745 의 효과를 재평가하지 않아 stale red 가 유지됨. 사용자는
CI 재평가를 기다리지 않고 deadlock 종결을 우선했다.

bypass 정당화 (이슈 본문 인용):
> 머지 후 main 의 fail 수는 `20 → 16` 으로 감소 (4건 해소).
> gc_help 16건은 #745 머지 시 0 으로 떨어짐 → 결과적으로 main Test (mise) 0/20 green 회복.

## Lessons Learned

1. **표준 도입 PR 은 누락 마이그레이션이 timebomb 이 된다.** PR #318 시점에 누락된
   2개 토픽의 pytest fail 이 6 개월 후 required-check 정책 변경 시점에 deadlock 의
   재료가 되었다. 표준 도입 PR 은 affected-topic matrix 를 본문에 명시해야 한다.

2. **느린 required check 는 일시적 빨강 시 회복 비용이 비대칭으로 커진다.** `Test (mise)`
   가 10–15 분 걸리는 long-tail 작업이라 두 PR 간 6 분의 정상 머지 간격으로는 CI
   재평가가 끝나지 않았다 — 정상 경로로 두 번째 PR 을 머지하려면 PR #745 머지 후
   `Test (mise)` 가 재실행될 시간을 기다린 뒤 #748 의 head 를 rebase 하는 라운드트립이
   필요했다.

3. **Admin bypass 의 audit trail 은 paired incident issue 로 강제되어야 한다.** 이번
   인시던트는 #752 가 생성되어 추적되었다. `gh-pr-merge-emergency` 스킬이 이를
   자동화하고 있어 정책이 작동 중임을 확인.

## Prevention (실제 적용된 변경)

| 항목 | 상태 | 참조 |
|---|---|---|
| `Test (mise)` 를 CI required check 에서 제거하고 로컬 pre-push hook 으로 이전 | **완료** | PR #754 (commit `688f6b7`) |
| `gh:pr-merge-emergency` 스킬 — bypass 시 incident issue 자동 생성 | **완료** | PR #481 후속 |
| 표준 도입 PR 의 affected-topic 체크리스트 | 미적용 (백로그) | 후속 follow-up 이슈 권장 |
| Long-tail required check 의 회복 경로 SSOT | 부분 완료 | PR #754 가 사실상 해결 (해당 잡 제거) |

PR #754 가 핵심 prevention 이다. `Test (mise)` 잡 자체를 CI required check 에서
제거하고 로컬 `pre-push` hook 으로 옮김으로써 이 클래스의 deadlock (느린 required check
가 자기 자신을 차단) 이 구조적으로 발생할 수 없게 만들었다.

## Recovery 검증

- 머지 직후 main: `Test (mise)` 0/20 (green) 확인.
- 본 인시던트 이후 정상 경로로 머지된 PR 들: `#754` `#755` `#756` `#757` `#758` `#759`
  `#761` `#762` `#763` `#765` `#768` `#771` `#772` `#773` `#776` `#778` `#780` `#783` —
  모두 정상 리뷰 경로 (admin bypass 없음). 회복 완료.
