# `shell-common/` 개발 치트시트

`shell-common/AGENTS.md` 의 "Common Mistakes & Fixes" 와 "Implementation Patterns"
를 분리한 playbook. AGENTS.md 100-line policy 를 지키면서 자주 헷갈리는
패턴/실수 예시를 한 곳에서 참조하기 위함이다.

## File Structure Template

```sh
#!/bin/sh
# shell-common/<category>/<module>.sh
# POSIX-compatible — no bash/zsh-specific syntax

_have() {
    command -v "$1" >/dev/null 2>&1
}

# Optional dependency guard
if ! _have mytool; then
    return 0
fi

alias myalias='command --flag'
export MY_VAR="value"
```

## Shell Detection Pattern

`bash`/`zsh`-specific 기능이 필요할 때:

```sh
if [ -n "$BASH_VERSION" ]; then
    IFS=':' read -r -a array <<<"$PATH"
elif [ -n "$ZSH_VERSION" ]; then
    array=("${(@s/:/)PATH}")
else
    OLD_IFS="$IFS"; IFS=':'; set -- $PATH; IFS="$OLD_IFS"
fi
```

## Naming Conventions

- 파일: `snake_case.sh`
- 함수: `snake_case` 또는 `tool_command` (예: `git_help`, `uv_help`)
- alias: dash 가능 (예: `bat-help` → `bat_help`)
- private 헬퍼: `_` 접두사 (`_have`, `_need`)

## Common Mistakes & Fixes

### 1. `tools/custom/` 에 함수 정의 (자동 sourcing 안 됨)

```sh
# WRONG — tools/custom/ 은 자동 source 되지 않음
tools/custom/my_function.sh   # contains: my_function() { ... }

# RIGHT — functions/ 로 이동
functions/my_function.sh      # contains: my_function() { ... }
```

`tools/custom/` 은 명시적 실행 (`bash tools/custom/setup.sh`) 전용이다.

### 2. 실행 스크립트가 자동 sourcing 되어 부작용 발생

```sh
# WRONG — 매 로그인마다 npm install 실행
functions/setup_dev.sh   # contains: npm install ...

# RIGHT — tools/custom/ 로 이동, 명시적 실행
tools/custom/setup_dev.sh
```

### 3. 하드코드 경로

```sh
# WRONG
script_path="/home/bwyoon/dotfiles/shell-common/tools/custom/setup.sh"

# RIGHT
script_path="${SHELL_COMMON}/tools/custom/setup.sh"
```

`$SHELL_COMMON`, `$DOTFILES_ROOT`, `$HOME` 사용.

### 4. `tools/integrations/` vs `tools/custom/` 혼동

- **`integrations/`**: 외부 도구 자동 sourcing 래퍼 (예: `npm.sh`, `docker.sh`)
- **`custom/`**: 명시적 실행 스크립트 (예: `install_npm.sh`, `setup_docker.sh`)

### 5. 한 파일에 여러 책임 혼재

```sh
# WRONG — env + alias + function 한 파일
git.sh:
  export GIT_EDITOR="vim"
  alias gs="git status"
  git_help() { ... }

# RIGHT — 책임별 분리
aliases/git.sh           # alias gs="git status"
env/git.sh               # export GIT_EDITOR="vim"
functions/git_help.sh    # git_help() { ... }
```

### 6. shell-common 에 bash-only 문법

```sh
# WRONG
my_array=("$@")
files=("${BASH_SOURCE[0]%/*}"/files/*)

# RIGHT — POSIX
my_array="$@"
for f in "${SHELL_COMMON}"/files/*; do ... done

# OR with detection
if [ -n "$BASH_VERSION" ]; then
    my_array=("$@")
elif [ -n "$ZSH_VERSION" ]; then
    my_array=("${(@s/ /)$@}")
fi
```

### 7. 공유 함수 파일을 `find`/PATH 탐색으로 자가 발견

```sh
# WRONG — 비대화형 셸에서 $SHELL_COMMON 이 비면 이름이 같은 아무 체크아웃이나 잡힌다
src=$(find "$HOME" -name gh_pr_review.sh -path '*/shell-common/functions/*' | head -1)
. "$src"

# RIGHT — 항상 fallback 패턴으로 고정된 한 곳에서만 source
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_review.sh"
```

디스크에는 `dotfiles` 라는 이름의 디렉터리가 여럿 존재한다 (예: 다른 repo 의
submodule 체크아웃). Claude Code subagent 처럼 `$SHELL_COMMON` / `$DOTFILES_ROOT`
가 unset 인 비대화형 컨텍스트에서 탐색으로 파일을 고르면, 수 주 묵은 사본이
정본 대신 sourced 되어 `Unknown --ai value: 'hermes'` 같은 엉뚱한 에러로 나타난다
(#1454). 3번이 하드코드 경로를 금지한다면 이 항목은 **탐색 자체**를 금지한다.

규칙을 어긴 코드를 위한 advisory 안전망으로
`_dotfiles_root_warn_if_foreign_source` (`shell-common/functions/dotfiles_root.sh`)
가 있다. 자신의 실제 load 경로가 `$HOME/dotfiles` 와 다른 git 저장소면 stderr 에
WARN 한 블록을 찍는다. 같은 저장소의 linked worktree 는 경고하지 않으며, 절대
실행을 막지 않는다. 비대화형 skill 호출자가 직접 source 하는 shell-common 파일
(예: `gh_pr_review.sh`, `gh_host.sh`)은 이 가드를 켜야 한다 — 정확한 복붙 스니펫은
아래 "Foreign-Checkout Guard Snippet" 참고. `${BASH_SOURCE[0]-}` 단독으로는 zsh 에서
항상 비어 있어 가드가 영구히 무력화되므로 (zsh 는 `$0` 을 리바인드) 단독 사용 금지.

## Foreign-Checkout Guard Snippet (#1454 / #1505)

비대화형 skill 이 직접 source 하는 `shell-common/functions/*.sh` 파일(git hook 이
source 하는 파일 포함)의 표준 가드. 파일 최상단, 함수 정의 이전에 붙인다. `LABEL`
만 파일마다 바꾼다 — 나머지는 7개 파일에 걸쳐 문자 그대로 동일해야 한다(자기 경로
탐지는 zsh 의 `FUNCTION_ARGZERO` 특성상 공유 함수로 옮길 수 없어 파일마다 반복이
불가피하다; probe + 호출 + `#724` 진단은 `_dotfiles_root_guard_self` 하나로 이미
SSOT 화됨):

```sh
if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "LABEL"
else
    printf '[LABEL] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper
```

`else` 분기를 빼먹지 말 것 — `dotfiles_root.sh` 자체가 없거나 source 에 실패해
`_dotfiles_root_guard_self` 가 정의되지 않은 경우, 이 `else` 가 없으면 진단 메시지
없이 조용히 가드가 꺼진다 (#1505 에서 실제로 빠졌던 회귀).

## Tool Integration UX-lib Guard

`tools/integrations/<tool>.sh` 의 표준 ux_lib guard:

```sh
if ! type ux_header >/dev/null 2>&1; then
    _dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _dir
fi
```

## Splitting Large Files

200줄 초과 시: 기능 경계로 분할, 명확한 새 이름, `bash/main.bash` /
`zsh/main.zsh` 의 참조 갱신.

## Known Issues

- **함수가 zsh 에서 안 보임**: `export -f` (bash-only) 사용 → 파일 상단에
  `[ -n "$BASH_VERSION" ] || return 0` 가드 추가
- **Array 문법 충돌**: shell detection 또는 POSIX `set --` loop 사용

## References

- 정책 SSOT: [`/docs/.ssot/command-guidelines.md`](../.ssot/command-guidelines.md)
- 라우터: [`/shell-common/AGENTS.md`](../../shell-common/AGENTS.md)
- UX 가이드라인: [`/shell-common/tools/ux_lib/UX_GUIDELINES.md`](../../shell-common/tools/ux_lib/UX_GUIDELINES.md)
