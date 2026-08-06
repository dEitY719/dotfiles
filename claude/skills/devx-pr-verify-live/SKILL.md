---
name: devx:pr-verify-live
description: >-
  Attach to the already-running dev app and verify a PR actually works — confirm the
  serving checkout contains the target commit, drive the screens the PR/issue named,
  prove each claim with a machine-readable assertion, and file surviving findings as
  new issues in the target project repo. Use for /devx:pr-verify-live,
  /devx-pr-verify-live, "머지된 PR 라이브 검증", "실행 중인 앱에서 내 PR 직접 확인해",
  "live-verify this PR". Primarily used right after a merge, but works on an unmerged
  PR branch too. Read-only on source code — fixes go out as new issues via
  gh:issue-create. Accepts `[pr-number] [remote] [--url <base-url>] [--api-url
  <origin>] [--start <cmd>] [--matrix auto|full] [--viewports <csv>] [--locales
  <csv>] [--dry-run] [--no-issue] [--allow-remote-host]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Write, AskUserQuestion, Agent
metadata:
  model_recommendation:
    tier: opus
    reason: "live browser verification with adversarial self-refutation; a false positive files a wrong issue in someone else's repo"
    claude: prefer
    non_claude: advisory-only
---

# devx:pr-verify-live — Verify a PR against the running app

## Role

**올바른 체크아웃을 서빙 중인 앱에 붙어 · PR 이 지정한 항목을 · 기계 판독 가능한 단언으로
확인하고 · 스스로 반증에서 살아남은 발견만 이슈로 넘긴다.** 막으려는 실패 클래스는 하나다 —
**화면은 멀쩡히 뜨는데 검증이 무효인 상태**(잘못된 체크아웃 · no-op 전환 · 오버레이에 가린
대상 · 일부 분기만 보고 전부 봤다는 착각). 이슈 본문·라벨·메트릭은 `gh:issue-create` 가 SSOT
— 이 스킬은 **게이트만** 책임진다. 항목별 실측 출처: `references/provenance.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output it
verbatim, then stop. No API calls, no browser.

## Step 1: Parse Args

`source "${SHELL_COMMON}/functions/devx_pr_verify_live.sh"` then
`devx_pr_verify_live_parse "$@"`. On `help_requested=1` follow Help; on exit 2 print
the stderr line and stop. Capture `pr` `remote` `url` `api_url` `start_cmd` `matrix`
`viewports` `locales` `issue_mode` `allow_remote_host`. Record `START_TS=$(date +%s)`.

## Step 2: Resolve target + discover the environment (`references/discovery.md`)

- `TARGET_REPO` ← `_gh_pr_review_resolve_target_repo "<remote>"`; `pr` 이 비었으면 현재 브랜치
  → 실패 시 `gh api /repos/{owner}/{repo}/commits/<sha>/pulls` 로 역추적.
- base URL / API origin 발견 (`--url`·`--api-url` 이 있으면 건너뛴다). 후보가 여럿이면
  `AskUserQuestion` — **추측 금지**.
- **호스트 가드**: 대상이 loopback 이 아니면 `--allow-remote-host` 없이 정지 (Step 6 은 앱 데이터에
  쓰기를 한다). `--start` 를 준 경우에만 레포 루트에서 기동하고 종료 시 정리한다.

## Step 3: Pre-verification assertion 1 — serving checkout

**변경된 코드를 서빙하는 모든 프로세스**에 대해 cwd → repo root → ancestry 를 돌린다. 비교
대상은 `gh pr view --json mergeCommit -q .mergeCommit.oid` — `headRefOid` 는 rebase/squash
merge 로 재작성되므로 쓰지 않는다(미머지 PR 일 때만 폴백). 불일치면 몇 커밋 뒤처졌는지와 함께
**정지**한다. dirty 워킹 트리는 경고, 컨테이너 백엔드는 `unverified` — 둘 다 정지가 아니다.

## Step 4: Decide what to verify (`references/targets.md`)

우선순위: 연결된 **이슈의 AC**(체크 무관) → PR `Test plan` 미체크 항목(최종 diff 와 대조) →
라우트 추론(진입점까지) → `AskUserQuestion`. `- [x]` 를 통과로 취급하지 않는다. 이어서 **각
분기에 도달할 데이터 상태**(계정·레코드)를 API 로 찾고 **feature flag 게이트**가 열려 있는지
확인한다 — 닫혀 있으면 결함이 아니라 미검증이며 켤지 말지를 묻는다. 도달 불가 분기는 `unverified[]`.

## Step 5: Driver + session (pre-verification assertions 2·3)

`references/driver.md` 의 사다리(playwright MCP → python → node → degraded)를 **브라우저
바이너리까지** 확인해 고르고, 그 드라이버가 가능케 하는 검사군을 확정한다. 그다음
`references/recipe-cache.md` 로 로그인·오버레이 해제·로케일 전환 레시피를 캐시에서 읽거나
발견한다. 여기서 **단언 2·3** 이 걸린다 — 전환이 실제로 적용됐는가, 대상이 가려지지 않았는가.
실패면 **측정하지 않고 정지**한다.

## Step 6: Measure (`references/assertions.md`)

먼저 diff 로 **축을 고르고**(`--matrix full` 은 opt-in), 변경 유형이 정하는 근거 형태로 각
항목을 단언한다: 측정값 · 형제 비교 · 지시-어포던스 · 셀렉터 규율 · 응답 가로채기 · 선행 조건
합성 · hit-test. 합성한 엔드포인트는 전부 기록한다.

## Step 7: Findings → issues (`references/findings.md`)

후보 1건마다 **자기 반증 3가설**(하네스 오류 · 데이터 상태 · 의도된 동작)을 먼저 세워 반증하고,
그다음 게이트 5개를 건다. 통과한 것만 발견 1건 = 이슈 1건으로 `Skill(gh:issue-create)` 에 넘기되
생성 직전 **대상 레포를 출력**한다. 회귀와 기존 결함을 갈라 적고, PR 의 근거가 반증됐으면 그
정정도 수정안에 포함한다. `issue_mode` 가 `dry-run` 이면 본문만 출력, `none` 이면 초안조차 쓰지 않는다.

## Step 8: Report (`references/report-template.md`)

그 양식으로 한 블록을 출력한다. `Checks:` 만 적지 않는다 — `Matrix:` `Unverified:` `Synthetic:` `Rejected:` `Created:` 가 빠지면 실제보다 강해 보인다.

## Constraints (전체 목록과 근거: `references/constraints.md`)

- 검증 전 단언 3종(체크아웃 · 전환 적용 · 비가림) 중 하나라도 실패면 측정하지 않고 정지한다.
- **소스 코드는 읽기 전용**이지만 앱 **데이터에는 쓰기를 한다** — dev/fake 스택 전용이고,
  사용자가 띄운 서버는 죽이지 않는다(`--start` 로 띄운 것만 정리).
- 근거 없는 발견, 자기 반증을 통과하지 못한 후보는 이슈로 만들지 않는다.
- 못 찾은 값을 추측하지 않고, 축소한 커버리지를 숨기지 않고, 자격증명을 어디에도 남기지 않는다.
