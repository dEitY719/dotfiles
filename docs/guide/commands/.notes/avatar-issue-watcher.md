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
