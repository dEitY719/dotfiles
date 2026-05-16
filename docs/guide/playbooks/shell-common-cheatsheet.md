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
