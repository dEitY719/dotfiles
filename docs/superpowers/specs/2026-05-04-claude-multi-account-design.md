# Claude Code Multi-Account Configuration Design

Issue: [#287](https://github.com/dEitY719/dotfiles/issues/287)
Phase: **1 (이번 작업)** — `claude_yolo` dispatcher + 매핑 + setup + 마이그레이션
Phase 2 (별도 follow-up): `gwt --launch` 의 `--user` 통합

## Overview

Claude Code 의 단일 머신 다중 계정 동시 사용을 지원한다. `CLAUDE_CONFIG_DIR`
환경변수로 계정별 설정 디렉토리를 분리하는 우회 방법을 dotfiles 의
SSOT/SOLID 패턴에 맞게 표준화한다.

**계정**:
- `personal` — deity719@gmail.com (MAX 요금제, 개인)
- `work`     — deity719g@gmail.com (Team 요금제, 회사)

**대상 PC** (3대):

| PC | 사용 계정 | Default 계정 |
|---|---|---|
| External-PC | personal + work | personal |
| Home-PC     | personal + work | personal |
| Internal-PC | work 만 (사내)  | work |

**목표**:
- 두 계정을 같은 머신에서 동시에 다른 터미널/VSCode pane 으로 실행 가능.
- SSOT: 계정 매핑은 한 함수에서만 정의, 별칭/setup/진단 모두 거기서 파생.
- 멱등성: 3대 PC 어디서든 같은 setup 함수 N회 실행해도 동일 결과.
- OCP: 3번째 계정 추가 시 매핑 한 줄 + ENABLED 한 단어로 끝.

**비목표 (Phase 1)**:
- `gwt spawn --launch --ai claude --user work` 통합 — Phase 2.
- Windows PowerShell 지원 — 이 dotfiles 레포 범위 외.
- 프로젝트별 `.env` 자동 로딩 — 별도 follow-up.

## 합의된 설계 결정

| # | 결정 | 선택 |
|---|---|---|
| 1 | 명령어 표면 | **하이브리드**: 매핑 SSOT + `claude-yolo --user <name>` 1차 표면 + `claude-yolo-<name>` 단축 alias 자동 파생 |
| 2 | 디렉토리 구조 | **명시적 분리**: `~/.claude-personal/`, `~/.claude-work/`. `~/.claude/` 는 빈 디렉토리 (자연 가드) |
| 3 | 계정 이름 | `personal` / `work` (역할 기반, 이메일 변경 영향 없음) |
| 4 | 공유 자원 | settings.json, statusline-command.sh, skills/, docs/, plugins/, projects/GLOBAL/memory |
| 5 | 분리 자원 | .credentials.json, projects/(GLOBAL 외), sessions/, history.jsonl, agents/, backups/, cache/, debug/, downloads/, ide/, mcp-needs-auth-cache.json, file-history/, paste-cache/, session-env/ |
| 6 | plugins 공유 방식 | `~/.claude-shared/plugins/` 실데이터 + 양쪽 계정에서 symlink |
| 7 | PC 별 활성화 | `CLAUDE_ENABLED_ACCOUNTS` 화이트리스트 + `CLAUDE_DEFAULT_ACCOUNT` 오버라이드 (`shell-common/env/claude.local.sh`) |
| 8 | plain `claude` 차단 | 별도 alias hack 없음. `~/.claude/` 빈 디렉토리만으로 자연 가드 |

## 디렉토리 레이아웃

```
~/.claude/                              # 빈 디렉토리 (가드 효과)

~/.claude-shared/
└── plugins/                            # 양쪽 계정 공유 (실데이터)

~/.claude-personal/                     # External-PC, Home-PC
├── settings.json         -> ~/dotfiles/claude/settings.json           (symlink, 공유)
├── statusline-command.sh -> ~/dotfiles/claude/statusline-command.sh   (symlink, 공유)
├── skills/               <- ~/dotfiles/claude/skills                  (bind mount, 공유)
├── docs/                 <- ~/dotfiles/claude/docs                    (bind mount, 공유)
├── plugins/              -> ~/.claude-shared/plugins                  (symlink, 공유)
├── projects/GLOBAL/memory -> ~/dotfiles/claude/global-memory          (symlink, 공유)
├── .credentials.json     # 격리 (deity719@gmail.com)
├── projects/             # 격리 (GLOBAL/memory 만 공유)
├── sessions/, history.jsonl, ...                                      # 격리

~/.claude-work/                         # 모든 PC
├── (위와 동일한 6개 link/mount)
├── .credentials.json     # 격리 (deity719g@gmail.com)
└── ...                                                                # 격리
```

→ **두 계정 디렉토리는 거울 구조**. Internal-PC 에선 personal 디렉토리가 만들어지지 않음.

## 컴포넌트 (SOLID 책임 분리)

```
shell-common/
├── env/
│   ├── claude.sh                       # CLAUDE_DEFAULT_ACCOUNT, CLAUDE_ENABLED_ACCOUNTS 기본값
│   └── claude.local.example            # PC 별 오버라이드 템플릿 (Internal-PC 용)
│
├── tools/integrations/claude.sh
│   ├── _claude_resolve_account()       # 매핑 SSOT (case 디스패처) + ENABLED 필터
│   ├── claude_yolo()                   # dispatcher: --user 파싱, 환경 주입, branch guard
│   ├── _claude_yolo_register_aliases() # 단축 alias 자동 파생
│   ├── claude_accounts()               # CLI: status/list/setup/migrate
│   ├── claude_accounts_init()          # 멱등 setup (3대 PC 공통)
│   ├── claude_accounts_migrate()       # 1회 마이그레이션 (Home-PC 한정)
│   ├── claude_accounts_status()        # 진단 출력
│   ├── _claude_account_setup_one()     # 계정 1개 setup (link/mount)
│   ├── _claude_ensure_symlink()        # 멱등 symlink 헬퍼
│   └── _claude_ensure_bind_mount()     # 멱등 bind mount 헬퍼
│
└── (변경 없음) functions/git_worktree.sh
    └── _gwt_yolo_command(claude) -> "claude_yolo"   # Phase 2 에서 확장
```

**책임 분리**:
- **SSOT**: 계정 매핑은 `_claude_resolve_account` 단 한 곳.
- **SRP**: dispatcher 는 실행만, resolver 는 해석만, init 은 setup 만.
- **OCP**: 3번째 계정 추가 = case 한 줄 + ENABLED 한 단어. 다른 곳 무수정.
- **DIP**: 호출자(gwt 등)는 계정명 문자열만 통과 → dispatcher 가 해석.

## 1. 매핑 SSOT — `_claude_resolve_account`

shell-common 의 기존 패턴(`_gwt_yolo_command`)과 일관:

```sh
_claude_resolve_account() {
    case "$1" in
        --list)
            # ENABLED 화이트리스트 적용 (PC 별)
            for acct in $CLAUDE_ENABLED_ACCOUNTS; do
                _claude_resolve_account "$acct" >/dev/null 2>&1 && echo "$acct"
            done
            ;;
        --list-all)
            echo "personal work"   # 매핑 SSOT (디버깅용)
            ;;
        personal) echo "$HOME/.claude-personal" ;;
        work)     echo "$HOME/.claude-work" ;;
        *)        return 1 ;;
    esac
}
```

→ 새 계정 추가 = case 한 줄. `setup`/alias/`status` 모두 `--list` 호출
→ ENABLED 자동 반영. PC 별 분기 코드 0줄.

## 2. Dispatcher — `claude_yolo`

POSIX 안전 인자 재구성 (sentinel 패턴, eval 없음, 공백·따옴표 인자 안전):

```sh
claude_yolo() {
    account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

    # --user 가로채고 나머지는 위치 인자로 보존
    set -- "$@" "__CY_END__"
    while [ "$1" != "__CY_END__" ]; do
        case "$1" in
            --user)     account="$2"; shift 2 ;;
            --user=*)   account="${1#--user=}"; shift ;;
            *)          set -- "$@" "$1"; shift ;;
        esac
    done
    shift   # sentinel 제거

    # 계정 → CONFIG_DIR (SSOT 호출)
    config_dir=$(_claude_resolve_account "$account") || {
        ux_error "Unknown account: $account"
        ux_info  "Available: $(_claude_resolve_account --list)"
        return 1
    }
    [ -d "$config_dir" ] || {
        ux_error "Account directory missing: $config_dir"
        ux_info  "Run: claude-accounts setup"
        return 1
    }

    # main/master 가드 (기존 로직 유지)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
        case "$branch" in
            main|master)
                if [ -z "${CLAUDE_YOLO_STAY:-}" ]; then
                    new_branch="scratch/$(date +%m%d-%H%M%S)"
                    ux_warning "main 브랜치 감지 → ${new_branch} 로 전환 (bypass: CLAUDE_YOLO_STAY=1)"
                    git switch -c "$new_branch" || return 1
                fi
                ;;
        esac
    fi

    CLAUDE_CONFIG_DIR="$config_dir" command claude --dangerously-skip-permissions "$@"
}
alias claude-yolo='claude_yolo'
```

**핵심**:
- `command claude` 유지 → alias 루프 회피, NVM 경로 변경 면역.
- `CLAUDE_CONFIG_DIR` 한 줄 환경 주입 → child process 만 영향, side effect 없음.
- `--` 분리는 `case *)` 가 그대로 인자 보존하므로 자연 처리됨.

## 3. 단축 alias 자동 파생

```sh
_claude_yolo_register_aliases() {
    for acct in $(_claude_resolve_account --list); do
        eval "alias claude-yolo-${acct}='claude_yolo --user ${acct}'"
    done
}

_claude_yolo_register_aliases   # claude.sh 로드 시 1회
```

→ External/Home: `claude-yolo-personal`, `claude-yolo-work` 등장.
→ Internal: `claude-yolo-work` 만 등장 (`claude-yolo-personal` 부재).
→ 새 계정 추가 시 자동 등장. 수동 alias 정의 금지.

## 4. Setup — `claude_accounts_init` (멱등, 3대 PC 공통)

```sh
claude_accounts_init() {
    ux_header "Claude Accounts Setup"

    # 마이그레이션 미수행 가드 (기존 ~/.claude/ 에 실데이터가 있으면 안내)
    if [ -d "$HOME/.claude" ] && [ ! -d "$HOME/.claude-personal" ] && [ ! -d "$HOME/.claude-work" ]; then
        # 빈 디렉토리만 있으면 OK, 아니면 마이그레이션 권유
        if [ -n "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
            ux_warning "~/.claude/ 에 기존 데이터가 있습니다."
            ux_info    "먼저 마이그레이션을 실행하세요: claude-accounts migrate"
            return 1
        fi
    fi

    mkdir -p "$HOME/.claude-shared/plugins"
    mkdir -p "$HOME/.claude"   # 빈 디렉토리 (가드)

    for acct in $(_claude_resolve_account --list); do
        config_dir=$(_claude_resolve_account "$acct")
        _claude_account_setup_one "$acct" "$config_dir"
    done

    ux_success "All accounts ready"
    claude_accounts_status
}

_claude_account_setup_one() {
    acct="$1"
    cdir="$2"
    ux_section "Account: $acct ($cdir)"

    mkdir -p "$cdir"
    mkdir -p "$cdir/projects/GLOBAL"

    # 공유 6종
    _claude_ensure_symlink   "$DOTFILES_ROOT/claude/settings.json"           "$cdir/settings.json"
    _claude_ensure_symlink   "$DOTFILES_ROOT/claude/statusline-command.sh"   "$cdir/statusline-command.sh"
    _claude_ensure_symlink   "$HOME/.claude-shared/plugins"                  "$cdir/plugins"
    _claude_ensure_symlink   "$DOTFILES_ROOT/claude/global-memory"           "$cdir/projects/GLOBAL/memory"
    _claude_ensure_bind_mount "$DOTFILES_ROOT/claude/skills"                 "$cdir/skills"
    _claude_ensure_bind_mount "$DOTFILES_ROOT/claude/docs"                   "$cdir/docs"
}
```

**멱등 헬퍼**:
- `_claude_ensure_symlink src tgt`: 없으면 생성, 같은 target 이면 skip,
  다른 file 이면 timestamped 백업 후 재생성. 기존 `claude/setup.sh` 의
  `create_symlink` 패턴 재사용.
- `_claude_ensure_bind_mount src tgt`: `_is_mounted` 로 확인, 안 된 경우만
  `sudo mount --bind`. 기존 `claude_mount_skills` 패턴 재사용.

→ 3대 PC 어디서든 N회 실행해도 동일 결과 (첫 회 setup, 이후 모두 skip).

## 5. PC 별 오버라이드 — `claude.local.sh`

기존 `*.local.sh` 패턴(`development.local.example`, `proxy.local.example`,
`security.local.example`) 과 일관. `.local.sh` 는 `.gitignore` 로 제외.

**`shell-common/env/claude.sh`** (모든 PC, 기본값):

```sh
export CLAUDE_AUTO_MOUNT_SKILLS=1
export CLAUDE_AUTO_MOUNT_DOCS=1
export CLAUDE_DOC_GENERATOR=claude
export CLAUDE_SKILLS_PATH="${DOTFILES_ROOT}/claude/skills"

# 다중 계정 (신규)
export CLAUDE_DEFAULT_ACCOUNT="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
export CLAUDE_ENABLED_ACCOUNTS="${CLAUDE_ENABLED_ACCOUNTS:-personal work}"
```

**`shell-common/env/claude.local.example`** (신규 템플릿):

```sh
# claude.local.sh (template)
#
# 사용법:
#   1. 이 파일을 claude.local.sh 로 복사
#      cp claude.local.example claude.local.sh
#   2. 아래 값을 PC 환경에 맞게 수정
#   3. claude.local.sh 는 자동으로 로드됨 (.gitignore 에 의해 제외됨)
#
# Internal-PC (사내 PC, work 계정만 사용) 예시:
#   export CLAUDE_DEFAULT_ACCOUNT="work"
#   export CLAUDE_ENABLED_ACCOUNTS="work"
```

→ 3대 PC 매트릭스:

| PC | claude.local.sh | ENABLED | DEFAULT | `claude-yolo` 동작 |
|---|---|---|---|---|
| External-PC | (없음) | `personal work` | `personal` | personal 실행 |
| Home-PC     | (없음) | `personal work` | `personal` | personal 실행 |
| Internal-PC | 있음 (위 예시 그대로) | `work` | `work` | work 실행 |

## 6. CLI — `claude-accounts`

```sh
claude_accounts() {
    case "${1:-status}" in
        status)   claude_accounts_status ;;
        list)     _claude_resolve_account --list ;;
        setup)    claude_accounts_init ;;
        migrate)  claude_accounts_migrate ;;
        -h|--help|help) _claude_accounts_help ;;
        *)        ux_error "Unknown subcommand: $1"; _claude_accounts_help; return 1 ;;
    esac
}
alias claude-accounts='claude_accounts'
```

`claude-accounts status` 출력 예 (External-PC):

```
Claude Accounts Status
═══════════════════════════════════════
Default: personal (CLAUDE_DEFAULT_ACCOUNT)
Enabled: personal work
Shared:  ~/.claude-shared/plugins ✓

Account: personal
  Path:        ~/.claude-personal             ✓ exists
  Credentials: .credentials.json              ✓ logged in
  Settings:    symlink → dotfiles             ✓
  Statusline:  symlink → dotfiles             ✓
  Skills:      bind mount                     ✓
  Docs:        bind mount                     ✓
  Plugins:     symlink → ~/.claude-shared     ✓
  GLOBAL/mem:  symlink → dotfiles             ✓

Account: work
  Path:        ~/.claude-work                 ✓ exists
  Credentials: .credentials.json              ✗ NOT logged in
                → Run: claude-yolo --user work (browser opens)
  ...
```

## 7. 마이그레이션 — `claude_accounts_migrate` (1회, Home-PC 한정)

기존 `~/.claude/` 에 데이터가 있는 PC 전용. 멱등 가드 포함.

```sh
claude_accounts_migrate() {
    if [ -d "$HOME/.claude-personal" ]; then
        ux_info "Already migrated to ~/.claude-personal — skipping"
        return 0
    fi

    ux_warning "Will move ~/.claude → ~/.claude-personal"
    ux_info    "Preserves: credentials, sessions, projects, history"
    printf "Continue? (y/N): "
    read -r reply
    [ "$reply" = "y" ] || { ux_info "Aborted"; return 1; }

    # 1) 기존 symlink/bind mount 해제
    [ -L "$HOME/.claude/settings.json" ]         && rm "$HOME/.claude/settings.json"
    [ -L "$HOME/.claude/statusline-command.sh" ] && rm "$HOME/.claude/statusline-command.sh"
    [ -L "$HOME/.claude/projects/GLOBAL/memory" ] && rm "$HOME/.claude/projects/GLOBAL/memory"
    _is_mounted "$HOME/.claude/skills" && sudo umount "$HOME/.claude/skills"
    _is_mounted "$HOME/.claude/docs"   && sudo umount "$HOME/.claude/docs"

    # 2) 기존 plugins 실데이터를 공유 위치로 승격
    if [ -d "$HOME/.claude/plugins" ] && [ ! -L "$HOME/.claude/plugins" ]; then
        mkdir -p "$HOME/.claude-shared"
        mv "$HOME/.claude/plugins" "$HOME/.claude-shared/plugins"
    fi

    # 3) 디렉토리 자체를 personal 로 이동
    mv "$HOME/.claude" "$HOME/.claude-personal"

    # 4) 빈 ~/.claude 재생성 + 모든 계정 init (멱등)
    claude_accounts_init

    ux_success "Migration complete. Personal data preserved at ~/.claude-personal/"
}
```

**3대 PC 첫 실행 흐름**:

| PC | 첫 명령 | 동작 |
|---|---|---|
| Home-PC (~/.claude/ 데이터 있음) | `claude-accounts migrate` | 데이터 → personal 로 이동 + 모든 link/mount + work 빈 디렉토리 |
| External-PC | `./setup.sh` (또는 `claude-accounts setup`) | personal/work 디렉토리 만들고 link/mount. 첫 로그인 필요 |
| Internal-PC | `cp claude.local.example claude.local.sh` 후 `./setup.sh` | work 만 디렉토리 + link/mount. 첫 로그인 필요 |

## 8. `claude/setup.sh` 통합

기존 `claude/setup.sh` 가 단일 `~/.claude/` 만 처리하던 코드를
**계정 디렉토리 N개 순회** 로 일반화.

핵심 변경:
1. shell-common 함수 source 후 `claude_accounts_init` 호출
   (또는 동등 로직을 setup.sh 내부에 풀어쓰기 — bash 환경이므로 함수 source 가능).
2. sudoers 등록은 ENABLED 계정의 mount target N×2 (skills/docs) 모두 등록.
   기존 `_setup_bind_mount_sudoers` 헬퍼 재사용, target 만 다르게.
3. 루트 `setup.sh` (orchestrator) 는 변경 없음 — `./claude/setup.sh` 한 호출이
   ENABLED 계정 모두 처리.

## 테스트 & 검증

### 멱등성 (3대 PC 공통)

```bash
./setup.sh                           # 첫 실행: 모든 link/mount "✓ created"
./setup.sh                           # 두 번째 실행: 모든 항목 "skip"
claude-accounts status               # 모든 항목 ✓
```

### 단위 시나리오

| # | 시나리오 | 명령 | 기대 결과 |
|---|---|---|---|
| 1 | personal default (External/Home) | `claude-yolo` | `CLAUDE_CONFIG_DIR=~/.claude-personal` 로 실행 |
| 2 | work 명시 | `claude-yolo --user work` | `CLAUDE_CONFIG_DIR=~/.claude-work` 로 실행 |
| 3 | 단축 alias | `claude-yolo-work` | 위와 동일 |
| 4 | 알 수 없는 계정 | `claude-yolo --user xyz` | 에러 + "Available: ..." 출력, claude 호출 없음 |
| 5 | 디렉토리 부재 | `mv ~/.claude-work /tmp/`<br>`claude-yolo --user work` | 에러 + "Run: claude-accounts setup" 안내 |
| 6 | 본체 인자 통과 | `claude-yolo --user work --resume foo` | claude 가 `--resume foo` 받음 |
| 7 | `--` 분리 | `claude-yolo -- --user not-flag` | claude 가 `--user not-flag` 그대로 받음 |
| 8 | Internal-PC default | (Internal) `claude-yolo` | `CLAUDE_CONFIG_DIR=~/.claude-work` |
| 9 | Internal-PC alias 부재 | (Internal) `type claude-yolo-personal` | not found |
| 10 | main 가드 | `git checkout main && claude-yolo` | `scratch/...` 자동 생성 |
| 11 | 멱등 setup | `claude-accounts setup` × 2 | 두 번째에서 모두 skip |
| 12 | 멱등 migrate | `claude-accounts migrate` × 2 | "Already migrated, skipping" |

### Lint (기존 lint 통과 필수)

- `tox -e shellcheck -- shell-common/tools/integrations/claude.sh shell-common/env/claude.sh shell-common/env/claude.local.example claude/setup.sh`
- `shfmt -d -i 4 shell-common/tools/integrations/claude.sh`

### 알려진 함정 회피

- **subshell tracing bug** (MEMORY.md): `while ... | ...` 패턴 미사용,
  `for ... in $(...)` 만 사용 → 안전.
- **VAR=val cmd argv expansion trap** (MEMORY.md): `CLAUDE_CONFIG_DIR=...
  command claude "$@"` 는 단일 명령에 대한 환경 prefix → 안전.
- **zsh 변수 trace** (MEMORY.md): 함수 안에 `emulate -L sh` 불필요
  (POSIX 안전 패턴만 사용).

## Future Work (Phase 2, 별도 issue)

- `gwt spawn ... --launch --ai claude --user work` 지원.
  `_gwt_yolo_command claude work` → `"claude_yolo --user work"`.
- gwt 의 `--user` 검증도 `_claude_resolve_account` 위임.
- 회귀 테스트: 기존 `gwt --launch --ai claude` (user 없음) 동작 변화 0.

## File Manifest (Phase 1 변경 파일)

| 파일 | 변경 |
|---|---|
| `shell-common/env/claude.sh` | `CLAUDE_DEFAULT_ACCOUNT`, `CLAUDE_ENABLED_ACCOUNTS` 기본값 추가 |
| `shell-common/env/claude.local.example` | 신규 (PC 별 오버라이드 템플릿) |
| `shell-common/tools/integrations/claude.sh` | `_claude_resolve_account`, `claude_yolo` 재작성, alias 자동 파생, `claude_accounts*` 함수군 추가. 기존 `claude_yolo` 의 main/master 가드 로직 보존 |
| `claude/setup.sh` | 단일 `~/.claude/` → 계정 N개 순회로 일반화 |
| `.gitignore` | `shell-common/env/claude.local.sh` 추가 (이미 `*.local.sh` 패턴이 있다면 무수정) |
| `docs/superpowers/specs/2026-05-04-claude-multi-account-design.md` | 신규 (이 문서) |
