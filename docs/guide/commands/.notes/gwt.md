`gwt teardown` 의 소스 주석에만 있던 동작들. 출처는
`shell-common/functions/git_worktree_spawn.sh` 의 `_gwt_commits_safe()` /
`_gwt_main_checkout_preflight()` / `_gwt_teardown_one_inplace()` (#2276).

- 미푸시 판정: HEAD 가 **어느 원격 브랜치에든** 도달 가능하면(`git branch -r --contains HEAD`)
  커밋이 보존된 것으로 보고 통과한다. upstream 이 없어도, origin/main 에 미병합이어도
  된다. 이때 `Commits preserved on remote: origin/<x>` 를 안내하고 push 안내는 나오지 않는다.
  브랜치 자체는 미병합이라 `--force` 없이는 삭제되지 않고 경고와 함께 남는다.
- 메인 repo pre-flight: 워크트리를 지우기 **전에** 메인 repo 가 main 으로 checkout 될 수
  있는지 본다. main 브랜치 부재, unmerged 경로, 또는 main 과 현재 HEAD 사이에서 달라지는
  dirty/untracked 경로가 있으면 아무것도 지우지 않고 중단한다. main 과 무관한 dirty 파일은
  막지 않는다(git checkout 이 그대로 들고 간다). `--force` 로도 메인 repo 변경은 덮어쓰지 않는다.
- 그래도 checkout 이 실패하면(예: main 을 다른 워크트리가 사용 중) git stderr 를 `git: ...` 로
  보여주고, 워크트리는 이미 제거됐으며 브랜치가 남았다는 사실과 `git branch -D <branch>`
  정리 명령을 안내한다.
