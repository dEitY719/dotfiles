# gwt

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/git_worktree.sh` 의 row 함수가 SSOT 입니다.
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
    - teardown gwt teardown [--force] [--keep-branch]       cleanup current/all worktree(s)
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

- **syntax** — gwt teardown [--all|-a|all] [--force] [--keep-branch] — Cleanup AI worktree(s)
- **context** — Single mode: run inside a worktree — Syncs main repo after cleanup
- **all mode** — Run from main repo or any worktree — Tears down every non-main worktree
- **flags** — --force / --keep-branch — Discard changes / keep branch

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gwt.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/git_worktree.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
