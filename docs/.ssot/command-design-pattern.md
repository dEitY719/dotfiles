# Shell Command Design Pattern

## 목적

`shell-common/functions/*.sh`의 함수형 명령어를 일관된 **dispatcher + private sub-function** 구조로 작성하기 위한 내부 아키텍처 SSOT다.

> **먼저 전달 방식부터 결정하라.** 이 문서는 명령을 **함수로 제공하기로 정한 뒤**의 내부 구조다. 함수 vs PATH 실행파일 결정은 한 단계 위 축 — [`command-delivery-model.md`](./command-delivery-model.md) 참조.

사용자 표면(`*-help` 출력 형식·15줄 정책·`ux_bullet` 계층 등)은 [`command-guidelines.md`](./command-guidelines.md)가 정의한다. 이 문서는 그 아래 layer — 명령어의 **내부 구조**를 다룬다.

## 적용 범위

- `shell-common/functions/*.sh` 내 모든 함수형 명령어
- 단일 동작 함수(simple function) 및 멀티 서브커맨드 함수(dispatcher) 모두
- `bash/`, `zsh/` 로더에서 alias로 노출되는 public 진입점

## 1. 명명 규칙

| 대상 | 규칙 | 예시 |
|------|------|------|
| Public 함수 (dispatcher/main) | `snake_case` | `git_branch`, `git_worktree` |
| Private sub-function | `_<prefix>_<verb>` | `_gb_clean_local`, `_gwt_help_rows_add` |
| Public alias (user-facing) | `dash-form` | `gb`, `gwt`, `git-clean-local` (deprecated) |
| Help 함수 (inline) | `_<prefix>_help` | `_gb_help` |
| Help 함수 (standalone) | `<topic>_help` + alias `<topic>-help` | `gwt_help` / `gwt-help` |

## 2. Command 유형 결정 기준

```
단일 동작? ──Yes──> Type 1: Simple Function
     │
     No
     │
서브커맨드 분리가 필요?
     │
     ├── 서브커맨드가 동사(verb) 형태 (add/list/spawn/teardown)
     │        └──> Type 2A: Positional Dispatcher (gwt 패턴)
     │
     └── 서브커맨드가 기존 flag(-D)에 중첩되거나
         원래 명령의 flag passthrough를 유지해야 할 때
                  └──> Type 2B: Flag-triggered Dispatcher (gb 패턴)
```

## 3. Type 1: Simple Function

단일 책임 함수. dispatcher 없이 직접 구현한다.

```sh
example_setup() {
    # 구현
}

alias example-setup='example_setup'
```

- Help는 `example-help` (별도 help 함수)로 등록한다.
- Help 표준은 [`command-guidelines.md`](./command-guidelines.md) 참조.

## 4. Type 2A: Positional Dispatcher (gwt 패턴)

서브커맨드가 **동사 형태 positional arg**인 경우.

### 구조 템플릿 (Type 2A)

```sh
# Private sub-functions
_<prefix>_<verb>() {
    # 구현
}

_<prefix>_<verb2>() {
    # 구현
}

# Dispatcher
<topic>() {
    case "${1:-}" in
        <verb>)   shift; _<prefix>_<verb> "$@" ;;
        <verb2>)  shift; _<prefix>_<verb2> "$@" ;;
        -h|--help|help|"")
            [ $# -gt 0 ] && shift
            <topic>_help "$@"   # standalone help, also reachable via <alias>-help
            ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: <alias> help"
            return 1
            ;;
    esac
}

alias <alias>='<topic>'
```

`-h|--help|help|""` invokes `<topic>_help` directly (no `return 1`) so users
discover help through the natural entry point (`gwt`, `gwt -h`, `gwt help
spawn`) instead of being told to learn a separate `<alias>-help` form. Passing
`"$@"` forwards a section name (`<alias> help spawn` → `<topic>_help spawn`).
The `<alias>-help` alias is preserved as a backward-compatible shortcut.

### 참조 구현: `gwt`

파일: `shell-common/functions/git_worktree.sh`

```sh
gwt() {
    case "${1:-}" in
        add)      shift; git_worktree_add "$@" ;;
        list|ls)  shift; git_worktree_list "$@" ;;
        spawn)    shift; git_worktree_spawn "$@" ;;
        teardown) shift; git_worktree_teardown "$@" ;;
        -h|--help|help|"")
            [ $# -gt 0 ] && shift
            gwt_help "$@" ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: gwt help"
            return 1 ;;
    esac
}
```

## 5. Type 2B: Flag-triggered Dispatcher (gb 패턴)

기존 flag(`-D`, `-f` 등)에 서브타입을 **중첩**하는 형태. 기존 명령의 **passthrough를 보존**해야 할 때 사용한다.

### 구조 템플릿 (Type 2B)

```sh
# Inline help (5줄 이내)
_<prefix>_help() {
    ux_info "Usage: <alias> [-FLAG <subtype>] [native-flags...]"
    ux_bullet "sub-commands"
    ux_bullet_sub "<alias> -FLAG <subtype1>    설명"
    ux_bullet_sub "<alias> -FLAG <subtype2>    설명"
    ux_bullet_sub "<alias> [flags]             passthrough to <underlying-cmd>"
}

# Private sub-functions
_<prefix>_<subtype1>() { :; }
_<prefix>_<subtype2>() { :; }

# Dispatcher
<topic>() {
    case "${1:-}" in
        -FLAG)
            case "${2:-}" in
                <subtype1>) shift 2; _<prefix>_<subtype1> "$@" ;;
                <subtype2>) shift 2; _<prefix>_<subtype2> "$@" ;;
                *)          <underlying-cmd> "$@" ;;
            esac
            ;;
        -h|--help|help) _<prefix>_help ;;
        *)              <underlying-cmd> "$@" ;;
    esac
}

alias <alias>='<topic>'
```

`<underlying-cmd> "$@"` (not `<underlying-cmd> -FLAG "$@"`): when 알 수 없는 subtype 가 들어오면 `"$@"` 가 이미 원본 `-FLAG <subtype>` 을 갖고 있어 그대로 위임하면 된다. 중복 `-FLAG` 를 추가하지 않는다.

### 참조 구현: `gb`

파일: `shell-common/functions/git.sh`

```sh
_gb_help() {
    ux_info "Usage: gb [-D local] [-D remote [<remote>]] [git-branch-flags...]"
    ux_bullet "sub-commands"
    ux_bullet_sub "gb -D local               delete local branches (keeps: main + current + keywords)"
    ux_bullet_sub "gb -D remote [<remote>]   delete remote-tracking branches (default: origin, keeps: main/master)"
    ux_bullet_sub "gb [flags]                passthrough to git --no-pager branch"
}

git_branch() {
    case "${1:-}" in
        -D)
            case "${2:-}" in
                local)  shift 2; _gb_clean_local "$@" ;;
                remote) shift 2; _gb_clean_remote "$@" ;;
                *)      git --no-pager branch "$@" ;;
            esac
            ;;
        -h|--help|help) _gb_help ;;
        *)              git --no-pager branch "$@" ;;
    esac
}

alias gb='git_branch'
```

## 6. Passthrough 규칙

| 상황 | 처리 |
|------|------|
| 알 수 없는 서브커맨드 (Type 2A) | `ux_error + return 1` — passthrough 없음 |
| 알 수 없는 flag (Type 2B) | underlying command로 passthrough |
| flag 뒤 알 수 없는 subtype (Type 2B) | underlying command로 passthrough |
| `-h/--help/help` | 항상 inline help 표시 |

**이유**: Type 2A는 완전히 새로운 인터페이스이므로 오타를 차단해야 한다. Type 2B는 기존 명령의 확장이므로 미처리 케이스를 원본으로 위임해야 한다.

## 7. Help 통합 전략

| Help 유형 | 언제 사용 | 구현 위치 |
|-----------|-----------|-----------|
| Inline help (`_<prefix>_help`) | Type 2B, 또는 sub-command 수 3개 이하 | dispatcher 파일 내 |
| Standalone help (`<topic>_help` + `<topic>-help`) | Type 2A, 또는 sub-command 수 4개 이상 | 별도 `*_help.sh` 파일 |

[`command-guidelines.md`](./command-guidelines.md)의 help 표준(15줄 이내, `ux_bullet`/`ux_bullet_sub`, `--all`/`<section>` 분리)은 standalone help에 완전 적용된다.

Type 2A 의 `-h|--help|help|""` 케이스는 `<topic>_help "$@"` 를 직접 호출한다. `<alias>-help` alias 는 backward-compat 단축형으로 동시 제공한다 (예: `gwt help spawn` ≡ `gwt-help spawn`).

## 8. Deprecated Alias 전략

기존 명령을 dispatcher 아래로 통합할 때, 하위 호환을 위해 thin wrapper alias를 유지한다.

```sh
alias git-clean-local='gb -D local'   # deprecated
alias gprune='gb -D remote'           # deprecated
```

- deprecated alias는 `# deprecated` 인라인 코멘트만 붙인다.
- deprecated alias 제거 시점은 별도 이슈로 결정한다.

## 9. SOLID 준수 기준

| 원칙 | 적용 방식 |
|------|-----------|
| **SRP** | dispatcher는 dispatch만 / private sub-function은 구현만 |
| **OCP** | 신규 sub-command = case 항목 추가만, 기존 코드 무변경 |
| **LSP** | passthrough로 기존 호출자 완전 호환 |
| **ISP** | private sub-function 간 상호 의존 없음 |
| **DIP** | `ux_*` 추상화 사용, 직접 `echo`/`printf` 금지 |
| **SSOT** | protected_keywords, default 값, 보호 브랜치 목록 — 각 함수 내 단일 정의 |

## 10. 테스트 요구사항

```bats
@test "<topic>: dispatcher function exists" { ... }
@test "<topic>: private sub-function <verb> exists" { ... }
@test "<topic>: alias <alias> maps to dispatcher" { ... }
@test "<topic>: -h shows help" { ... }
@test "<topic>: unknown sub-command returns error (Type 2A)" { ... }
@test "<topic>: unknown flag passes through (Type 2B)" { ... }
```

- bash/zsh 모두에서 실행
- shellcheck/shfmt 통과 필수

## 11. 변경 절차

1. 이 문서를 먼저 검토하여 Type 결정
2. private sub-function 먼저 작성 + 단위 테스트
3. dispatcher 작성 + passthrough 케이스 확인
4. help 통합 (`_help` inline 또는 별도 `*-help.sh`)
5. deprecated alias 정리
6. shellcheck/shfmt/bats 통과 확인
7. PR body에 SOLID 준수 근거 표 포함

## 12. 참조

- [`command-guidelines.md`](./command-guidelines.md) — Help interface SSOT (사용자 표면)
- `shell-common/tools/ux_lib/UX_GUIDELINES.md` — UX output rules
- `shell-common/functions/git_worktree.sh` — Type 2A 참조 구현 (gwt)
- `shell-common/functions/git.sh` — Type 2B 참조 구현 (gb)
- Issue #558 — gb 통합 설계 근거
- PR #559 — gb 구현 검증
- Issue #566 — 본 문서 추출 근거
