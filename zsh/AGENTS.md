# Module Context

- **Purpose**: Zsh-specific configuration and application integrations
- **Entry Point**: `main.zsh` — sources `shell-common` then zsh-specific modules
- **Structure**: `app/`(zsh 앱: git, p10k, zsh utilities) · `env/`(zsh-only env) · `main.zsh`(loader)
- **Dependencies**: `shell-common/` (공유 유틸리티), Powerlevel10k (옵션 테마)

# Operational Commands

- **Reload**: `source ~/.zshrc` 또는 `exec zsh`
- **Lint**: `mise run lint-sh` (`bash/` 자동 커버) — `zsh/` 만 직접 검사는 `shellcheck -x -e SC1090,SC1091 zsh/**/*.zsh` (shellcheck 가 zsh 지원하는 경우)
- **Syntax check**: `zsh -n <file>`
- **Theme config**: `p10k configure`

# Loading Order (`main.zsh`)

1. Shell detection (zsh 아니면 exit)
2. Directory setup (`DOTFILES_ROOT`, `SHELL_COMMON`, `ZSH_DOTFILES`)
3. `safe_source` 헬퍼 정의
4. Common env (`shell-common/env/*.sh`)
5. Zsh-only env (`zsh/env/*.sh`)
6. UX library (`shell-common/tools/ux_lib/ux_lib.sh`)
7. Common aliases / functions / 외부 도구 / 프로젝트
8. Zsh utilities (`zsh/util/*.zsh`)
9. Zsh applications (`zsh/app/*.zsh`)

# Golden Rules

## Zsh-Specific Features

- **DO**: zsh array / associative array / parameter expansion / `setopt` 자유 사용
- **DO**: 함수 안에서는 `local`, 글로벌은 `typeset`
- **DON'T**: `local`을 함수 밖에서 사용 (`main.zsh`는 `_load_zsh_apps()`로 래핑)
- **DON'T**: bash 호환을 가정 — 항상 zsh 에서 실제 실행 검증

## Loading Discipline

- **DO**: `main.zsh` 로딩 순서 존중
- **DO**: 모든 파일 로드는 `safe_source` 사용
- **DON'T**: `~/.zshrc` 에서 직접 파일 source — `main.zsh` 우회 금지
- **DON'T**: zsh-only 기능을 위해 `shell-common/` 수정 — `zsh/` 에 새 파일을 만들 것

## Output Standards

- **DO**: `ux_lib` 함수 사용 (`ux_header`, `ux_success`, `ux_error`)
- **Exception**: ux_lib 로드 전 에러는 `echo ... >&2`
- ux_lib 는 shell-aware — zsh 분기 자동 처리

## File Naming

- Zsh-only 파일: `snake_case.zsh`
- 공유 파일: `shell-common/` 에 `.sh` 확장자
- 함수: `snake_case` 또는 `tool_command` (bash와 일관)

## Cross-shell Sourcing

`shell-common/` 에서 sourcing 할 때 `${BASH_SOURCE[0]}` 같은 bash-only 패턴 금지.
공식 패턴: `source "${SHELL_COMMON}/path/to/file.sh"`.
상세는 [`shell-common/AGENTS.md`](../shell-common/AGENTS.md) → "Bash/Zsh Sourcing Rules".

# Testing Strategy

```bash
# Syntax
zsh -n zsh/app/myapp.zsh

# Source + 함수 확인
zsh -c "source zsh/main.zsh && type myfunction"

# 클린 zsh
zsh -f
source ~/dotfiles/zsh/main.zsh
```

체크리스트: zsh 전용 기능 사용 / bash-only 문법 회피 / 의도 시 `[ -n "$ZSH_VERSION" ]` 가드 /
공유 의도면 `shell-common/` 으로 이전.

# When to Use `zsh/` vs `shell-common/`

- **`zsh/`**: zsh-only 문법, zsh 플러그인, zsh-specific 동작 (예: p10k)
- **`shell-common/`**: POSIX 호환, bash/zsh 공유 (예: git 헬퍼)

# Maintenance

새 zsh 모듈 추가:

1. `zsh/app/<module>.zsh` 생성
2. zsh 전용 기능 자유 사용
3. `ux_lib` 출력
4. `zsh -n` + 수동 sourcing 검증
5. `main.zsh` 가 자동 로드함

# References

- **[Shell Common](../shell-common/AGENTS.md)** — POSIX 공유 유틸리티
- **[Bash Module](../bash/AGENTS.md)** — bash-specific (병렬 구조)
- **[UX Library](../shell-common/tools/ux_lib/AGENTS.md)** — 출력 스타일
- **[Root Context](../AGENTS.md)** — 프로젝트 표준
- **[Powerlevel10k](https://github.com/romkatv/powerlevel10k)** — 테마 문서
