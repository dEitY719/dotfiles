# Shell vs Python Boundary

이 문서는 dotfiles 에서 **언제 Python 을 쓰고 언제 셸에 남기는지**의 SSOT 다
(이슈 #2157). 셸 상태머신이 수천 줄로 자라는 것(`issue_watcher_cron.sh` 3204줄,
jq 11곳)을 막기 위한 규칙이다.

## Python 채택 기준

다음 중 **하나라도** 해당하면 로직은 Python 으로, 셸은 thin entrypoint 로 둔다.

| 기준 | 예 |
|------|----|
| (a) 상태머신 — 3개 이상 상태 전이 | issue watcher 의 dispatch/retry/cleanup 판정 |
| (b) JSON/GraphQL 을 2단계 이상 변환 | `gh ... --json` 결과를 jq 로 거른 뒤 다시 가공 |
| (c) 단일 파일 500줄 초과 예상 | 새 cron 도구 |
| (d) 재시도·백오프 정책 | merge train 의 retry |

## 셸 유지 기준

- 부모 셸 상태를 바꾼다 (`cd`, `export`, alias/function 정의 — sourced 코드).
- 외부 repo 가 vendoring 하는 셸 lib 다.
- 대화형 프롬프트나 `ux_lib` 출력이 중심이다.
- gh/herdr/git 호출, lock, 로그 — 하이브리드에서도 이 부분은 셸에 남긴다.

## 패키지와 테스트 위치

- 패키지: `tools/py/dotfiles_tools/<영역>/` (`pyproject.toml` `package-dir = {"" = "tools/py"}`).
  `uv sync` 가 editable 로 설치한다.
- **stdlib 만** 쓴다 — cron 은 uv venv 밖의 시스템 `python3` 로 실행한다
  (`cron-jobs.json` `defaults.env.PATH`).
- 타입: `uv run mypy .` (strict) 가 패키지를 검사한다. 린트: ruff 기존 규칙.
- 테스트: `tests/py/test_<영역>_*.py`, fixture 는 `tests/py/fixtures/<영역>/`.
  `pyproject.toml` `testpaths` 와 `./tests/test` 의 pytest 단계가 `tests/py` 를 포함한다.

## 호출 규약

```sh
. "$(dirname "$0")/lib/cron_common.sh" && cron_bootstrap || exit 1
printf '%s' "$json" | cron_py dotfiles_tools.<영역>.<모듈> <op> [arg]
```

- `cron_py` (`shell-common/tools/custom/lib/cron_common.sh`) 는
  `cd "$SHELL_COMMON/../tools/py" && python3 -E -s -m <모듈>` 이다. `-E -s` 로
  `PYTHONPATH`·user site 를 무시하고, `-m` 이 import 하는 위치를 이 repo 가 소유한
  `tools/py` 로 고정한다 (`-I` 는 3.11+ 에서 `-m` 의 cwd 탐색까지 꺼서 쓸 수 없다).
- 입력: stdin — gh 가 출력한 JSON 그대로 (셸이 이미 가진 줄 목록이면 그 줄 그대로).
- 출력: stdout — 셸이 바로 소비하는 형태 (`read` 루프면 TSV 줄, 아니면 JSON).
  셸 쪽에 jq 재파싱을 남기지 않는 것이 목적이다.
- 종료 코드: `0` 은 답함, `2` 는 읽을 수 없는 입력·잘못된 사용 (stdout 비움). `1` 은
  op 의 "아니오" 로만 쓰되, **안전에 걸린 판정은 exit 1 이 아니라 stdout 으로 내린다** —
  import 조차 못 한 `python3` 도 exit 1 로 끝나므로, 셸은 빈/비숫자 stdout 을
  "판단 불가" 로 읽어야 한다 (`handled-by-pr` 가 그 예).
- python3 >= 3.10 이 없으면 (RHEL 8 은 3.6) 롤백 경로로 경고 후 자동 전환한다 — 도구가 멈추지 않는다.
- 진단 메시지는 stderr 만. 사용자 출력(`ux_*`)은 셸이 한다.

## 이식 절차

1. 대상 셸 함수의 jq/awk 필터를 그대로 `lib/<영역>_shell.sh` 로 옮겨 롤백 경로로
   남기고, `<PREFIX>_IMPL=shell|python` 스위치(기본 python)를 1 릴리스 둔다.
2. pytest 에 golden parity 테스트 — 같은 fixture 에서 셸 경로와 Python 경로의
   stdout·종료 코드가 같아야 한다.
3. 관측 기간 후 롤백 경로를 제거하는 후속 이슈를 등록한다.

## 1차 이식 — issue watcher (#2157)

`dotfiles_tools.issue_watcher.select` 가 `issue_watcher_cron.sh` 의 후보 선정·필터
순수 로직을 맡는다. 1 릴리스 관측 후 `IW_SELECT_IMPL=shell` 롤백 경로
(`issue_watcher_select_shell.sh`)와 golden parity 테스트는 제거됐다 (#2173) —
python3 >= 3.10 이 없으면 watcher tick 은 후보 선정을 하지 않고 에러로 종료한다.

| 셸 함수 | op | 바뀐 것 |
|---------|----|---------|
| `_iw_search_issues` | `search-rows` | search JSON → `<repo>\t<n>\t<labels>` jq 필터 |
| `_iw_load_open_prs` | `pr-count` | PR 창 크기 jq `length` |
| `_iw_handled_by_pr` | `handled-by-pr <n>` | closing keyword / `wt/issue-<n>/` 에 걸린 PR 수 (셸이 0/1/2 로 판정) |
| `_iw_blocked_by_open` | `open-blockers` | blockedBy GraphQL 응답의 OPEN 번호 |
| `_iw_repo_order` | `repo-order <last>` | round-robin 순서 awk |

셸에 남은 것: `_iw_select_candidates` 의 오케스트레이션 (예산 계산, per-repo cap,
lazy 한 gh 호출 순서) — 네트워크 호출 사이에 끼어 있어 순수 함수가 아니다.

이식 시점 수치 (#2157): `issue_watcher_cron.sh` 의 jq 호출 6 → 2 (남은 2건은 watch list·herdr pane 파싱), `grep -c "jq "` 11 → 9 (롤백 안내 문구 포함), 줄 수 3204 → 3209 (선택 로직 −40줄, 롤백·fail-closed 분기 +45줄).

후속: 2순위 이식 (`pr_merge_train_cron.sh`, claude 계정 로직) 은 아래 "2차 이식" (#2174).

## 2차 이식 — merge train dispatcher (#2174)

`dotfiles_tools.merge_train.queue` 가 `pr_merge_train_cron.sh` 의 큐 판정 순수 로직을
맡는다. 롤백: `PMT_QUEUE_IMPL=shell` (`shell-common/tools/custom/lib/merge_train_queue_shell.sh`).
python3 >= 3.10 이 없으면 경고 후 자동으로 롤백 경로를 쓴다.

| 셸 함수 | 기준 | op | 바뀐 것 |
|---------|------|----|---------|
| `_pmt_target_count` | (b) | `count` | 필터된 PR 배열 jq `length` |
| `_pmt_bind_fingerprint` | (b) | `fingerprint` | `(number, headRefOid, mergeStateStatus, mergeable, verdict labels)` 튜플 정렬·접기 jq |
| `_pmt_backoff_gate` | (a)(d) | `backoff-next <max> <fp>` | 상태줄 → `run` / `run <w> <r>` / `skip <w> <r>` 판정 (리셋·카운트다운·2배·상한) |

셸에 남은 것: 상태 파일 읽기/쓰기와 쓰기 실패 시 "skip 대신 run" 결정, lock, gh/herdr 호출,
`_pmt_bind_actionable` (판정 술어가 `gh:pr-merge-train` 스킬과 공유하는
`functions/gh_pr_merge_train.sh` 의 SSOT — #1524 가 중복을 없앤 그 로직이라 옮기지 않는다),
`_pmt_start_agent_retrying` / `_pmt_prompt_train` 의 재시도 루프 (각 시도가 herdr 호출이고
분기는 에러 코드 1개 비교라 순수 로직이 남지 않는다).

### claude 계정 로직 — 이식 대상 없음

`claude_accounts.sh` + `lib/claude_accounts_{auth,lifecycle,skills}.sh` 를 같은 기준으로
판정했다. migrate/rollback 은 (a)(b)(d) 어느 것에도 해당하지 않아 셸에 둔다.

| 함수 | 판정 | 이유 |
|------|------|------|
| `claude_accounts_migrate` | 셸 유지 | 대화형 확인(`read`) + `mv`/`umount` 순차 실행. 상태 전이·JSON·재시도 없음 |
| `claude_accounts_rollback` | 셸 유지 | 활성 계정 선택은 파일 존재 2-pass 검사 1개, 나머지는 `mv` 순차 실행 |
| `claude_accounts_repair` | 셸 유지 | symlink 재지정 — 파일시스템 조작이 본체 |
| `_claude_has_unmigrated_data` | 셸 유지 | 파일 존재 술어 |
| `_claude_resolve_account` · `_claude_account_auth_kind` · `_claude_validate_login` | 셸 유지 | auth lib 은 부모 셸 상주(`claude_yolo` 가 source), jq 1단계 조회 |
| `_claude_ensure_settings_copy` | 셸 유지 | (b) 에 해당(model 키 이주·로컬 전용 키 병합)하지만 `./setup.sh` 경로다 — one-click setup 은 python3 >= 3.10 이 없는 PC 에서도 수렴해야 하고(`docs/.ssot/one-click-setup.md`), 이미 jq 부재 시 degrade 경로가 있다 |

후속: 롤백 경로(`PMT_QUEUE_IMPL`) 제거 #2210 (1 릴리스 관측 후, #2173 과 같은 형태).
