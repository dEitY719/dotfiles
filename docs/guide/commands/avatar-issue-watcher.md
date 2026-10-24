# avatar-issue-watcher

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/avatar_issue_watcher.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic avatar_issue_watcher --force`

## 호출

- Help 진입점: `avatar-issue-watcher-help [section|--list|--all]`
- 통합 라우팅: `my-help avatar_issue_watcher [section]`
- Alias: `avatar-issue-watcher`, `avatar-issue-watcher-help`

## 요약 (avatar-issue-watcher-help)

- Usage: avatar-issue-watcher-help [section|--list|--all]
- sections
    - commands: run modes (tick, --dry-run, <issue-ref>, --status, watch, label)
    - examples: manual runs, watch list, excluded labels, periodic runs (aicron/crontab)
- Full cycle, caps, gate, watch list and state paths: avatar-issue-watcher --help

## 섹션

### commands

- **avatar-issue-watcher** — Tick — Dispatch assigned open issues to /gh-flow:wave in a wt/issue-<N> worktree (cron)
- **avatar-issue-watcher --dry-run** — Preview — Print what a tick would dispatch, change nothing
- **avatar-issue-watcher <issue-ref>** — Target — Dispatch one issue (URL, owner/repo#N, #N, N) through the tick's guards
- **avatar-issue-watcher <issue-ref> --force** — Target — Same, despite an excluded label
- **avatar-issue-watcher --status** — Status — Rate-limit gate, saturation, gh search state
- **avatar-issue-watcher watch list** — Watch — Show the watch list file and its entries
- **avatar-issue-watcher watch add [owner/repo]** — Watch — Add/update an entry (--path P, --host H; default: cwd repo; stored as the main checkout)
- **avatar-issue-watcher watch remove [owner/repo]** — Watch — Drop an entry (default: cwd repo)
- **avatar-issue-watcher label list** — Label — Show the excluded labels and their source (env/file/default)
- **avatar-issue-watcher label add <label>...** — Label — Exclude labels (absent file: seeded from the default)
- **avatar-issue-watcher label remove <label>...** — Label — Stop excluding labels
- **avatar-issue-watcher --help** — Help — Full cycle, caps and gate rules

### examples

- **avatar-issue-watcher --dry-run** — Manual — Preview one tick without dispatching
- **avatar-issue-watcher --status** — Manual — Show gate, saturation and search state
- **avatar-issue-watcher --dry-run https://github.com/dEitY719/dotfiles/issues/2275** — Target — Preview dispatching that one issue
- **cd ~/dotfiles && avatar-issue-watcher 2275** — Target — Dispatch issue 2275 of the cwd repo
- **cd ~/dotfiles && avatar-issue-watcher** — Manual — cwd mode: tick only this repo
- **avatar-issue-watcher --cwd ~/dotfiles** — Manual — Watch-list tick (not cwd mode), started from any directory
- **avatar-issue-watcher watch list** — Watch — Show the watch list
- **cd ~/dotfiles && avatar-issue-watcher watch add** — Watch — Add the cwd repo
- **avatar-issue-watcher watch add dEitY719/gh-verify-skills --path ~/para/project/skills** — Watch — Add a repo with its checkout path
- **avatar-issue-watcher watch remove dEitY719/equinest** — Watch — Drop a repo
- **avatar-issue-watcher label list** — Label — Show the excluded labels
- **avatar-issue-watcher label add 보류** — Label — Also skip issues labelled 보류
- **avatar-issue-watcher label remove TODO** — Label — Dispatch TODO issues again
- **aicron add avatar-issue-watcher --schedule '*/4 * * * *'** — Periodic — Install the shipped aicron job
- **aicron status avatar-issue-watcher --json | jq .last_exit** — Periodic — Exit code of the last run
- **aicron run avatar-issue-watcher --dry-run** — Periodic — Run the job once by hand
- **crontab: */4 * * * * avatar-issue-watcher --cwd ~ >> ~/.local/state/avatar-issue-watcher/cron.log 2>&1** — Periodic — Plain crontab line
- Note: inside a git repo without --cwd it runs in cwd mode (that repo only, no watch list)
- Note: from cron, pass --cwd or start in $HOME so the watch list is used

## 엣지케이스 / 의도된 동작

`avatar-issue-watcher` 의 소스 주석에만 있던 동작들. 출처는
`shell-common/tools/custom/avatar_issue_watcher.sh` 의 `_iw_process_issue()`,
`_iw_issue_worktree()`, `_iw_main_checkout()` (#2281).

- 디스패치는 **탭을 열기 전에 이슈 worktree 를 확보한다.** main 체크아웃의
  `git worktree list` 에서 브랜치 `wt/issue-<N>/*` 인 worktree 를 찾아 재사용하고
  (여러 개면 index 가 가장 큰 것), 없으면 main 체크아웃에서
  `gwt spawn --wt-name issue-<N>` 을 실행한다. 경로는
  `<main 의 부모>/<project>-issue-<N>-<k>`, 브랜치는 `wt/issue-<N>/<k>`.
  herdr 탭은 그 worktree 를 cwd 로 열리고, `/gh-flow:wave <N>` 은 그 worktree 를
  재사용 모드로 채택한다.
- worktree 확보는 **이슈당 1회, 재시도 루프 밖**에서 한다. 재시도와 다음 tick 은
  같은 worktree 를 재사용하므로 `issue-<N>-2` 같은 중복이 생기지 않는다.
- worktree 를 못 얻으면 그 이슈는 **디스패치하지 않고** 에러
  (`Not dispatching <repo>#<N> — could not acquire a wt/issue-<N> worktree ...`)
  만 남긴다. main 체크아웃에서 세션을 여는 폴백은 없다.
- 실패한 attempt 정리는 **탭만 닫는다.** worktree 는 작업 보존을 위해 남기며,
  제거는 `gwt teardown` 몫이다.
- `gwt` 는 interactive guard 뒤의 셸 함수라 cron 에서는 그냥 부를 수 없다.
  watcher 는 서브셸 안에서 `DOTFILES_FORCE_INIT=1` 로 `functions/git_worktree.sh`
  와 `git_worktree_spawn.sh` 를 source 해 실행하므로 watcher 의 cwd 는 바뀌지 않는다.
  `--ai`/`--user`/`--launch` 는 쓰지 않는다 — agent 와 계정은 herdr pane 쪽이 정한다.
- repo 경로는 언제나 **main 체크아웃으로 정규화**된다
  (`git rev-parse --git-common-dir` 의 부모). worktree 안에서 cwd 모드로 실행하거나
  `watch add` 를 실행해도, watch list 에 이미 worktree 경로가 저장돼 있어도
  main 체크아웃 기준으로 동작한다.

## 소스

- `shell-common/functions/avatar_issue_watcher.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
