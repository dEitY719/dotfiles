# gwt

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/gwt_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gwt --force`

## 호출

- Help 진입점: `gwt-help [section|--list|--all]`
- 통합 라우팅: `my-help gwt [section]`
- Alias: `gwt-help`

## 요약 (gwt-help)

- Usage: gwt-help [section|--list|--all]
- sections
    - add      gwt add <path> [branch] [start]              create worktree
    - list     gwt list|ls [--quick|--remote]               list worktrees
    - remove   gwt remove <path|name|all> [--force]         delete worktree dir + branch
    - prune    gwt prune                                    clean stale .git/worktrees/ refs (no path)
    - spawn    gwt spawn <name> [--task|--base|--tmux|...]  create named worktree (AI workflow)
    - status   gwt status [<name>]                          per-worktree diagnostic
    - teardown gwt teardown [--all [-r]] [--force] [...]    cleanup current/all worktree(s)
    - details: gwt-help <section>  (example: gwt-help spawn)

## 섹션

### add

- **syntax** — gwt add <path> [<new-branch> [<start-point>]] — Create git-crypt-safe worktree
- **behavior** — Sparse checkout excludes encrypted paths — Keeps encrypted layout safe

### list

- **syntax** — gwt list | gwt ls [--quick|-q] [--remote|-r] — List linked worktrees
- **default** — PATH/BRANCH/STATE/AGE/NEXT columns — Local signals (no network)
- **--quick** — path/commit/branch only — Legacy output
- **--remote** — Adds PR state via batched gh CLI call — One network call regardless of N
- **states** — dirty/ahead/pr-open/pr-merged/merged/... — See 'gwt-help status' for full list

### status

- **syntax** — gwt status [<name>] — Per-worktree diagnostic
- **no arg** — status for the worktree containing $PWD — Single-worktree mode
- **<name>** — Matches *-<name>-* like 'gwt remove' — Fails if multiple match
- **rows** — Path/Branch/HEAD/Upstream/Uncommitted/PR/Lock/Ahead-Behind — Mirrors gh-flow status
- **verdict** — dirty/ahead/pr-open/pr-merged/pr-closed/merged/stale/locked/prunable/clean — + Next action hint

### remove

- **syntax** — gwt remove <path|name|all> [--force] — Remove worktree + branch
- **name mode** — <name> matches *-<name>-* — Batch remove by worktree name
- **all mode** — all removes non-main worktrees — Batch cleanup
- **force** — --force — Force remove and branch delete

### prune

- **syntax** — gwt prune — Run: git worktree prune

### spawn

- **syntax** — gwt spawn <name> [--task <slug>] [--base <ref>] [--tmux|--launch [--ai <agent>]] [--user <account>] — Create named worktree
- **context** — Run from main repo only — Fails inside a worktree
- **name** — Free-form slug (required) — e.g. issue-11, login-fix
- **--ai** — AI agent (default: claude) — claude, codex, agy, opencode, cursor, copilot
- **--user** — Claude account for --tmux/--launch (only with --ai claude) — personal, work — default: $CLAUDE_DEFAULT_ACCOUNT
- **--tmux** — Runs <agent>-yolo in new tmux pane — Mutually exclusive with --launch
- **--launch** — cd into worktree + run <agent>-yolo inline — Current shell, no tmux
- **example** — gwt spawn issue-11 --tmux --ai codex — Free-form name + codex agent
- **example** — gwt spawn feat --launch — spawn -> cd -> claude-yolo (one shot)
- **example** — gwt spawn feat --launch --user work — spawn -> cd -> claude-yolo --user work

### teardown

- **syntax** — gwt teardown [--all|-a|all] [--recursive|-r] [--force] [--keep-branch] — Cleanup AI worktree(s)
- **context** — Single mode: run inside a worktree — Syncs main repo after cleanup
- **all mode** — Run from main repo or any worktree — Tears down every non-main worktree
- **recursive** — --all --recursive|-r from a parent dir — Every main repo directly under $PWD (one prompt)
- **flags** — --force / --keep-branch — Discard changes / keep branch
- **safe commits** — HEAD on any remote branch — Counts as saved -- no push needed
- **main pre-flight** — Main repo must check out main — Checked before removal; --force never overwrites it

## 엣지케이스 / 의도된 동작

`gwt teardown` 의 소스 주석에만 있던 동작들. 출처는
`shell-common/functions/git_worktree_spawn.sh` 의 `_gwt_commits_safe()` /
`_gwt_main_checkout_preflight()` / `_gwt_teardown_one_inplace()` (#2276).

- 미푸시 판정: HEAD 가 **어느 원격 브랜치에든** 도달 가능하면(`git branch -r --contains HEAD`)
  커밋이 보존된 것으로 보고 통과한다. upstream 이 없어도, origin/main 에 미병합이어도
  된다. 이때 `Commits preserved on remote: origin/<x>` 를 안내하고 push 안내는 나오지 않는다.
  teardown 의 fetch 는 `--prune` 이라 원격에서 삭제된 브랜치의 stale ref 는 믿지 않는다.
  브랜치 자체는 미병합이라 `--force` 없이는 삭제되지 않고 경고와 함께 남는다.
- 메인 repo pre-flight: 워크트리를 지우기 **전에** 메인 repo 가 main 으로 checkout 될 수
  있는지 본다. main 브랜치 부재, unmerged 경로, 다른 워크트리가 main 을 점유, 또는 main 과 현재 HEAD 사이에서 달라지는
  dirty/untracked 경로가 있으면 아무것도 지우지 않고 중단한다. main 과 무관한 dirty 파일은
  막지 않는다(git checkout 이 그대로 들고 간다). `--force` 로도 메인 repo 변경은 덮어쓰지 않는다.
- 그래도 checkout 이 실패하면(예: 메인 repo 의 `index.lock` 이 남아 있음) git stderr 를 `git: ...` 로
  보여주고, 워크트리는 이미 제거됐으며 브랜치가 남았다는 사실과 `git branch -D <branch>`
  정리 명령을 안내한다.

## 소스

- `shell-common/functions/gwt_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
