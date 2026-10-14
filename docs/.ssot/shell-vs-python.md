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
- 종료 코드: `0`/`1` 은 op 의 답 (예/아니오), `2` 는 읽을 수 없는 입력·잘못된 사용.
- 진단 메시지는 stderr 만. 사용자 출력(`ux_*`)은 셸이 한다.

## 이식 절차

1. 대상 셸 함수의 jq/awk 필터를 그대로 `lib/<영역>_shell.sh` 로 옮겨 롤백 경로로
   남기고, `<PREFIX>_IMPL=shell|python` 스위치(기본 python)를 1 릴리스 둔다.
2. pytest 에 golden parity 테스트 — 같은 fixture 에서 셸 경로와 Python 경로의
   stdout·종료 코드가 같아야 한다.
3. 관측 기간 후 롤백 경로를 제거하는 후속 이슈를 등록한다.

## 1차 이식 — issue watcher (#2157)

`dotfiles_tools.issue_watcher.select` 가 `issue_watcher_cron.sh` 의 후보 선정·필터
순수 로직을 맡는다. 롤백: `IW_SELECT_IMPL=shell`
(`shell-common/tools/custom/lib/issue_watcher_select_shell.sh`).

| 셸 함수 | op | 바뀐 것 |
|---------|----|---------|
| `_iw_search_issues` | `search-rows` | search JSON → `<repo>\t<n>\t<labels>` jq 필터 |
| `_iw_load_open_prs` | `pr-count` | PR 창 크기 jq `length` |
| `_iw_handled_by_pr` | `handled-by-pr <n>` | closing keyword / `wt/issue-<n>/` 판정 (0/1/2) |
| `_iw_blocked_by_open` | `open-blockers` | blockedBy GraphQL 응답의 OPEN 번호 |
| `_iw_repo_order` | `repo-order <last>` | round-robin 순서 awk |

셸에 남은 것: `_iw_select_candidates` 의 오케스트레이션 (예산 계산, per-repo cap,
lazy 한 gh 호출 순서) — 네트워크 호출 사이에 끼어 있어 순수 함수가 아니다.

수치: `issue_watcher_cron.sh` 3204 → 3194줄, `grep -c "jq "` 11 → 7.

후속: 롤백 경로 제거 #2173 (1 릴리스 관측 후), 2순위 이식
(`pr_merge_train_cron.sh`, claude 계정 로직) #2174.
