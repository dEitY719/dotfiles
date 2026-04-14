# Git worktree 컨텍스트 감지

## Context

- **출처**: [PR #130](https://github.com/dEitY719/dotfiles/pull/130) — `gwt teardown` 에러 메시지에서 "사용자가 main repo 에 있는지 worktree 에 있는지"를 감지해야 했음
- **커밋**: `de96848`, `6ea9531` (non-repo early-exit 추가)
- **파일**: `shell-common/functions/git_worktree.sh:567-611`

worktree 관련 헬퍼를 작성할 때 "현재 pwd 가 main repo 인가, 아니면 worktree
내부인가?"를 구분해야 하는 경우가 자주 생깁니다. 매번 직접 구현하는 것보다
확립된 3줄 패턴을 재사용하면 됩니다.

## Pattern

`git rev-parse --git-dir` 와 `git rev-parse --git-common-dir` 의 출력이
**같으면 main repo**, **다르면 worktree** 입니다.

- main repo: `git-dir` == `.git` 디렉토리 == `git-common-dir`
- worktree: `git-dir` == `.git/worktrees/<name>/` (개별 metadata), `git-common-dir` == `.git` (공유)

두 명령은 git repo 가 아닌 곳에서 실패 (exit 128) 하므로 `||` 로 early-exit 도
동시에 처리할 수 있습니다.

## Code

```sh
local _git_common _git_dir _in_worktree=false

# non-repo 에서 early-exit
_git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
    ux_error "Not inside a git repository"
    return 1
}

_git_dir="$(git rev-parse --git-dir 2>/dev/null)"
[ "$_git_dir" != "$_git_common" ] && _in_worktree=true

# worktree 또는 main repo 의 절대 경로
local _toplevel
_toplevel="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

## 실제 출력 예시

```sh
# main repo 안
$ cd ~/dotfiles
$ git rev-parse --git-dir
.git
$ git rev-parse --git-common-dir
.git
# → 같음 → main repo

# worktree 안
$ cd ~/dotfiles-claude-2
$ git rev-parse --git-dir
/home/bwyoon/dotfiles/.git/worktrees/dotfiles-claude-2
$ git rev-parse --git-common-dir
/home/bwyoon/dotfiles/.git
# → 다름 → worktree
```

## When to use

**적용하기 좋은 경우**
- worktree 전용 동작과 main repo 전용 동작을 분기하는 헬퍼 함수
- 에러 메시지에서 "사용자가 잘못된 위치에서 명령을 실행했는지" 판단
- 같은 명령이 위치에 따라 의미가 달라지는 자체 정리(self-cleanup) 명령

**불필요한 경우**
- 단순히 repo root 경로만 필요 — `git rev-parse --show-toplevel` 하나로 충분
- 브랜치 이름만 필요 — `git rev-parse --abbrev-ref HEAD` 로 충분

## 주의점

- `emulate -L sh` 를 쓰는 zsh-호환 POSIX 함수 안에서는 `local` 이 동작 —
  shellcheck 가 SC3043 를 경고하지만 기존 `git_worktree.sh` 패턴이라 무시 가능
- `2>/dev/null` 는 필수 — non-repo 에서 stderr 로 `fatal: not a git repository`
  가 새면 사용자 혼란

## Related

- **구현**: `shell-common/functions/git_worktree.sh:567-611` (`git_worktree_teardown`)
- **관련 learning**: [`ux-color-hierarchy.md`](./ux-color-hierarchy.md) — 이 감지 결과로 메시지를 분기한 방식
- **git 문서**: `git-rev-parse(1)` — `--git-dir`, `--git-common-dir`, `--show-toplevel`
