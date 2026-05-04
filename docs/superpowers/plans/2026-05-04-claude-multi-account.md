# Claude Multi-Account Configuration — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code 의 단일 머신 다중 계정(`personal` / `work`) 동시 사용을
SSOT/SOLID 원칙에 맞게 dotfiles 에 통합한다. 3대 PC(External / Home / Internal)
환경 차이를 `CLAUDE_ENABLED_ACCOUNTS` 화이트리스트로 흡수하고 멱등 setup
함수 한 번 호출로 동일 상태 유지.

**Architecture:** `_claude_resolve_account` case 디스패처가 단일 SSOT.
모든 컴포넌트(`claude_yolo` dispatcher, alias 자동 파생, setup, status,
migration) 가 이 함수를 호출 → PC별 분기 코드 0줄. POSIX 안전 인자
재구성(sentinel 패턴)으로 dispatcher 가 `--user <name>` 만 가로채고
나머지는 `claude` 본체로 통과.

**Tech Stack:** POSIX sh (bash + zsh 호환), bats (단위/통합 테스트),
shellcheck + shfmt (lint), 기존 `_is_mounted` / `ux_*` / `create_symlink`
헬퍼 재사용.

**Spec:** `docs/superpowers/specs/2026-05-04-claude-multi-account-design.md` (commit `1e8098c`)
**Issue:** [#287](https://github.com/dEitY719/dotfiles/issues/287)
**Branch:** `wt/issue-287/1`

---

## File Structure

### 신규 파일

| 파일 | 책임 |
|---|---|
| `shell-common/env/claude.local.example` | PC별 오버라이드 템플릿 (Internal-PC 안내 포함) |
| `tests/bats/integrations/claude_accounts.bats` | 단위·통합 테스트 (계정 해석, dispatcher 인자 파싱, 멱등 setup) |

### 수정 파일

| 파일 | 변경 |
|---|---|
| `shell-common/env/claude.sh` | `CLAUDE_DEFAULT_ACCOUNT`, `CLAUDE_ENABLED_ACCOUNTS` 기본값 + `claude.local.sh` source |
| `shell-common/tools/integrations/claude.sh` | `claude_yolo` 재작성, `_claude_resolve_account`, `_claude_ensure_*`, `_claude_account_setup_one`, `claude_accounts*`, `_claude_yolo_register_aliases` 추가 |
| `claude/setup.sh` | 단일 `~/.claude/` 처리 → 계정 N개 순회로 일반화 |
| `.gitignore` | (검증) `*.local.sh` 패턴이 이미 있음. 별도 변경 불필요 |

### 디렉토리 (각 PC 의 setup 시 생성)

```
~/.claude/                              # 빈 디렉토리 가드
~/.claude-shared/plugins/               # 양쪽 계정 공유 plugins 실데이터
~/.claude-personal/                     # External, Home (Internal 에선 부재)
~/.claude-work/                         # 모든 PC
```

---

## Conventions (모든 task 공통)

- **POSIX sh**: `[[ ]]` 금지, `[ ]` 사용. 배열·연관배열 금지. `local` OK (bash/zsh/dash 다 지원).
- **인용**: 모든 변수는 `"$var"` 인용. 공백 안전.
- **헬퍼 재사용**: `ux_info` / `ux_warning` / `ux_error` / `ux_success` / `ux_section` / `ux_header`. `_is_mounted` (from `shell-common/functions/mount.sh`).
- **subshell tracing bug 회피**: `while ... | ...` 패턴 금지 (MEMORY.md). `for ... in $(...)` 또는 heredoc 사용.
- **Lint**: 각 task 끝에서 `tox -e shellcheck -- <변경 파일>` 통과 필수.
- **Commit 메시지 형식**: `feat(claude-accounts): <한국어 설명> (#287)` 또는 `test(claude-accounts): ...`. Co-author trailer 포함.

---

## Task 1: env 기본값 + `.local.sh` 로드

**Files:**
- Modify: `shell-common/env/claude.sh:1-19` (전체 파일에 추가)

- [ ] **Step 1: Test 작성 (env 변수 기본값 검증)**

`tests/bats/integrations/claude_accounts.bats` 신규 파일 생성:

```bash
#!/usr/bin/env bats
# tests/bats/integrations/claude_accounts.bats
# Verify multi-account env vars and helper functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------- Task 1: env defaults ----------

@test "bash: CLAUDE_DEFAULT_ACCOUNT defaults to personal" {
    run_in_bash 'echo "$CLAUDE_DEFAULT_ACCOUNT"'
    assert_success
    assert_output "personal"
}

@test "bash: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work'" {
    run_in_bash 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work"
}

@test "zsh: CLAUDE_DEFAULT_ACCOUNT defaults to personal" {
    run_in_zsh 'echo "$CLAUDE_DEFAULT_ACCOUNT"'
    assert_success
    assert_output "personal"
}

@test "zsh: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work'" {
    run_in_zsh 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 테스트 모두 FAIL (변수 미정의)

- [ ] **Step 3: `shell-common/env/claude.sh` 에 변수 추가 + .local 로드**

기존 파일 끝에 다음 블록 추가 (기존 라인 1-19 보존):

```sh
# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# Default account for `claude-yolo` (no --user flag).
# Override per-PC via shell-common/env/claude.local.sh.
export CLAUDE_DEFAULT_ACCOUNT="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

# Whitelist of accounts to enable on this PC.
# Setup, alias auto-derivation, and status filter by this list.
# Override per-PC via shell-common/env/claude.local.sh
# (e.g. Internal-PC: CLAUDE_ENABLED_ACCOUNTS="work").
export CLAUDE_ENABLED_ACCOUNTS="${CLAUDE_ENABLED_ACCOUNTS:-personal work}"

# Load PC-local overrides (gitignored, see claude.local.example).
_claude_env_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
if [ -f "$_claude_env_root/env/claude.local.sh" ]; then
    . "$_claude_env_root/env/claude.local.sh"
fi
unset _claude_env_root
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/env/claude.sh
git add shell-common/env/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): CLAUDE_DEFAULT_ACCOUNT, CLAUDE_ENABLED_ACCOUNTS env vars (#287)

PC별 오버라이드는 shell-common/env/claude.local.sh 에서 가능.
기본값은 personal default + personal/work 활성화.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `claude.local.example` 템플릿

**Files:**
- Create: `shell-common/env/claude.local.example`

- [ ] **Step 1: 템플릿 작성**

`shell-common/env/claude.local.example` 신규 파일:

```sh
#!/bin/sh
# claude.local.sh (template) — PC별 Claude Code 다중 계정 오버라이드
#
# 사용 방법:
#   1. 이 파일을 claude.local.sh 로 복사
#      cp claude.local.example claude.local.sh
#   2. PC 환경에 맞게 아래 값을 수정 (필요 시)
#   3. claude.local.sh 는 자동으로 로드됨 (.gitignore 에 의해 제외됨)
#
# 기본값 (claude.sh):
#   CLAUDE_DEFAULT_ACCOUNT=personal
#   CLAUDE_ENABLED_ACCOUNTS="personal work"

# ─── External-PC, Home-PC ───────────────────────────────────────
# 두 계정 모두 사용 → 기본값 그대로. 이 파일 작성 불필요.

# ─── Internal-PC (사내 PC, work 계정만) ─────────────────────────
# 아래 두 줄의 주석을 해제하면 work 계정만 활성화되고
# `claude-yolo` 가 work 로 실행됨.
#
# export CLAUDE_DEFAULT_ACCOUNT="work"
# export CLAUDE_ENABLED_ACCOUNTS="work"
```

- [ ] **Step 2: `.gitignore` 검증**

```bash
grep -n "local.sh" .gitignore
```

Expected: `*.local.sh` 라인 출력 (이미 존재). 변경 불필요.

- [ ] **Step 3: 자동 로드 검증 테스트 추가**

`tests/bats/integrations/claude_accounts.bats` 에 추가:

```bash
@test "bash: claude.local.sh override is loaded" {
    cat > "${DOTFILES_ROOT}/shell-common/env/claude.local.sh" <<'LOCAL'
export CLAUDE_DEFAULT_ACCOUNT="work"
export CLAUDE_ENABLED_ACCOUNTS="work"
LOCAL

    run_in_bash 'echo "$CLAUDE_DEFAULT_ACCOUNT|$CLAUDE_ENABLED_ACCOUNTS"'

    rm -f "${DOTFILES_ROOT}/shell-common/env/claude.local.sh"

    assert_success
    assert_output "work|work"
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 5개 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add shell-common/env/claude.local.example tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude.local.example PC별 오버라이드 템플릿 (#287)

Internal-PC 용 work-only 설정 예시 포함. claude.local.sh 는
기존 *.local.sh 패턴(.gitignore)과 자동 로드 패턴(env/security.sh
등) 을 그대로 따름.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `_claude_resolve_account` 매핑 SSOT

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh` (파일 끝에 추가)

- [ ] **Step 1: 테스트 추가**

`tests/bats/integrations/claude_accounts.bats` 에 추가:

```bash
# ---------- Task 3: _claude_resolve_account ----------

@test "bash: resolve personal returns ~/.claude-personal" {
    run_in_bash '_claude_resolve_account personal'
    assert_success
    assert_output "$HOME/.claude-personal"
}

@test "bash: resolve work returns ~/.claude-work" {
    run_in_bash '_claude_resolve_account work'
    assert_success
    assert_output "$HOME/.claude-work"
}

@test "bash: resolve unknown account returns non-zero" {
    run_in_bash '_claude_resolve_account xyz'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve --list-all returns 'personal work'" {
    run_in_bash '_claude_resolve_account --list-all'
    assert_success
    assert_output "personal work"
}

@test "bash: resolve --list returns ENABLED accounts only (default)" {
    run_in_bash '_claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "bash: resolve --list filters by CLAUDE_ENABLED_ACCOUNTS=work" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "work "
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 6개 신규 테스트 FAIL (`_claude_resolve_account: command not found`)

- [ ] **Step 3: `_claude_resolve_account` 함수 추가**

`shell-common/tools/integrations/claude.sh` 파일 끝(현재 라인 426 이후)에 추가:

```sh
# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# _claude_resolve_account — 계정 매핑 SSOT (case dispatcher).
# Usage:
#   _claude_resolve_account <name>     → echo CONFIG_DIR (exit 0) or fail (exit 1)
#   _claude_resolve_account --list     → echo enabled accounts (one per line)
#   _claude_resolve_account --list-all → echo all defined accounts (debug)
#
# 새 계정 추가 시 case 한 줄 + --list-all 한 단어만 추가.
_claude_resolve_account() {
    case "$1" in
        --list)
            for _cra_acct in $CLAUDE_ENABLED_ACCOUNTS; do
                _claude_resolve_account "$_cra_acct" >/dev/null 2>&1 && echo "$_cra_acct"
            done
            ;;
        --list-all)
            echo "personal work"
            ;;
        personal) echo "$HOME/.claude-personal" ;;
        work)     echo "$HOME/.claude-work" ;;
        *)        return 1 ;;
    esac
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 11개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): _claude_resolve_account 매핑 SSOT (#287)

case 디스패처로 계정 → CONFIG_DIR 매핑 단일 정의. --list 는
CLAUDE_ENABLED_ACCOUNTS 화이트리스트 적용, --list-all 은 매핑 전체
(디버깅용). 새 계정 추가 = case 한 줄.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 멱등 헬퍼 (`_claude_ensure_symlink`, `_claude_ensure_bind_mount`)

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh` (Task 3 블록 뒤)

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 4: ensure helpers (idempotency) ----------

@test "bash: _claude_ensure_symlink creates new symlink" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    [ -L "$HOME/tgt-dir/link" ]
}

@test "bash: _claude_ensure_symlink is idempotent (already correct)" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    ln -s "$HOME/src/file.txt" "$HOME/tgt-dir/link"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    assert_output --partial "already"
}

@test "bash: _claude_ensure_symlink backs up regular file collision" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    echo "old" > "$HOME/tgt-dir/link"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    [ -L "$HOME/tgt-dir/link" ]
    ls "$HOME/tgt-dir/" | grep -q "link.*backup\|link.*original"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 3개 신규 테스트 FAIL

- [ ] **Step 3: 멱등 헬퍼 추가**

`shell-common/tools/integrations/claude.sh` 에 추가:

```sh
# _claude_ensure_symlink — 멱등 symlink 생성.
# - 없음 → 생성
# - 같은 target 의 symlink → skip
# - 다른 file/dir → timestamped backup 후 재생성
_claude_ensure_symlink() {
    _ces_src="$1"
    _ces_tgt="$2"

    if [ -L "$_ces_tgt" ]; then
        _ces_current=$(readlink "$_ces_tgt")
        if [ "$_ces_current" = "$_ces_src" ]; then
            ux_info "  ✓ already linked: $_ces_tgt"
            return 0
        fi
        ux_warning "  symlink target mismatch — recreating: $_ces_tgt"
        rm "$_ces_tgt"
    elif [ -e "$_ces_tgt" ]; then
        _ces_backup="${_ces_tgt}.backup-$(date +%Y%m%d%H%M%S)"
        ux_warning "  backing up existing file: $_ces_tgt → $_ces_backup"
        mv "$_ces_tgt" "$_ces_backup"
    fi

    ln -s "$_ces_src" "$_ces_tgt"
    ux_success "  created symlink: $_ces_tgt → $_ces_src"
}

# _claude_ensure_bind_mount — 멱등 bind mount.
# - 이미 마운트됨 → skip
# - 안 됨 → sudo mount --bind (sudoers 등록 전제)
_claude_ensure_bind_mount() {
    _cebm_src="$1"
    _cebm_tgt="$2"

    [ -d "$_cebm_src" ] || {
        ux_warning "  bind mount source missing: $_cebm_src"
        return 1
    }

    mkdir -p "$_cebm_tgt"

    if _is_mounted "$_cebm_tgt"; then
        ux_info "  ✓ already mounted: $_cebm_tgt"
        return 0
    fi

    if sudo mount --bind "$_cebm_src" "$_cebm_tgt" 2>/dev/null; then
        ux_success "  bind mount: $_cebm_tgt ← $_cebm_src"
    else
        ux_error "  bind mount failed: $_cebm_tgt (check sudoers)"
        return 1
    fi
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 14개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): 멱등 헬퍼 _claude_ensure_symlink/bind_mount (#287)

3대 PC 에서 N회 실행해도 동일 상태 유지. 기존 file 충돌 시 timestamped
backup. bind mount 는 _is_mounted 로 사전 확인.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `_claude_account_setup_one` + `claude_accounts_init`

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh`

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 5: account setup ----------

@test "bash: _claude_account_setup_one creates symlinks (skips bind mount)" {
    # bind mount 는 sudo 필요 → 단위 테스트는 symlink 만 검증
    # CLAUDE_SKIP_BIND_MOUNT=1 로 우회 (구현에서 지원)
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-shared/plugins"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 _claude_account_setup_one personal '$HOME/.claude-personal'"
    assert_success

    [ -L "$HOME/.claude-personal/settings.json" ]
    [ -L "$HOME/.claude-personal/statusline-command.sh" ]
    [ -L "$HOME/.claude-personal/plugins" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
}

@test "bash: claude_accounts_init creates only ENABLED account dirs" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"

    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success

    [ ! -d "$HOME/.claude-personal" ]
    [ -d "$HOME/.claude-work" ]
    [ -d "$HOME/.claude" ]                 # 빈 가드 디렉토리
    [ -d "$HOME/.claude-shared/plugins" ]
}

@test "bash: claude_accounts_init refuses if ~/.claude/ has unmigrated data" {
    mkdir -p "$HOME/.claude"
    echo "old" > "$HOME/.claude/legacy-file"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_failure
    assert_output --partial "claude-accounts migrate"
}

@test "bash: claude_accounts_init is idempotent (second run skips)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success
    assert_output --partial "already"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 신규 FAIL

- [ ] **Step 3: 함수 구현 추가**

```sh
# _claude_account_setup_one — 단일 계정의 link/mount 멱등 셋업.
_claude_account_setup_one() {
    _caso_acct="$1"
    _caso_cdir="$2"
    ux_section "Account: $_caso_acct ($_caso_cdir)"

    mkdir -p "$_caso_cdir"
    mkdir -p "$_caso_cdir/projects/GLOBAL"

    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/settings.json"          "$_caso_cdir/settings.json"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/statusline-command.sh"  "$_caso_cdir/statusline-command.sh"
    _claude_ensure_symlink "$HOME/.claude-shared/plugins"                   "$_caso_cdir/plugins"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/global-memory"          "$_caso_cdir/projects/GLOBAL/memory"

    if [ "${CLAUDE_SKIP_BIND_MOUNT:-0}" = "1" ]; then
        ux_info "  (CLAUDE_SKIP_BIND_MOUNT=1 → skipping bind mounts)"
    else
        _claude_ensure_bind_mount "${DOTFILES_ROOT}/claude/skills"  "$_caso_cdir/skills"
        _claude_ensure_bind_mount "${DOTFILES_ROOT}/claude/docs"    "$_caso_cdir/docs"
    fi
}

# claude_accounts_init — 멱등 setup, 3대 PC 공통 진입점.
claude_accounts_init() {
    ux_header "Claude Accounts Setup"

    # 마이그레이션 미수행 가드: ~/.claude/ 에 빈 디렉토리 외 데이터 있으면 거부
    if [ -d "$HOME/.claude" ] \
       && [ ! -d "$HOME/.claude-personal" ] \
       && [ ! -d "$HOME/.claude-work" ] \
       && [ -n "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
        ux_warning "~/.claude/ 에 기존 데이터가 있습니다."
        ux_info    "먼저 마이그레이션을 실행하세요: claude-accounts migrate"
        return 1
    fi

    mkdir -p "$HOME/.claude-shared/plugins"
    mkdir -p "$HOME/.claude"

    for _cai_acct in $(_claude_resolve_account --list); do
        _cai_cdir=$(_claude_resolve_account "$_cai_acct")
        _claude_account_setup_one "$_cai_acct" "$_cai_cdir"
    done

    ux_success "All accounts ready"
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 18개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude_accounts_init 멱등 setup + 마이그레이션 가드 (#287)

ENABLED 계정만 순회하여 6종(symlink 4 + bind mount 2) 자동 셋업.
~/.claude/ 에 unmigrated 데이터가 있으면 setup 거부 → migrate 안내.
CLAUDE_SKIP_BIND_MOUNT=1 로 단위 테스트 환경에서 sudo 회피.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `claude_accounts_status`

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh`

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 6: status ----------

@test "bash: claude_accounts_status shows enabled accounts" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && claude_accounts_status'
    assert_success
    assert_output --partial "Default: personal"
    assert_output --partial "Account: personal"
    assert_output --partial "Account: work"
}

@test "bash: claude_accounts_status reports NOT logged in when no .credentials.json" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && claude_accounts_status'
    assert_output --partial "NOT logged in"
}

@test "bash: claude_accounts_status hides disabled accounts (Internal-PC)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_DEFAULT_ACCOUNT=work claude_accounts_status'
    assert_success
    refute_output --partial "Account: personal"
    assert_output --partial "Account: work"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 3개 신규 FAIL

- [ ] **Step 3: 구현 추가**

```sh
# claude_accounts_status — 진단 출력 (모든 계정의 link/mount/credential 상태).
claude_accounts_status() {
    ux_header "Claude Accounts Status"
    ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
    ux_info "Enabled: $CLAUDE_ENABLED_ACCOUNTS"
    if [ -d "$HOME/.claude-shared/plugins" ]; then
        ux_info "Shared:  $HOME/.claude-shared/plugins ✓"
    else
        ux_warning "Shared:  $HOME/.claude-shared/plugins ✗ missing"
    fi
    echo ""

    for _cas_acct in $(_claude_resolve_account --list); do
        _cas_cdir=$(_claude_resolve_account "$_cas_acct")
        ux_section "Account: $_cas_acct"
        echo "  Path:        $_cas_cdir $([ -d "$_cas_cdir" ] && echo '✓' || echo '✗ missing')"

        if [ -f "$_cas_cdir/.credentials.json" ]; then
            echo "  Credentials: .credentials.json ✓ logged in"
        else
            echo "  Credentials: .credentials.json ✗ NOT logged in"
            echo "                → Run: claude-yolo --user $_cas_acct"
        fi

        for _cas_link in settings.json statusline-command.sh plugins projects/GLOBAL/memory; do
            if [ -L "$_cas_cdir/$_cas_link" ]; then
                echo "  $_cas_link: symlink ✓"
            else
                echo "  $_cas_link: ✗ missing"
            fi
        done

        for _cas_mount in skills docs; do
            if _is_mounted "$_cas_cdir/$_cas_mount"; then
                echo "  $_cas_mount: bind mount ✓"
            else
                echo "  $_cas_mount: ✗ not mounted"
            fi
        done
        echo ""
    done
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 21개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude_accounts_status 진단 출력 (#287)

ENABLED 계정 각각의 path/credentials/symlink/mount 상태 한눈에. 첫
로그인 안 된 계정에 안내 명령 출력. Internal-PC 처럼 ENABLED 가
"work" 만이면 personal 계정은 출력에 등장하지 않음.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `claude_accounts_migrate` (1회 마이그레이션)

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh`

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 7: migrate ----------

@test "bash: claude_accounts_migrate moves ~/.claude → ~/.claude-personal" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects" "$HOME/.claude/sessions"
    echo "creds" > "$HOME/.claude/.credentials.json"
    echo "history" > "$HOME/.claude/history.jsonl"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 yes | claude_accounts_migrate'
    assert_success

    [ -d "$HOME/.claude-personal" ]
    [ -f "$HOME/.claude-personal/.credentials.json" ]
    [ -f "$HOME/.claude-personal/history.jsonl" ]
    [ -d "$HOME/.claude-personal/projects" ]
}

@test "bash: claude_accounts_migrate promotes ~/.claude/plugins → ~/.claude-shared/" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/plugins/marketplaces"
    echo "plugin" > "$HOME/.claude/plugins/marketplaces/test"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 yes | claude_accounts_migrate'
    assert_success

    [ -d "$HOME/.claude-shared/plugins/marketplaces" ]
    [ -f "$HOME/.claude-shared/plugins/marketplaces/test" ]
    [ -L "$HOME/.claude-personal/plugins" ]
}

@test "bash: claude_accounts_migrate is idempotent (already migrated)" {
    mkdir -p "$HOME/.claude-personal"
    run_in_bash 'claude_accounts_migrate'
    assert_success
    assert_output --partial "Already migrated"
}

@test "bash: claude_accounts_migrate aborts on user 'n'" {
    mkdir -p "$HOME/.claude/projects"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 echo n | claude_accounts_migrate'
    assert_failure
    [ -d "$HOME/.claude" ]
    [ ! -d "$HOME/.claude-personal" ]
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 신규 FAIL

- [ ] **Step 3: 구현 추가**

```sh
# claude_accounts_migrate — 1회 마이그레이션 (Home-PC 등 기존 데이터 보유 PC 한정).
# 멱등: 이미 마이그됐으면 즉시 skip.
claude_accounts_migrate() {
    if [ -d "$HOME/.claude-personal" ]; then
        ux_info "Already migrated to ~/.claude-personal — skipping"
        return 0
    fi

    if [ ! -d "$HOME/.claude" ]; then
        ux_info "~/.claude not found — nothing to migrate. Run: claude-accounts setup"
        return 0
    fi

    ux_warning "Will move ~/.claude → ~/.claude-personal"
    ux_info    "Preserves: credentials, sessions, projects, history"
    printf "Continue? (y/N): "
    read -r _cam_reply
    if [ "$_cam_reply" != "y" ] && [ "$_cam_reply" != "yes" ]; then
        ux_info "Aborted"
        return 1
    fi

    # 1) 기존 symlink/bind mount 해제
    [ -L "$HOME/.claude/settings.json" ]                 && rm "$HOME/.claude/settings.json"
    [ -L "$HOME/.claude/statusline-command.sh" ]         && rm "$HOME/.claude/statusline-command.sh"
    [ -L "$HOME/.claude/projects/GLOBAL/memory" ]        && rm "$HOME/.claude/projects/GLOBAL/memory"
    if [ "${CLAUDE_SKIP_BIND_MOUNT:-0}" != "1" ]; then
        _is_mounted "$HOME/.claude/skills" && sudo umount "$HOME/.claude/skills"
        _is_mounted "$HOME/.claude/docs"   && sudo umount "$HOME/.claude/docs"
    fi

    # 2) 기존 plugins 실데이터를 공유 위치로 승격
    if [ -d "$HOME/.claude/plugins" ] && [ ! -L "$HOME/.claude/plugins" ]; then
        mkdir -p "$HOME/.claude-shared"
        if [ -d "$HOME/.claude-shared/plugins" ]; then
            ux_warning "  ~/.claude-shared/plugins already exists — keeping new, ignoring old"
        else
            mv "$HOME/.claude/plugins" "$HOME/.claude-shared/plugins"
        fi
    fi

    # 3) 디렉토리 자체 이동
    mv "$HOME/.claude" "$HOME/.claude-personal"

    # 4) 빈 ~/.claude 재생성 + 모든 계정 init (멱등)
    claude_accounts_init

    ux_success "Migration complete. Personal data preserved at ~/.claude-personal/"
}
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 25개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude_accounts_migrate 1회 마이그레이션 (#287)

Home-PC 처럼 ~/.claude/ 에 기존 데이터가 있는 PC 전용. 사용자 확인
후 plugins 를 ~/.claude-shared/ 로 승격 + ~/.claude → ~/.claude-personal
이동 + init. 이미 마이그 됐으면 skip.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `claude_accounts` CLI + alias

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh`

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 8: claude_accounts CLI ----------

@test "bash: claude-accounts list shows enabled accounts" {
    run_in_bash 'claude-accounts list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "bash: claude-accounts (no arg) defaults to status" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && claude-accounts'
    assert_success
    assert_output --partial "Default: personal"
}

@test "bash: claude-accounts unknown subcommand fails" {
    run_in_bash 'claude-accounts foo'
    assert_failure
    assert_output --partial "Unknown"
}

@test "bash: claude-accounts -h shows help" {
    run_in_bash 'claude-accounts -h'
    assert_success
    assert_output --partial "status"
    assert_output --partial "setup"
    assert_output --partial "migrate"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 신규 FAIL

- [ ] **Step 3: CLI 구현 추가**

```sh
_claude_accounts_help() {
    ux_header "claude-accounts — Claude Code multi-account management"
    ux_info "Usage: claude-accounts [<subcommand>]"
    ux_info ""
    ux_info "Subcommands:"
    ux_info "  status     (default) Show all accounts: path/credentials/symlinks/mounts"
    ux_info "  list       List enabled accounts"
    ux_info "  setup      Idempotent setup (creates dirs, symlinks, bind mounts)"
    ux_info "  migrate    One-time migration: ~/.claude → ~/.claude-personal (Home-PC)"
    ux_info "  -h|--help  This help"
    ux_info ""
    ux_info "Env vars:"
    ux_info "  CLAUDE_DEFAULT_ACCOUNT     Default for \`claude-yolo\` (default: personal)"
    ux_info "  CLAUDE_ENABLED_ACCOUNTS    Whitelist (default: 'personal work')"
    ux_info "  Override per-PC in shell-common/env/claude.local.sh"
}

claude_accounts() {
    case "${1:-status}" in
        status)         claude_accounts_status ;;
        list)           _claude_resolve_account --list ;;
        setup)          claude_accounts_init ;;
        migrate)        claude_accounts_migrate ;;
        -h|--help|help) _claude_accounts_help ;;
        *)              ux_error "Unknown subcommand: $1"; _claude_accounts_help; return 1 ;;
    esac
}
alias claude-accounts='claude_accounts'
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 29개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude-accounts CLI 디스패처 (#287)

status (default) / list / setup / migrate / -h. 단일 진입점에서
모든 다중 계정 운영 작업 가능. 새 PC: \`claude-accounts setup\`.
Home-PC: \`claude-accounts migrate\`. 진단: \`claude-accounts status\`.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `claude_yolo` 재작성 (`--user` 인자 파싱)

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh:406-426` (기존 `claude_yolo` 함수 + alias 교체)

- [ ] **Step 1: 테스트 추가 (claude 본체 호출은 mock)**

```bash
# ---------- Task 9: claude_yolo dispatcher ----------

# Mock `claude` 바이너리 — 실제 호출 대신 인자만 echo
_setup_claude_mock() {
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'MOCK'
#!/bin/sh
echo "MOCK_CLAUDE: CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-unset} ARGS=$*"
MOCK
    chmod +x "$HOME/bin/claude"
    export PATH="$HOME/bin:$PATH"
}

@test "bash: claude_yolo defaults to personal account" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    run_in_bash "_setup_claude_mock; mkdir -p \"$HOME/.claude-personal\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-personal"
}

@test "bash: claude_yolo --user work routes to work" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "_setup_claude_mock; mkdir -p \"$HOME/.claude-work\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo --user=work syntax also works" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "_setup_claude_mock; mkdir -p \"$HOME/.claude-work\"; CLAUDE_YOLO_STAY=1 claude_yolo --user=work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo passes extra args through to claude" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "_setup_claude_mock; mkdir -p \"$HOME/.claude-work\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work --resume foo"
    assert_success
    assert_output --partial "ARGS=--dangerously-skip-permissions --resume foo"
}

@test "bash: claude_yolo --user xyz fails with available list" {
    _setup_claude_mock
    run_in_bash "_setup_claude_mock; CLAUDE_YOLO_STAY=1 claude_yolo --user xyz"
    assert_failure
    assert_output --partial "Unknown account: xyz"
    assert_output --partial "Available"
}

@test "bash: claude_yolo errors when account dir missing" {
    _setup_claude_mock
    rm -rf "$HOME/.claude-work"
    run_in_bash "_setup_claude_mock; CLAUDE_YOLO_STAY=1 claude_yolo --user work"
    assert_failure
    assert_output --partial "Account directory missing"
    assert_output --partial "claude-accounts setup"
}

@test "bash: claude_yolo respects CLAUDE_DEFAULT_ACCOUNT=work (Internal-PC)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "_setup_claude_mock; mkdir -p \"$HOME/.claude-work\"; CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}
```

추가로 `setup()` 안에 `_setup_claude_mock` 함수 정의를 옮기면 중복 제거됨 — 단, 테스트 격리를 위해 각 테스트에서 명시적으로 호출하는 패턴을 유지.

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 7개 신규 FAIL (기존 `claude_yolo` 는 `--user` 모름 → 에러 또는 잘못된 동작)

- [ ] **Step 3: 기존 `claude_yolo` 를 새 dispatcher 로 교체**

`shell-common/tools/integrations/claude.sh:406-426` 의 기존 함수와 alias 를 다음으로 교체:

```sh
# claude_yolo — 다중 계정 dispatcher (issue #287, Phase 1).
#
# Usage:
#   claude-yolo                       → CLAUDE_DEFAULT_ACCOUNT 으로 실행
#   claude-yolo --user work           → work 계정으로 실행
#   claude-yolo --user=work foo bar   → --user 추출, foo bar 는 claude 통과
#   claude-yolo -- --user not-flag    → -- 이후는 모두 claude 본체 통과
#
# 동작:
# 1. POSIX 안전 인자 재구성 (sentinel 패턴, eval 없음)
# 2. 계정 → CLAUDE_CONFIG_DIR 해석 (SSOT: _claude_resolve_account)
# 3. main/master 브랜치 가드 (기존 동작 유지) — bypass: CLAUDE_YOLO_STAY=1
# 4. CLAUDE_CONFIG_DIR 환경 주입 + command claude --dangerously-skip-permissions
claude_yolo() {
    _cy_account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

    # --user 가로채고 나머지는 위치 인자로 보존 (POSIX 안전)
    set -- "$@" "__CY_END__"
    while [ "$1" != "__CY_END__" ]; do
        case "$1" in
            --user)
                _cy_account="$2"
                shift 2
                ;;
            --user=*)
                _cy_account="${1#--user=}"
                shift
                ;;
            *)
                set -- "$@" "$1"
                shift
                ;;
        esac
    done
    shift   # sentinel 제거

    # 계정 → CONFIG_DIR (SSOT 호출)
    _cy_config_dir=$(_claude_resolve_account "$_cy_account") || {
        ux_error "Unknown account: $_cy_account"
        ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
        return 1
    }

    [ -d "$_cy_config_dir" ] || {
        ux_error "Account directory missing: $_cy_config_dir"
        ux_info  "Run: claude-accounts setup"
        return 1
    }

    # main/master 브랜치 가드 (기존 로직 보존)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _cy_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
        case "$_cy_branch" in
            main|master)
                if [ -z "${CLAUDE_YOLO_STAY:-}" ]; then
                    _cy_new_branch="scratch/$(date +%m%d-%H%M%S)"
                    ux_warning "main 브랜치 감지 → ${_cy_new_branch} 로 전환 (bypass: CLAUDE_YOLO_STAY=1)"
                    git switch -c "$_cy_new_branch" || return 1
                fi
                ;;
        esac
    fi

    CLAUDE_CONFIG_DIR="$_cy_config_dir" command claude --dangerously-skip-permissions "$@"
}
alias claude-yolo='claude_yolo'
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 36개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude_yolo --user dispatcher (#287)

POSIX 안전 sentinel 인자 재구성으로 --user / --user=val 가로채고
나머지는 claude 본체로 통과. 알 수 없는 계정 / 디렉토리 부재는
명확한 에러 메시지 + 다음 액션 안내. 기존 main/master 가드 보존.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `_claude_yolo_register_aliases` (단축 alias 자동 파생)

**Files:**
- Modify: `shell-common/tools/integrations/claude.sh`

- [ ] **Step 1: 테스트 추가**

```bash
# ---------- Task 10: alias auto-derivation ----------

@test "bash: claude-yolo-personal alias exists (default ENABLED)" {
    run_in_bash 'type claude-yolo-personal'
    assert_success
    assert_output --partial "alias"
}

@test "bash: claude-yolo-work alias exists (default ENABLED)" {
    run_in_bash 'type claude-yolo-work'
    assert_success
    assert_output --partial "alias"
}

@test "bash: claude-yolo-personal NOT defined when ENABLED='work' (Internal-PC)" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" _claude_yolo_register_aliases; type claude-yolo-personal 2>&1 || echo NOT_FOUND'
    assert_output --partial "NOT_FOUND"
}

@test "bash: claude-yolo-work expands to claude_yolo --user work" {
    run_in_bash 'alias claude-yolo-work'
    assert_success
    assert_output --partial "claude_yolo --user work"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 4개 신규 FAIL

- [ ] **Step 3: 자동 파생 함수 추가 + 로드 시 호출**

```sh
# _claude_yolo_register_aliases — ENABLED 계정마다 단축 alias 자동 생성.
# 매핑 SSOT (_claude_resolve_account --list) 한 곳에서 파생되므로
# 새 계정 추가 시 alias 도 자동 등장. 수동 alias 정의 금지.
_claude_yolo_register_aliases() {
    for _cyra_acct in $(_claude_resolve_account --list); do
        # POSIX-safe: alias 동적 생성 (eval 필요)
        # shellcheck disable=SC2139
        eval "alias claude-yolo-${_cyra_acct}='claude_yolo --user ${_cyra_acct}'"
    done
}

# claude.sh 로드 시 1회 자동 호출
_claude_yolo_register_aliases
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 40개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- shell-common/tools/integrations/claude.sh
git add shell-common/tools/integrations/claude.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
feat(claude-accounts): claude-yolo-{personal,work} 단축 alias 자동 파생 (#287)

매핑 SSOT (_claude_resolve_account --list) 에서 파생 → 새 계정
추가 시 alias 자동 등장. Internal-PC 처럼 ENABLED 가 'work' 만이면
claude-yolo-personal alias 는 등장하지 않음.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `claude/setup.sh` 통합

**Files:**
- Modify: `claude/setup.sh:177-291` (Main Script Logic 재작성)

- [ ] **Step 1: 테스트 추가 (setup 통합 동작 검증)**

```bash
# ---------- Task 11: claude/setup.sh integration ----------

@test "bash: claude/setup.sh creates ~/.claude-personal/ structure" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "${DOTFILES_ROOT}/claude/global-memory"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    [ -L "$HOME/.claude-personal/settings.json" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
}

@test "bash: claude/setup.sh respects CLAUDE_ENABLED_ACCOUNTS=work (Internal-PC)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "${DOTFILES_ROOT}/claude/global-memory"

    run_in_bash "CLAUDE_ENABLED_ACCOUNTS=work CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    [ ! -d "$HOME/.claude-personal" ]
    [ -d "$HOME/.claude-work" ]
    [ -L "$HOME/.claude-work/settings.json" ]
}

@test "bash: claude/setup.sh is idempotent (second run)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "${DOTFILES_ROOT}/claude/global-memory"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "already"
}
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 3개 신규 FAIL (현 setup.sh 는 단일 `~/.claude/` 만 처리)

- [ ] **Step 3: `claude/setup.sh` 재작성**

기존 라인 177-291 (Main Script Logic ~ exit 0) 을 다음으로 교체:

```bash
# --- Main Script Logic (issue #287, Phase 1: multi-account) ---

log_debug "\n--- Claude Code dotfiles setup 시작 ---"

# 필수 dotfiles source 검증
[ -f "$CLAUDE_SETTINGS_SOURCE" ]    || log_error_and_exit "settings.json 없음: $CLAUDE_SETTINGS_SOURCE"
[ -f "$CLAUDE_STATUSLINE_SOURCE" ]  || log_error_and_exit "statusline-command.sh 없음: $CLAUDE_STATUSLINE_SOURCE"
[ -d "$CLAUDE_SKILLS_SOURCE" ]      || log_error_and_exit "skills 디렉토리 없음: $CLAUDE_SKILLS_SOURCE"
[ -d "$CLAUDE_DOCS_SOURCE" ]        || log_error_and_exit "docs 디렉토리 없음: $CLAUDE_DOCS_SOURCE"
[ -d "$CLAUDE_GLOBAL_MEMORY_SOURCE" ] || log_error_and_exit "global-memory 없음: $CLAUDE_GLOBAL_MEMORY_SOURCE"

# 다중 계정 함수 source (claude.sh + env/claude.sh)
. "$DOTFILES_ROOT/shell-common/env/claude.sh"
. "$DOTFILES_ROOT/shell-common/tools/integrations/claude.sh"

# 빈 ~/.claude/ 가드 디렉토리
mkdir -p "$HOME/.claude"

# ~/.claude-shared/plugins/ 보장
mkdir -p "$HOME/.claude-shared/plugins"

# 마이그레이션 가드 안내 (강제 안 함, claude_accounts_init 가 거부)
if [ -d "$HOME/.claude" ] \
   && [ ! -d "$HOME/.claude-personal" ] \
   && [ ! -d "$HOME/.claude-work" ] \
   && [ -n "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
    log_warning "~/.claude/ 에 기존 데이터가 있습니다."
    log_warning "쉘 재시작 후 다음 명령으로 마이그레이션하세요:"
    log_warning "  claude-accounts migrate"
    exit 0
fi

# 활성화된 계정마다 sudoers 등록 + setup
for acct in $(_claude_resolve_account --list); do
    cdir=$(_claude_resolve_account "$acct")
    log_info "Account: $acct → $cdir"

    if [ "${CLAUDE_SKIP_SUDOERS:-0}" != "1" ]; then
        _setup_bind_mount_sudoers \
            "/etc/sudoers.d/claude-skills-mount-${acct}" \
            "Skills (${acct})" \
            "$CLAUDE_SKILLS_SOURCE" \
            "${cdir}/skills"
        _setup_bind_mount_sudoers \
            "/etc/sudoers.d/claude-docs-mount-${acct}" \
            "Docs (${acct})" \
            "$CLAUDE_DOCS_SOURCE" \
            "${cdir}/docs"
    fi

    _claude_account_setup_one "$acct" "$cdir"
done

# --- Verify Links (모든 활성 계정) ---
log_debug "\n--- 심볼릭 링크 확인 ---"
for acct in $(_claude_resolve_account --list); do
    cdir=$(_claude_resolve_account "$acct")
    for link in settings.json statusline-command.sh plugins projects/GLOBAL/memory; do
        if [ -L "${cdir}/${link}" ]; then
            log_dim "✓ ${acct}/${link} 심볼릭 링크 확인됨"
        else
            log_error_and_exit "${acct}/${link} 심볼릭 링크 생성 실패"
        fi
    done
done

# --- Completion Messages ---
log_debug "--- Claude Code dotfiles setup 완료 ---"
echo ""
ux_success "Claude Code 다중 계정 설정 완료!"
ux_info "활성 계정: $(_claude_resolve_account --list | tr '\n' ' ')"
ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
echo ""
ux_section "다음 단계"
ux_bullet "쉘 재시작 후 진단: ${UX_BOLD}claude-accounts status${UX_RESET}"
ux_bullet "처음 사용: ${UX_BOLD}claude-yolo${UX_RESET} (브라우저로 ${CLAUDE_DEFAULT_ACCOUNT} 로그인)"
ux_bullet "다른 계정: ${UX_BOLD}claude-yolo --user <name>${UX_RESET} 또는 ${UX_BOLD}claude-yolo-<name>${UX_RESET}"
echo ""

exit 0
```

- [ ] **Step 4: 테스트 실행 (통과 확인)**

```bash
bats tests/bats/integrations/claude_accounts.bats
```

Expected: 43개 모두 PASS

- [ ] **Step 5: shellcheck + commit**

```bash
tox -e shellcheck -- claude/setup.sh
git add claude/setup.sh tests/bats/integrations/claude_accounts.bats
git commit -m "$(cat <<'EOF'
refactor(claude-setup): 다중 계정 N개 순회로 일반화 (#287)

기존 단일 ~/.claude/ 처리에서 ENABLED 계정 N개 순회로 변경.
sudoers 도 계정별로 등록 (claude-skills-mount-{acct}, claude-docs-mount-{acct}).
unmigrated ~/.claude/ 발견 시 setup 중단 + migrate 안내.
CLAUDE_SKIP_SUDOERS=1 / CLAUDE_SKIP_BIND_MOUNT=1 로 단위 테스트 환경 우회.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: 통합 검증 (lint + bats 전체 + 수동 시나리오)

**Files:** (검증만, 변경 없음)

- [ ] **Step 1: 전체 shellcheck 통과 확인**

```bash
tox -e shellcheck -- \
    shell-common/env/claude.sh \
    shell-common/env/claude.local.example \
    shell-common/tools/integrations/claude.sh \
    claude/setup.sh
```

Expected: exit 0, 경고 없음.

- [ ] **Step 2: shfmt diff 확인 후 적용**

```bash
shfmt -d -i 4 \
    shell-common/env/claude.sh \
    shell-common/tools/integrations/claude.sh
```

차이가 있으면 `shfmt -w -i 4 <파일>` 로 적용 후 commit.

- [ ] **Step 3: bats 전체 테스트 실행**

```bash
bats tests/bats/integrations/claude_accounts.bats
bats tests/bats/init/env_vars.bats         # 회귀: 기존 env 테스트
bats tests/bats/init/sourcing.bats         # 회귀: 로딩 메커니즘
```

Expected: 모두 PASS, 기존 테스트 회귀 0건.

- [ ] **Step 4: 수동 시나리오 검증 (External-PC, 현재)**

```bash
# 새 zsh 셸에서 (다중 계정 함수 + alias 로드 확인)
source ~/.zshrc
type claude-yolo-personal       # → alias 'claude_yolo --user personal'
type claude-yolo-work           # → alias 'claude_yolo --user work'
type claude-accounts            # → alias 'claude_accounts'
echo "$CLAUDE_DEFAULT_ACCOUNT"  # → personal
echo "$CLAUDE_ENABLED_ACCOUNTS" # → personal work

# 진단 (아직 setup 안 한 상태에서 호출)
claude-accounts status
# Expected: 계정 디렉토리 없음 표시

# Dry-run dispatcher (실제 claude 호출 전 분기 검증)
claude-yolo --user xyz   # → "Unknown account: xyz"
claude-yolo --user work  # → "Account directory missing: ~/.claude-work"
                         #   "Run: claude-accounts setup"
```

- [ ] **Step 5: 수동 setup + 첫 로그인 (External-PC)**

```bash
./setup.sh
# Expected:
#   - ~/.claude/ 빈 디렉토리 보장
#   - ~/.claude-shared/plugins/ 생성
#   - ~/.claude-personal/ 6개 link/mount
#   - ~/.claude-work/ 6개 link/mount
#   - sudoers 4개 등록 (skills/docs × personal/work)

claude-accounts status
# Expected: 두 계정 모두 ✓ (단 .credentials.json 은 NOT logged in)

# 첫 로그인 (브라우저 자동 열림)
claude-yolo --user work
# → deity719g@gmail.com 로 로그인
# → ~/.claude-work/.credentials.json 생성

claude-accounts status
# Expected: work 계정의 Credentials 가 ✓ logged in
```

- [ ] **Step 6: 멱등성 재검증**

```bash
./setup.sh   # 두 번째 실행
# Expected: 모든 항목 "already" / "skipping" 메시지, 변경 0건

claude-accounts setup   # 동등 실행
# Expected: 동일
```

- [ ] **Step 7: 마지막 commit (lint/format 보정 있을 시)**

```bash
git status
# 변경 없으면 다음 단계, 있으면:
git add -u
git commit -m "$(cat <<'EOF'
chore(claude-accounts): shfmt 포맷팅 정리 (#287)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review (이 plan 작성 후 자체 점검)

### Spec coverage

| Spec 섹션 | 커버 task |
|---|---|
| 매핑 SSOT (`_claude_resolve_account`) | Task 3 |
| Dispatcher (`claude_yolo`) | Task 9 |
| 단축 alias 자동 파생 | Task 10 |
| 멱등 setup (`claude_accounts_init`) | Task 5 |
| PC별 오버라이드 (`claude.local.sh`) | Task 1, 2 |
| 진단 CLI (`claude-accounts status`) | Task 6, 8 |
| 마이그레이션 (`claude_accounts_migrate`) | Task 7 |
| `claude/setup.sh` 통합 | Task 11 |
| 디렉토리 6종 (settings/statusline/plugins/global-memory + skills/docs mount) | Task 5 (`_claude_account_setup_one`) |
| `~/.claude/` 빈 가드 | Task 5 (init), Task 11 (setup.sh) |
| `~/.claude-shared/plugins/` 공유 | Task 5 (init), Task 7 (migrate) |
| 멱등 헬퍼 | Task 4 |
| Lint (shellcheck/shfmt) | 각 task Step 5 + Task 12 |
| 테스트 (bats) | 각 task TDD Step 1-4 |

### Placeholder scan

- TBD/TODO: 없음 ✓
- 모호한 "add error handling" 등: 없음 (모든 에러 메시지·동작 명시) ✓
- "Similar to Task N" 단축 코드: 없음 (모든 코드 블록 완전 작성) ✓

### Type/identifier consistency

- `_claude_resolve_account` 호출은 모든 task 에서 동일 시그니처
- `_claude_account_setup_one acct cdir` 호출은 Task 5, 11 일관
- `CLAUDE_CONFIG_DIR` 환경변수명 일관
- `CLAUDE_SKIP_BIND_MOUNT=1`, `CLAUDE_SKIP_SUDOERS=1` 환경변수는 단위 테스트용 — 두 변수 모두 Task 5 (`_claude_account_setup_one`), Task 11 (`claude/setup.sh`) 에서 일관 사용
- 함수 prefix `_cy_*`, `_cra_*`, `_caso_*`, `_cai_*`, `_cas_*`, `_cebm_*`, `_ces_*`, `_cyra_*`, `_cam_*` — task 별 prefix 분리로 변수 충돌 방지

### Scope check

- Phase 1만 포함, Phase 2 (`gwt --launch --user`) 미포함 ✓
- Windows PowerShell 미포함 ✓
- 프로젝트별 `.env` 자동 로딩 미포함 ✓
