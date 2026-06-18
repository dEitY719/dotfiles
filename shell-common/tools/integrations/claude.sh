#!/bin/sh
# shell-common/tools/claude.sh
# Claude Code CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# Reference: https://code.claude.com/docs/en/getting-started
# ═══════════════════════════════════════════════════════════════
#
# Use: clinstall (runs official native installer)
# Use: delete_claude (uninstall and clean)
#
# Storage layout: skills/, docs/ are exposed to Claude Code via a single
# top-level directory symlink per account (issue #575). The legacy bind-
# mount path (#287) and the interim per-skill symlink path (#342, #344)
# were removed in favour of one symlink that mirrors the SSOT atomically
# and survives reboot without sudoers entries.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ═══════════════════════════════════════════════════════════════
# Dependency Check: Ensure jq is installed
# ═══════════════════════════════════════════════════════════════

ensure_jq() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ensure_jq.sh"
}

# NOTE: Do not auto-install dependencies at shell init time.
# If jq is required for a specific workflow, call `ensure_jq` explicitly.

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# ═══════════════════════════════════════════════════════════════

clinstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Uninstallation
# ═══════════════════════════════════════════════════════════════

delete_claude() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/delete_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Configuration Initialization
# ═══════════════════════════════════════════════════════════════

claude_init() {
    local settings_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    local settings_target="$HOME/.claude/settings.json"
    local statusline_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/statusline-command.sh"
    local statusline_target="$HOME/.claude/statusline-command.sh"
    local skills_source_dir="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skills_target_dir="$HOME/.claude/skills"

    ux_info "Initializing Claude Code configuration..."
    echo ""

    # Create ~/.claude directory if not exists
    if [ ! -d "$HOME/.claude" ]; then
        ux_info "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Create ~/.claude/skills directory if not exists
    if [ ! -d "$skills_target_dir" ]; then
        ux_info "Creating ~/.claude/skills directory..."
        mkdir -p "$skills_target_dir"
    fi

    # Handle settings.json
    ux_section "Settings Configuration"
    if [ -L "$settings_target" ]; then
        ux_success "settings.json symbolic link already exists"
    elif [ -f "$settings_target" ]; then
        ux_warning "settings.json exists as regular file"
        ux_info "Backing up to settings.json.backup..."
        mv "$settings_target" "$settings_target.backup"
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    else
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    fi
    echo ""

    # Handle statusline-command.sh
    ux_section "Statusline Configuration"
    if [ -L "$statusline_target" ]; then
        ux_success "statusline-command.sh symbolic link already exists"
    elif [ -f "$statusline_target" ]; then
        ux_warning "statusline-command.sh exists as regular file"
        ux_info "Backing up to statusline-command.sh.backup..."
        mv "$statusline_target" "$statusline_target.backup"
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    else
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    fi
    echo ""

    # Handle skills directory
    ux_section "Claude Code Skills"
    skill_count=0
    if [ -d "$skills_source_dir" ]; then
        for skill_file in "$skills_source_dir"/*.md; do
            if [ -f "$skill_file" ]; then
                skill_name=$(basename "$skill_file")
                skill_target="$skills_target_dir/$skill_name"

                if [ -L "$skill_target" ]; then
                    ux_success "$skill_name (already linked)"
                elif [ -f "$skill_target" ]; then
                    ux_warning "$skill_name exists as regular file"
                    ux_info "Backing up to $skill_name.backup..."
                    mv "$skill_target" "$skill_target.backup"
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                else
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                fi
                skill_count=$((skill_count + 1))
            fi
        done

        if [ "$skill_count" -eq 0 ]; then
            ux_info "No skill files found in $skills_source_dir"
        else
            ux_success "Total: $skill_count skill(s) linked"
        fi
    else
        ux_warning "Skills source directory not found: $skills_source_dir"
    fi
    echo ""

    ux_header "Claude Code Initialization Complete"
    echo ""

    ux_section "Configuration Files"
    for config_target in "$settings_target" "$statusline_target"; do
        if [ -e "$config_target" ]; then
            ls -la -- "$config_target"
        fi
    done
    echo ""

    ux_section "Skills"
    if [ -d "$skills_target_dir" ]; then
        linked_skill_found=0
        for skill_target_file in "$skills_target_dir"/*.md; do
            if [ -e "$skill_target_file" ]; then
                ls -la -- "$skill_target_file"
                linked_skill_found=1
            fi
        done
        if [ "$linked_skill_found" -eq 0 ]; then
            ux_info "(no skills found)"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Settings Editor
# ═══════════════════════════════════════════════════════════════

claude_edit_settings() {
    local settings_file="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"

    if [ ! -f "$settings_file" ]; then
        ux_error "Settings file not found: $settings_file"
        return 1
    fi

    ux_header "Claude Code Settings"
    ux_info "File: $settings_file"
    echo ""

    ${EDITOR:-vim} "$settings_file"

    echo ""
    ux_success "Settings file edited"
    ux_info "Changes will take effect immediately (settings.json is symlinked)"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Marketplace Plugins Management
# ═══════════════════════════════════════════════════════════════

open_claude_plugins() {
    local plugins_dir="$HOME/.claude/plugins/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found: $plugins_dir"
        ux_info "Plugins will be available after Claude Code marketplace setup"
        return 1
    fi

    ux_header "Opening Claude Marketplace Plugins"
    ux_info "Location: $plugins_dir"
    echo ""

    # Open in VSCode
    code "$plugins_dir"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Workflow Helpers
# ═══════════════════════════════════════════════════════════════

# Plan mode: Interactive mode (recommended)
alias clplan='claude'

# Test writing helper
cltest() {
    if [ -z "$1" ]; then
        ux_header "cltest"
        ux_usage "cltest" "\"request\"" "Run Claude with prompt for test writing"
        ux_bullet "Example: ${UX_INFO}cltest \"Write authentication tests\"${UX_RESET}"
        return 1
    fi
    claude -p "$1"
}

# Skip permissions mode (use with caution)
clskip() {
    if [ -z "$1" ]; then
        ux_header "clskip"
        ux_usage "clskip" "\"request\"" "Run Claude skipping permission prompts (caution)"
        ux_bullet "Example: ${UX_INFO}clskip \"Refactor this module\"${UX_RESET}"
        echo ""
        ux_warning "This will skip all permission prompts"
        ux_bullet "Start with small scopes and use carefully"
        return 1
    fi

    ux_warning "Running in skip permissions mode"
    ux_info "Request: $1"
    echo ""
    claude --dangerously-skip-permissions -p "$1"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Direct Permission Bypass Alias
# ═══════════════════════════════════════════════════════════════

alias claude-skip='claude --dangerously-skip-permissions'

# _claude_yolo_export_settings_env — propagate settings.local.json `env` block
# to the shell process so `claude` inherits it via the normal env path. Some
# Claude Code releases do not apply the settings.local.json env block to the
# spawned child, so the gateway URL / auth headers configured there silently
# never reach the request layer (symptom: `Failed to connect to
# api.anthropic.com` on a Samsung-internal PC even with a fully-correct
# settings.local.json). This helper is the belt-and-suspenders fix: jq-read
# the env block and `export` each key. Idempotent, silent, no-op when jq or
# the file is missing.
#
# Parameters:
#   $1: Claude config dir (e.g. ~/.claude or ~/.claude-work)
#
# Why eval is safe here: settings.local.json is gitignored and user-owned;
# its contents are already trusted by Claude Code itself. `@sh` quoting on
# the value handles embedded newlines and shell metacharacters.
_claude_yolo_export_settings_env() {
    local _cysee_dir="${1:-}"
    [ -n "$_cysee_dir" ] || return 0
    local _cysee_file="$_cysee_dir/settings.local.json"
    [ -f "$_cysee_file" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Declare and assign separately to avoid SC2155 (local + command
    # substitution masks the substitution's exit status). The colleague
    # PR #576 fixed the same pattern elsewhere in setup.sh.
    local _cysee_exports
    _cysee_exports=$(jq -r '
        .env // {}
        | to_entries[]
        | "export \(.key)=\(.value | tostring | @sh)"
    ' "$_cysee_file" 2>/dev/null)

    # Explicit `return 0` — without it, the final `[ -n "" ] && ...` short-
    # circuits with exit 1 when the env block is absent / malformed, which
    # would propagate to callers expecting silent no-op.
    if [ -n "$_cysee_exports" ]; then
        eval "$_cysee_exports"
    fi
    return 0
}

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
# 3. CLAUDE_CONFIG_DIR 환경 주입 + command claude --dangerously-skip-permissions
#
# main/master 자동 scratch/* 가드 + CLAUDE_YOLO_STAY env 는 #647 에서 제거됨 —
# 격리 워크플로는 `gwt spawn --launch --ai claude <task>` 가 SSOT.
claude_yolo() {
    _cy_account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"

    # zsh disables word-splitting; emulate sh inside this function.
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # --user 가로채고 나머지는 위치 인자로 보존 (POSIX 안전).
    # --no-sync 는 #575 에서 skills/docs 가 디렉토리 symlink 가 되며 사라짐
    # — 쉘 시작마다 동기화할 항목이 더 이상 없다. 알 수 없는 인자는
    # claude 본체로 그대로 전달된다.
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

    # Internal-PC single-account override (issue #571, F-2). When
    # ~/.dotfiles-setup-mode == internal, the multi-account layout is
    # intentionally disabled — Claude Code config lives at ~/.claude/ and
    # `claude-accounts` is not in use. This branch runs BEFORE
    # _claude_resolve_account so a sandbox PC with an unset/empty
    # CLAUDE_ENABLED_ACCOUNTS can't trip the "Unknown account" path.
    if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
        _cy_config_dir="$HOME/.claude"
        _cy_account="internal"
    else
        # 계정 → CONFIG_DIR (SSOT 호출)
        _cy_config_dir=$(_claude_resolve_account "$_cy_account") || {
            ux_error "Unknown account: $_cy_account"
            ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
            return 1
        }
    fi

    [ -d "$_cy_config_dir" ] || {
        ux_error "Account directory missing: $_cy_config_dir"
        ux_info  "Run: claude-accounts setup"
        return 1
    }

    # Pre-launch .claude.json integrity guard (issue #294).
    # See _claude_restore_if_reset for the heuristic and rationale.
    _claude_restore_if_reset "$_cy_config_dir"

    # Pre-launch account binding sanity (issue #300, item B).
    # Opt-in via CLAUDE_ACCOUNT_EMAIL_<account>; silent unless the mapping
    # AND a populated .claude.json AND a mismatch are all present.
    _claude_validate_login "$_cy_config_dir" "$_cy_account"

    # Apply settings.local.json env block at the shell level too — works
    # around Claude Code releases where the env block isn't propagated to
    # the spawned process. The subshell isolates exports so the caller's
    # shell env (which may persist after `claude-yolo` exits) is not
    # polluted with e.g. NODE_TLS_REJECT_UNAUTHORIZED=0.
    (
        _claude_yolo_export_settings_env "$_cy_config_dir"
        CLAUDE_CONFIG_DIR="$_cy_config_dir" command claude --dangerously-skip-permissions "$@"
    )
}

# _claude_restore_if_reset — auto-restore .claude.json from sealed snapshot
# when it has been reset to the "first-start placeholder" state (issue #294).
#
# Trigger requires ALL of:
#   1. live .claude.json exists and is < 500 bytes (healthy file is 10-100 KB)
#   2. live file contains `firstStartTime` but neither `oauthAccount` nor
#      `migrationVersion` (positive evidence of reset state, not a partial
#      write or unrelated tiny file)
#   3. .claude.json.preserved-by-migrate snapshot exists in same dir
#
# Rationale: Claude CLI sometimes rewrites .claude.json to just
# `{"firstStartTime":"..."}` on first run with a previously-unseen
# CLAUDE_CONFIG_DIR, wiping the oauth + migration cache. Since the bug is
# upstream, we can't prevent the rewrite — but we restore before the next
# launch, so the user never sees the "configuration file not found" prompt.
#
# Bypass: delete the snapshot file (`rm <dir>/.claude.json.preserved-by-migrate`)
# to opt out — useful if the user intentionally reset their config.
_claude_restore_if_reset() {
    _crir_dir="$1"
    _crir_live="$_crir_dir/.claude.json"
    _crir_snap="$_crir_dir/.claude.json.preserved-by-migrate"

    # Snapshot 부재 시에는 어느 쪽으로도 복원 불가 — silent return.
    [ -f "$_crir_snap" ] || return 0

    # Missing-case branch (issue #500, F-2): live .claude.json 자체가
    # 사라진 상태도 reset 의 한 변종으로 처리. Claude CLI 가 빈
    # CLAUDE_CONFIG_DIR 진입 시 "configuration file not found" 프롬프트를
    #띄우기 전에 sealed snapshot 으로 복원해 사용자 개입을 없앤다.
    if [ ! -f "$_crir_live" ]; then
        ux_warning "Detected missing .claude.json — restoring from sealed migrate snapshot"
        ux_info    "  → snapshot: $_crir_snap"
        if cp "$_crir_snap" "$_crir_live" 2>/dev/null; then
            _crir_restored_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
            ux_success "  Restored $_crir_live (${_crir_restored_size:-?} bytes)"
        else
            ux_error "  Restore failed — proceeding anyway (claude may prompt for re-login)"
        fi
        return 0
    fi

    _crir_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
    [ -n "$_crir_size" ] || return 0
    [ "$_crir_size" -lt 500 ] || return 0

    grep -q 'firstStartTime' "$_crir_live" 2>/dev/null || return 0
    grep -qE 'oauthAccount|migrationVersion' "$_crir_live" 2>/dev/null && return 0

    ux_warning "Detected reset .claude.json (${_crir_size}B, no oauth/migration cache)"
    ux_info    "  → restoring from sealed migrate snapshot: $_crir_snap"
    if cp "$_crir_snap" "$_crir_live" 2>/dev/null; then
        _crir_restored_size=$(wc -c < "$_crir_live" 2>/dev/null | tr -d ' ')
        ux_success "  Restored $_crir_live (${_crir_restored_size:-?} bytes)"
    else
        ux_error "  Restore failed — proceeding anyway (claude may prompt for re-login)"
    fi
}

# _claude_validate_login — expected ↔ actual oauth email check (issue #300-B).
#
# Catches the "wrong Google account on browser" trap: a leftover personal
# Google session bleeds into the OAuth flow for `claude-yolo --user work`,
# leaving the work CLAUDE_CONFIG_DIR populated with personal credentials.
# The code in this repo can't influence the browser, but it CAN cross-check
# the resulting .claude.json against an expected email and warn loudly so
# the user can recover before the misbinding becomes load-bearing.
#
# Opt-in: caller defines `CLAUDE_ACCOUNT_EMAIL_<account>` (e.g.
# `CLAUDE_ACCOUNT_EMAIL_work=alice@corp.com`) in claude.local.sh. Without
# the mapping the function silently returns — zero-config / zero-regression
# for everyone who doesn't opt in.
_claude_validate_login() {
    _cvl_dir="$1"
    _cvl_acct="$2"

    _cvl_expected=$(_claude_expected_email "$_cvl_acct")
    [ -n "$_cvl_expected" ] || return 0

    _cvl_json="$_cvl_dir/.claude.json"
    [ -f "$_cvl_json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    _cvl_actual=$(jq -r '.oauthAccount?.emailAddress? // empty' "$_cvl_json" 2>/dev/null)
    [ -n "$_cvl_actual" ] || return 0
    [ "$_cvl_expected" = "$_cvl_actual" ] && return 0

    ux_warning "Account mismatch on '$_cvl_acct':"
    ux_warning "  expected: $_cvl_expected (CLAUDE_ACCOUNT_EMAIL_${_cvl_acct})"
    ux_warning "  actual:   $_cvl_actual (.claude.json oauthAccount)"
    ux_info    "  → 다른 Google 계정으로 잘못 로그인된 자격증명일 수 있습니다."
    ux_info    "  → 복구: rm '$_cvl_dir/.credentials.json' '$_cvl_json' && claude-yolo --user $_cvl_acct"
}
alias claude-yolo='claude_yolo'

# ═══════════════════════════════════════════════════════════════
# Multi-account configuration (issue #287)
# ═══════════════════════════════════════════════════════════════

# _dotfiles_setup_mode — read ~/.dotfiles-setup-mode and canonicalise.
#
# Returns one of: public | internal | external | "" (file missing).
# Legacy numeric values ("1|2|3") written by older shell-common/setup.sh
# (pre-#571) are translated to their symbolic equivalents, so users
# don't hit a wedge after upgrading. Empty when the file doesn't exist
# (fresh install before setup.sh has run).
#
# Used by claude_yolo (F-2) to bypass multi-account resolution and by
# claude_accounts_rollback (F-3) to confirm the rollback target.
_dotfiles_setup_mode() {
    _dsm_file="$HOME/.dotfiles-setup-mode"
    [ -f "$_dsm_file" ] || { echo ""; return 0; }
    _dsm_raw=$(tr -d ' \t\n\r' < "$_dsm_file" 2>/dev/null)
    case "$_dsm_raw" in
        1|public)   echo "public" ;;
        2|internal) echo "internal" ;;
        3|external) echo "external" ;;
        *)          echo "$_dsm_raw" ;;
    esac
}

# _claude_resolve_account — 계정 매핑 SSOT (convention-based, issue #568).
# Usage:
#   _claude_resolve_account <name>     → echo "$HOME/.claude-<name>" when
#                                        <name> is in CLAUDE_ENABLED_ACCOUNTS
#                                        and passes the safe-identifier
#                                        regex. return 1 otherwise.
#   _claude_resolve_account --list     → echo ENABLED accounts (one per line)
#                                        that pass the safe-identifier regex.
#   _claude_resolve_account --list-all → deprecated; same as --list. Kept
#                                        for back-compat with external
#                                        scripts that may still call it.
#
# 새 계정 추가 = claude.local.sh 의 CLAUDE_ENABLED_ACCOUNTS 에 단어 추가
# 만으로 끝. 코드 수정 불필요. 디렉터리는 자동으로 ~/.claude-<name>.
#
# Safe-identifier regex: ^[a-z][a-z0-9_-]*$
# - 첫 글자 소문자, 뒤로 소문자·숫자·하이픈·언더스코어.
# - alias 명·env-var 접미사·디렉터리명 셋 다 안전하게 쓰일 식별자.
_claude_resolve_account() {
    # zsh disables word-splitting by default; emulate sh inside this function
    # so `for x in $LIST` behaves identically to bash/dash. (See MEMORY.md
    # "Zsh-Specific Tracing Behavior" for the same pattern in gcp_scan.sh.)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    case "$1" in
        --list|--list-all)
            # --list-all 은 issue #568 에서 --list 로 통합. 외부 사용자
            # 보호용 호환 alias — 향후 메이저 버전에서 제거 가능.
            # 검증을 인라인으로 — 재귀 호출 시 ENABLED 가 "--list" 같은
            # 플래그 토큰을 포함하면 무한 재귀에 빠질 수 있고, 재귀는
            # O(N²) 비용을 만든다 (gemini review on PR #569).
            # ${VAR:-} 로 set -u 환경에서 unbound 회피.
            # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
            for _cra_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
                case "$_cra_acct" in
                    [a-z]*) ;;
                    *) continue ;;
                esac
                case "$_cra_acct" in
                    *[!a-z0-9_-]*) continue ;;
                esac
                echo "$_cra_acct"
            done
            return 0
            ;;
    esac

    # name validation: must start with lowercase letter, rest [a-z0-9_-]
    case "$1" in
        [a-z]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!a-z0-9_-]*) return 1 ;;
    esac

    # ENABLED whitelist check — unknown names fail even if regex-valid.
    # Preserves the "Unknown account: xyz" path in claude_yolo for typos.
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _cra_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
        if [ "$_cra_acct" = "$1" ]; then
            echo "$HOME/.claude-$1"
            return 0
        fi
    done
    return 1
}

# _claude_expected_email <account-name> — expected oauth email lookup.
# Reads CLAUDE_ACCOUNT_EMAIL_<account> if defined, else echoes nothing.
# Opt-in mapping convention from issue #300, items B and C — kept in a
# helper so claude_yolo and claude_accounts_status share the same source
# of truth.
#
# Uses eval (not ${!var}) for POSIX sh portability — the input is always
# an account name vetted by _claude_resolve_account, so injection is not
# a concern.
_claude_expected_email() {
    _ceeem_acct="$1"
    [ -n "$_ceeem_acct" ] || return 0
    eval "echo \"\${CLAUDE_ACCOUNT_EMAIL_${_ceeem_acct}:-}\""
}

# _claude_ensure_symlink — 멱등 symlink 생성.
# - 없음 → 생성
# - 같은 target 의 symlink → skip (출력 "already")
# - bind-mount → sudo umount 후 재생성 (issue #575 마이그레이션 경로)
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
    elif _is_mounted "$_ces_tgt" 2>/dev/null; then
        # Legacy bind-mount survivor from the #287/#342-era multi-account
        # layout. The kernel refuses `mv` on a mount point, so unmount
        # first and then fall through to the normal `ln -s` path.
        ux_warning "  bind-mount detected at $_ces_tgt — unmounting (sudo may prompt)"
        if ! sudo umount "$_ces_tgt"; then
            ux_error "  unmount failed: $_ces_tgt"
            return 1
        fi
        ux_success "  ✓ unmounted: $_ces_tgt"
        # Three post-umount states: (a) dir already gone, (b) empty
        # backing dir, (c) non-empty backing dir hiding user data.
        # Try rmdir for (b), and if (c) reveals a populated directory,
        # back it up so `ln -s` below has a clear slot (the next elif
        # would be skipped because this branch already matched).
        if [ -e "$_ces_tgt" ] && ! rmdir "$_ces_tgt" 2>/dev/null; then
            _ces_backup="${_ces_tgt}-$(date +%Y%m%d%H%M%S)-original"
            ux_warning "  backing up revealed directory: $_ces_tgt → $_ces_backup"
            mv "$_ces_tgt" "$_ces_backup" || return 1
        fi
    elif [ -e "$_ces_tgt" ]; then
        # Backup naming matches claude/setup.sh:100 legacy convention
        # so users with a mixed-version setup see one consistent format.
        _ces_backup="${_ces_tgt}-$(date +%Y%m%d%H%M%S)-original"
        ux_warning "  backing up existing file: $_ces_tgt → $_ces_backup"
        mv "$_ces_tgt" "$_ces_backup"
    fi

    ln -s "$_ces_src" "$_ces_tgt"
    ux_success "  created symlink: $_ces_tgt → $_ces_src"
}

# _claude_ensure_settings_copy — settings.json 멱등 실파일 설치 (#940).
#
# Claude Code 의 /model 은 active config dir 의 settings.json 에 직접
# persist 한다. 이 파일이 dotfiles SSOT 로의 symlink 면 write-through 로
# tracked 파일이 오염된다 (#924 의 재발 경로). internal 모드가 #687 에서
# 실파일로 전환한 것과 같은 원리를 다중 계정 모드에도 적용:
#   - 기존 symlink (canonical / worktree-tainted 불문) 는 제거 후 SSOT 복사
#   - 기존 실파일의 개인 `model` 키는 settings.local.json 으로 1회 이주
#     (jq 없으면 경고 후 SSOT 가 덮어씀)
#   - dangling settings.local.json symlink (teardown 된 worktree 잔재) 제거
_claude_ensure_settings_copy() {
    _cesc_src="$1"
    _cesc_tgt="$2"
    _cesc_local="$(dirname "$_cesc_tgt")/settings.local.json"

    # dangling settings.local.json 정리가 model 이주보다 먼저 — 깨진 링크를
    # 통해 쓰면 소멸한 worktree 경로로 write 가 향해 실패한다 (#940).
    if [ -L "$_cesc_local" ] && [ ! -e "$_cesc_local" ]; then
        # Routine one-time cleanup, not a problem needing user action — info
        # severity keeps ⚠️ reserved for genuine warnings (issue #995).
        rm -f "$_cesc_local" \
            && ux_info "  removed dangling settings.local.json symlink: $_cesc_local"
    fi

    if [ -L "$_cesc_tgt" ]; then
        # Intended idempotent migration (#940) — info severity, not ⚠️ (#995).
        rm "$_cesc_tgt" \
            && ux_info "  legacy settings.json symlink → real file (#940): $_cesc_tgt"
    elif [ -f "$_cesc_tgt" ] && ! cmp -s "$_cesc_src" "$_cesc_tgt"; then
        # /model 이 남긴 개인 model 키 보존 — SSOT 복사로 사라지기 전에
        # settings.local.json 으로 이주. local 에 이미 model 이 있으면 그대로.
        if command -v jq >/dev/null 2>&1; then
            _cesc_model=$(jq -r '.model // empty' "$_cesc_tgt" 2>/dev/null)
            if [ -n "$_cesc_model" ]; then
                if [ ! -f "$_cesc_local" ]; then
                    printf '{ "model": "%s" }\n' "$_cesc_model" > "$_cesc_local"
                    chmod 600 "$_cesc_local"
                    ux_info "  migrated model '$_cesc_model' → $_cesc_local"
                elif [ -z "$(jq -r '.model // empty' "$_cesc_local" 2>/dev/null)" ]; then
                    # mktemp: 명시 템플릿 + TMPDIR 폴백 — BSD/macOS 이식성과
                    # 공유 /tmp 의 예측 가능한 이름 회피 (PR #943 리뷰).
                    # 실패 시 soft-fail — sourced 함수이므로 exit 금지.
                    _cesc_tmp=$(mktemp "${TMPDIR:-/tmp}/claude_settings.XXXXXX") || _cesc_tmp=
                    if [ -z "$_cesc_tmp" ]; then
                        ux_warning "  mktemp failed — model migration skipped, keeping $_cesc_local as-is"
                    elif jq --arg m "$_cesc_model" '.model = $m' "$_cesc_local" > "$_cesc_tmp"; then
                        mv "$_cesc_tmp" "$_cesc_local"
                        ux_info "  migrated model '$_cesc_model' → $_cesc_local"
                    else
                        rm -f "$_cesc_tmp"
                        ux_warning "  model migration failed — keeping $_cesc_local as-is"
                    fi
                fi
            fi
        else
            ux_warning "  jq 없음 — $_cesc_tgt 의 로컬 변경(model 등)은 SSOT 로 덮어씀"
        fi
    fi

    if [ -f "$_cesc_tgt" ] && cmp -s "$_cesc_src" "$_cesc_tgt"; then
        ux_info "  ✓ settings.json up to date (real file): $_cesc_tgt"
        return 0
    fi
    if ! cp "$_cesc_src" "$_cesc_tgt"; then
        ux_error "  settings.json copy failed: $_cesc_src → $_cesc_tgt"
        return 1
    fi
    chmod 600 "$_cesc_tgt"
    ux_success "  installed settings.json (real file): $_cesc_tgt"
}

# _claude_dir_sync_one / _claude_count_dir_sync / claude_skills_sync —
# REMOVED (issue #575).
#
# These used to maintain per-skill / per-doc symlinks under
# "<cdir>/skills/" and "<cdir>/docs/" as a sudo-free replacement for the
# legacy bind-mount design (#342, #344). Issue #575 collapses that into
# a single top-level symlink — "<cdir>/skills" / "<cdir>/docs" — so
# per-entry sync is no longer needed; the SSOT is reflected atomically
# and new skills appear instantly without re-running setup. The
# `claude-skills-sync` alias and `claude-accounts skills-sync`
# sub-command went away with them.

# _claude_compose_skills_dir <src_skills_dir> <target_skills_dir>
#
# F-8 (issue #707): replace the directory-level symlink "<tgt> -> <src>"
# (the #575 design) with a real directory at <tgt> that contains an
# entry-level symlink for every skill subdirectory of <src>. This is
# what lets a follow-up overlay step (scripts/setup-company-skills.sh)
# layer additional skills from a private user-supplied directory into
# the same <tgt> without those skills ever entering the dotfiles git
# tree.
#
# Idempotent — converges on the same state on repeat calls. Also
# performs three migrations in place:
#   1. If <tgt> is a legacy directory-symlink (#575), remove it and
#      replace with a real directory.
#   2. If <tgt> is a legacy bind-mount (#287/#342 era), unmount it.
#   3. Stale entries — symlinks under <tgt> that point into <src> but
#      whose target no longer exists — are removed. Symlinks pointing
#      outside <src> (e.g. company-skills overlays) are left alone.
_claude_compose_skills_dir() {
    _ccsd_src="${1:-}"
    _ccsd_tgt="${2:-}"
    if [ -z "$_ccsd_src" ] || [ -z "$_ccsd_tgt" ]; then
        ux_error "_claude_compose_skills_dir: src and tgt required"
        return 1
    fi
    if [ ! -d "$_ccsd_src" ]; then
        ux_error "_claude_compose_skills_dir: source missing: $_ccsd_src"
        return 1
    fi

    if [ -L "$_ccsd_tgt" ]; then
        ux_info "  legacy dir-symlink at $_ccsd_tgt — converting to entry composition"
        rm -f "$_ccsd_tgt"
    elif _is_mounted "$_ccsd_tgt" 2>/dev/null; then
        ux_warning "  bind-mount detected at $_ccsd_tgt — unmounting (sudo may prompt)"
        if ! sudo umount "$_ccsd_tgt"; then
            ux_error "  unmount failed: $_ccsd_tgt"
            return 1
        fi
        # Post-umount the underlying directory is revealed. If empty,
        # rmdir clears it and `mkdir -p` below creates a fresh slot. If
        # populated (stale skill data from before the bind-mount era),
        # back it up so the entry-composition loop does not mingle
        # symlinks with the user's data. Mirrors _claude_ensure_symlink's
        # post-umount backup (line 625) so a mixed-version install sees
        # one consistent naming convention.
        if [ -e "$_ccsd_tgt" ] && ! rmdir "$_ccsd_tgt" 2>/dev/null; then
            _ccsd_backup="${_ccsd_tgt}-$(date +%Y%m%d%H%M%S)-original"
            ux_warning "  backing up revealed directory: $_ccsd_tgt → $_ccsd_backup"
            mv "$_ccsd_tgt" "$_ccsd_backup" || return 1
        fi
    elif [ -e "$_ccsd_tgt" ] && [ ! -d "$_ccsd_tgt" ]; then
        _ccsd_backup="${_ccsd_tgt}-$(date +%Y%m%d%H%M%S)-original"
        ux_warning "  unexpected file at $_ccsd_tgt — backing up: $_ccsd_backup"
        mv "$_ccsd_tgt" "$_ccsd_backup" || return 1
    fi
    mkdir -p "$_ccsd_tgt"

    _ccsd_added=0
    _ccsd_refreshed=0
    for _ccsd_dir in "$_ccsd_src"/*/; do
        [ -d "$_ccsd_dir" ] || continue
        _ccsd_name="${_ccsd_dir%/}"
        _ccsd_name="${_ccsd_name##*/}"
        _ccsd_link="${_ccsd_tgt}/${_ccsd_name}"
        _ccsd_want="${_ccsd_src}/${_ccsd_name}"

        if [ -L "$_ccsd_link" ]; then
            if [ "$(readlink "$_ccsd_link")" = "$_ccsd_want" ]; then
                continue
            fi
            rm -f "$_ccsd_link"
            _ccsd_refreshed=$((_ccsd_refreshed + 1))
            ux_info "  refreshed skill: $_ccsd_name"
        elif [ -e "$_ccsd_link" ]; then
            ux_warning "  skill entry blocked by non-symlink — skipped: $_ccsd_link"
            continue
        else
            _ccsd_added=$((_ccsd_added + 1))
            ux_info "  new skill: $_ccsd_name"
        fi
        ln -s "$_ccsd_want" "$_ccsd_link" || {
            ux_error "  symlink failed: $_ccsd_link -> $_ccsd_want"
            return 1
        }
    done

    # Drop stale dotfiles-sourced links whose source entry was removed.
    # Only touch symlinks that point into <src> so private overlay
    # links (company-skills, user-managed entries) survive.
    for _ccsd_existing in "$_ccsd_tgt"/*; do
        [ -L "$_ccsd_existing" ] || continue
        _ccsd_target_path=$(readlink "$_ccsd_existing")
        case "$_ccsd_target_path" in
            "$_ccsd_src"/*)
                if [ ! -d "$_ccsd_target_path" ]; then
                    _ccsd_stale_name="${_ccsd_existing##*/}"
                    rm -f "$_ccsd_existing" && ux_info "  removed stale skill: $_ccsd_stale_name"
                fi
                ;;
        esac
    done

    ux_success "  composed skills dir: $_ccsd_tgt (added=$_ccsd_added refreshed=$_ccsd_refreshed)"
}

# _claude_account_setup_one — 단일 계정의 link 멱등 셋업.
#
# skills/ 와 docs/ 는 SSOT 디렉토리 자체로의 단일 symlink 다 (issue #575).
# 이전의 per-skill symlink (`_claude_dir_sync_one`, #342) 와 bind-mount
# (#287) 는 모두 이 함수 하나로 대체됐고, 새 skill 은 setup 재실행 없이
# 즉시 반영된다.
_claude_account_setup_one() {
    # ${VAR:-} for set -u safety (gemini review on PR #590).
    _caso_acct="${1:-}"
    _caso_cdir="${2:-}"
    ux_section "Account: $_caso_acct ($_caso_cdir)"

    mkdir -p "$_caso_cdir"
    mkdir -p "$_caso_cdir/projects/GLOBAL"

    # settings.json is a real-file copy, NOT a symlink (#940) — Claude Code's
    # /model persists into this file, and a symlink would write through into
    # the tracked dotfiles SSOT (the #924 recurrence path).
    _claude_ensure_settings_copy "${DOTFILES_ROOT}/claude/settings.json"    "$_caso_cdir/settings.json"
    # settings.local.json is intentionally NOT symlinked from dotfiles (#584) —
    # it is a per-PC regular file the user hand-creates only when local env
    # overrides are needed. Claude Code merges it with settings.json natively.
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/statusline-command.sh"  "$_caso_cdir/statusline-command.sh"
    _claude_ensure_symlink "$HOME/.claude-shared/plugins"                   "$_caso_cdir/plugins"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/global-memory"          "$_caso_cdir/projects/GLOBAL/memory"
    # skills/ uses entry-level composition (issue #707, F-8) so a private
    # company-skills overlay can be layered into the same target dir
    # without touching the dotfiles git tree.
    _claude_compose_skills_dir "${DOTFILES_ROOT}/claude/skills"             "$_caso_cdir/skills"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/docs"                   "$_caso_cdir/docs"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/workflows"               "$_caso_cdir/workflows"
}

# _claude_status_show_oauth — append OAuth binding (email/org) to the
# Credentials line in claude_accounts_status (issue #300, item C).
#
# Visibility goal: the status command already says "✓ logged in" but does
# not say *which* Anthropic account those credentials map to. Without
# that, item-B's misbinding trap is invisible at diagnosis time. This
# helper jq-extracts the .oauthAccount fields populated by Claude after
# its first authenticated call, and prints two indented lines.
#
# Silent skip when: .claude.json missing, jq missing, or oauthAccount
# field absent (e.g. first-start placeholder before login completes).
# When item-B's expected mapping is also defined and disagrees with the
# observed email, append a ⚠️ marker to make the discrepancy obvious.
_claude_status_show_oauth() {
    _csso_dir="$1"
    _csso_acct="$2"
    _csso_json="$_csso_dir/.claude.json"

    [ -f "$_csso_json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Single jq invocation (was 3 separate forks — claude_accounts_status
    # iterates per account so the saving compounds). `|` delimiter chosen
    # because the gemini-suggested space form breaks on real-world
    # organizationName values that contain spaces (observed: "★ S.LSI AX
    # Agent ★"). POSIX heredoc — no bash process substitution.
    _csso_blob=$(jq -r '"\(.oauthAccount?.emailAddress? // "")|\(.oauthAccount?.organizationName? // "")|\(.oauthAccount?.organizationType? // "")"' "$_csso_json" 2>/dev/null)
    IFS='|' read -r _csso_email _csso_org _csso_type <<EOF
$_csso_blob
EOF
    [ -n "$_csso_email" ] || return 0

    _csso_marker=""
    _csso_expected=$(_claude_expected_email "$_csso_acct")
    if [ -n "$_csso_expected" ] && [ "$_csso_expected" != "$_csso_email" ]; then
        _csso_marker=" ⚠️  expected $_csso_expected"
    fi

    echo "    └─ Email: $_csso_email$_csso_marker"
    if [ -n "$_csso_org" ]; then
        if [ -n "$_csso_type" ]; then
            echo "    └─ Org:   $_csso_org ($_csso_type)"
        else
            echo "    └─ Org:   $_csso_org"
        fi
    fi
}

# claude_accounts_status — 진단 출력 (모든 ENABLED 계정의 상태).
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

    # zsh word-splitting parity
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cas_acct in $(_claude_resolve_account --list); do
        _cas_cdir=$(_claude_resolve_account "$_cas_acct")
        ux_section "Account: $_cas_acct"
        if [ -d "$_cas_cdir" ]; then
            echo "  Path:        $_cas_cdir ✓ exists"
        else
            echo "  Path:        $_cas_cdir ✗ missing"
        fi

        if [ -f "$_cas_cdir/.credentials.json" ]; then
            echo "  Credentials: .credentials.json ✓ logged in"
            _claude_status_show_oauth "$_cas_cdir" "$_cas_acct"
        else
            echo "  Credentials: .credentials.json ✗ NOT logged in"
            echo "                → Run: claude-yolo --user $_cas_acct"
        fi

        for _cas_link in settings.json settings.local.json statusline-command.sh plugins projects/GLOBAL/memory skills docs; do
            if [ "$_cas_link" = "settings.json" ]; then
                # settings.json is a real-file copy since #940 (was a
                # symlink) — a symlink here is the legacy write-through
                # layout that lets /model pollute the tracked SSOT (#924).
                if [ -L "$_cas_cdir/$_cas_link" ]; then
                    echo "  $_cas_link: symlink ✗ legacy layout (#940) — run: claude-accounts repair"
                elif [ -f "$_cas_cdir/$_cas_link" ]; then
                    echo "  $_cas_link: regular file ✓"
                else
                    echo "  $_cas_link: ✗ missing"
                fi
            elif [ -L "$_cas_cdir/$_cas_link" ] && [ ! -e "$_cas_cdir/$_cas_link" ]; then
                # Dangling symlink — e.g. settings.local.json left pointing
                # into a torn-down worktree (#940). Reporting it as
                # "symlink ✓" hid the breakage at diagnosis time.
                echo "  $_cas_link: broken symlink ✗ — target missing"
            elif [ -L "$_cas_cdir/$_cas_link" ]; then
                echo "  $_cas_link: symlink ✓"
            elif [ "$_cas_link" = "settings.local.json" ] && [ -f "$_cas_cdir/$_cas_link" ]; then
                # settings.local.json is a per-PC hand-created regular
                # file (#584), never a symlink — report it as present
                # rather than missing (gemini review on PR #590).
                echo "  $_cas_link: regular file ✓"
            else
                echo "  $_cas_link: ✗ missing"
            fi
        done
        echo ""
    done
}

# _claude_has_unmigrated_data — SSOT for "user has legacy ~/.claude data
# that must be migrated before setup". Used by claude_accounts_init AND
# claude/setup.sh — keeping the sentinel list in one place.
# Returns 0 (true) if migration is needed, 1 (false) otherwise.
# Tolerates empty bind-mount leftovers (skills/, docs/) — those are not
# user data, just unmounted dirs from the legacy layout.
#
# Migration-done check iterates CLAUDE_ENABLED_ACCOUNTS (issue #568) so
# adding work1 / work-eng / etc. via env doesn't need a code edit here.
_claude_has_unmigrated_data() {
    [ -d "$HOME/.claude" ] || return 1

    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi
    # ${VAR:-} for set -u safety (gemini review on PR #569).
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _chud_acct in ${CLAUDE_ENABLED_ACCOUNTS:-}; do
        [ -d "$HOME/.claude-$_chud_acct" ] && return 1
    done

    [ -e "$HOME/.claude/.credentials.json" ] && return 0
    [ -d "$HOME/.claude/projects" ] && return 0
    [ -d "$HOME/.claude/sessions" ] && return 0
    [ -e "$HOME/.claude/history.jsonl" ] && return 0
    [ -d "$HOME/.claude/plugins" ] && return 0
    return 1
}

# claude_accounts_init — 멱등 setup, 3대 PC 공통 진입점.
claude_accounts_init() {
    ux_header "Claude Accounts Setup"

    # Unmigrated guard runs BEFORE any mkdir, so a stale ~/.claude/ from
    # another tool can't be silently obscured by guard-dir creation.
    if _claude_has_unmigrated_data; then
        ux_warning "$HOME/.claude/ 에 기존 사용자 데이터가 있습니다."
        ux_info    "먼저 마이그레이션을 실행하세요: claude-accounts migrate"
        return 1
    fi

    mkdir -p "$HOME/.claude-shared/plugins"
    mkdir -p "$HOME/.claude"

    # zsh word-splitting parity (same reason as _claude_resolve_account)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cai_acct in $(_claude_resolve_account --list); do
        _cai_cdir=$(_claude_resolve_account "$_cai_acct")
        _claude_account_setup_one "$_cai_acct" "$_cai_cdir"
    done

    ux_success "All accounts ready"
}

# claude_accounts_migrate — 1회 마이그레이션 (Home-PC 등 기존 데이터
# 보유 PC 한정). 멱등: 이미 마이그됐으면 즉시 skip.
claude_accounts_migrate() {
    if [ -d "$HOME/.claude-personal" ]; then
        ux_info "Already migrated to ~/.claude-personal — skipping"
        return 0
    fi

    if [ ! -d "$HOME/.claude" ]; then
        ux_info "$HOME/.claude not found — nothing to migrate. Run: claude-accounts setup"
        return 0
    fi

    # Diagnostic: capture .claude.json size BEFORE the mv (issue #294).
    # If the file is already in the "first-start placeholder" state at this
    # point, the regression is upstream of migrate (bad shutdown, prior
    # corruption) — and the post-mv size check below will match.
    _cam_pre_size=""
    if [ -f "$HOME/.claude/.claude.json" ]; then
        _cam_pre_size=$(wc -c < "$HOME/.claude/.claude.json" 2>/dev/null | tr -d ' ')
        ux_info "Pre-migrate ~/.claude/.claude.json size: ${_cam_pre_size:-?} bytes"
        if [ -n "$_cam_pre_size" ] && [ "$_cam_pre_size" -lt 500 ]; then
            ux_warning "  .claude.json is suspiciously small (< 500B) — already in"
            ux_warning "  first-start placeholder state. Migration will preserve it"
            ux_warning "  as-is, but you may need to re-login on first use."
        fi
    else
        # Issue #500, F-3: pre-migrate .claude.json missing means we cannot
        # seal a snapshot, so _claude_restore_if_reset cannot auto-recover
        # later. Surface that fact up front so the user knows a manual
        # re-login may be required after the first claude-yolo run.
        # English wording + ux_info for the explanatory follow-up matches
        # the surrounding _cam_pre_size block (PR #503 review).
        ux_warning "Pre-migrate ~/.claude/.claude.json missing — sealed snapshot not created"
        ux_info    "  Automatic restoration will be unavailable if .claude.json is reset"
        ux_info    "  (manual re-login required: re-run claude-yolo after first login)"
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

    # Diagnostic + safety net (issue #294): verify post-mv size matches and
    # seal a snapshot so claude_yolo can recover if .claude.json is later
    # reset (Claude CLI's first-run-with-new-CLAUDE_CONFIG_DIR can wipe it
    # to a `firstStartTime`-only stub, which kills oauthAccount/migration
    # cache and triggers a "configuration file not found" prompt).
    if [ -f "$HOME/.claude-personal/.claude.json" ]; then
        _cam_post_size=$(wc -c < "$HOME/.claude-personal/.claude.json" 2>/dev/null | tr -d ' ')
        ux_info "Post-migrate ~/.claude-personal/.claude.json size: ${_cam_post_size:-?} bytes"
        if [ -n "$_cam_pre_size" ] && [ -n "$_cam_post_size" ] \
           && [ "$_cam_pre_size" != "$_cam_post_size" ]; then
            ux_warning "  Size mismatch (pre=${_cam_pre_size}, post=${_cam_post_size}) —"
            ux_warning "  another process modified .claude.json during migrate."
        fi
        _cam_snap="$HOME/.claude-personal/.claude.json.preserved-by-migrate"
        if cp "$HOME/.claude-personal/.claude.json" "$_cam_snap" 2>/dev/null; then
            ux_info "Sealed snapshot: $_cam_snap"
            ux_info "  (claude-yolo auto-restores from this if .claude.json gets reset)"
        else
            ux_error "  Failed to create snapshot: $_cam_snap (recovery will be unavailable)"
        fi
    fi

    # 4) 빈 ~/.claude 재생성 + 모든 계정 init (멱등)
    claude_accounts_init

    ux_success "Migration complete. Personal data preserved at ~/.claude-personal/"
}

# claude_accounts_rollback — multi-account → single ~/.claude/ (issue #571).
#
# Reverse of `claude_accounts_migrate`. Promotes one account's directory
# back to ~/.claude/ and timestamp-backs-up the rest. Idempotent — when
# there are no ~/.claude-* dirs to roll back, it returns success without
# touching anything.
#
# Usage:
#   claude-accounts rollback             # auto-detect active account
#   claude-accounts rollback personal    # force-promote a specific account
#
# Auto-detect order:
#   1. The account whose .credentials.json exists (signals "logged in").
#   2. First existing ~/.claude-<name> dir among ENABLED_ACCOUNTS.
#
# Side effects:
#   - mv ~/.claude-<active>      → ~/.claude
#   - mv ~/.claude-<other>       → ~/.claude-<other>-rollback-<TS>-original
#   - mv ~/.claude (if non-empty)→ ~/.claude-pre-rollback-<TS>-original
#
# The Samsung internal PC use-case driving #571: a user ran
# `claude-accounts migrate` by mistake on an internal box (where the
# multi-account layout is structurally wrong), then `claude-yolo`
# hard-failed on the missing ~/.claude-personal check. Rollback gives
# them a one-shot recovery path without manual `mv`/`rm -rf`.
claude_accounts_rollback() {
    _car_active="${1:-}"

    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    # Auto-detect the active account when not passed explicitly.
    if [ -z "$_car_active" ]; then
        # First pass: prefer the account that's logged in.
        # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
        for _car_cand in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
            if [ -f "$HOME/.claude-${_car_cand}/.credentials.json" ]; then
                _car_active="$_car_cand"
                break
            fi
        done
        # Fallback: any existing ~/.claude-<name> dir.
        if [ -z "$_car_active" ]; then
            # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
            for _car_cand in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
                if [ -d "$HOME/.claude-${_car_cand}" ]; then
                    _car_active="$_car_cand"
                    break
                fi
            done
        fi
    fi

    ux_header "claude-accounts rollback — multi-account → single ~/.claude/"

    if [ -z "$_car_active" ]; then
        ux_info "No ~/.claude-* dirs to roll back — nothing to do (idempotent)"
        return 0
    fi

    _car_src="$HOME/.claude-${_car_active}"
    if [ ! -d "$_car_src" ]; then
        ux_error "Active account dir missing: $_car_src"
        ux_info  "Available: $(ls -d "$HOME"/.claude-* 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    ux_info "Active account:  $_car_active ($_car_src)"
    if [ "$(_dotfiles_setup_mode)" != "internal" ]; then
        # SC2088: the tilde here is a literal `~` in a user-facing path,
        # not a shell expansion — display form deliberately.
        # shellcheck disable=SC2088
        ux_warning "~/.dotfiles-setup-mode is not 'internal' — rollback is intended for"
        ux_warning "  the internal-PC single-account flow. Continuing anyway."
    fi

    _car_ts=$(date +%Y%m%d%H%M%S)

    # Step 1: Move out any existing ~/.claude/ contents.
    # Empty guard dirs (the kind setup.sh creates) → just rmdir, no backup.
    # Non-empty real dirs → timestamped backup (no auto-delete — user owns).
    # Symlinks → remove (they only point at SSOT, no data loss).
    if [ -L "$HOME/.claude" ]; then
        rm -f "$HOME/.claude"
        ux_info "  removed legacy ~/.claude symlink"
    elif [ -d "$HOME/.claude" ]; then
        if [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
            rmdir "$HOME/.claude" 2>/dev/null && \
                ux_info "  removed empty guard dir: ~/.claude"
        else
            _car_pre="$HOME/.claude-pre-rollback-${_car_ts}-original"
            mv "$HOME/.claude" "$_car_pre" || {
                ux_error "  backup failed: ~/.claude → $_car_pre — abort"
                return 1
            }
            ux_warning "  backed up existing ~/.claude → $_car_pre"
        fi
    fi

    # Step 2: Promote the active account's data to ~/.claude/.
    mv "$_car_src" "$HOME/.claude" || {
        ux_error "Move failed: $_car_src → ~/.claude"
        return 1
    }
    ux_success "  ~/.claude-${_car_active} → ~/.claude"

    # Step 3: Timestamp-backup every other ENABLED account that still has
    # a dir. Plugins are *not* moved — they live in ~/.claude-shared and
    # the active account already symlinks to that location.
    # shellcheck disable=SC2086  # intentional word-split for POSIX list iteration
    for _car_other in ${CLAUDE_ENABLED_ACCOUNTS:-personal work}; do
        [ "$_car_other" = "$_car_active" ] && continue
        _car_other_src="$HOME/.claude-${_car_other}"
        if [ -d "$_car_other_src" ]; then
            _car_other_bak="$HOME/.claude-${_car_other}-rollback-${_car_ts}-original"
            if mv "$_car_other_src" "$_car_other_bak"; then
                ux_info "  backed up: $_car_other_src → $_car_other_bak"
            else
                ux_warning "  backup failed for $_car_other_src — leaving in place"
            fi
        fi
    done

    ux_success "Rollback complete. ~/.claude/ is now the single config dir."
    ux_info "Next steps:"
    ux_info "  1. ./setup.sh   (re-select '2) Internal company PC' to wire single-account symlinks)"
    ux_info "  2. exec zsh     (reload shell)"
    ux_info "  3. claude-yolo  (no --user flag; multi-account dispatch is bypassed)"
}

# claude_accounts_repair — one-shot cleanup for worktree-tainted symlinks
# (issue #589, Option C).
#
# Walks every ~/.claude-* directory and ~/.claude/ and rebinds symlinks
# whose target either (a) dangles or (b) lives outside the canonical
# DOTFILES_ROOT/claude/ subtree, to the equivalent path under the
# canonical root. Idempotent — clean PCs see "nothing to repair".
#
# Why this exists in addition to the loader/setup canonicalization: those
# guards prevent FUTURE breakage. Pre-existing PCs that already ran
# setup from a (now-deleted) worktree carry dangling symlinks today;
# `claude_accounts_repair` is the explicit recovery command.
#
# Scope: only touches symlinks whose name matches the well-known set
# created by `_claude_account_setup_one`:
#   settings.json, statusline-command.sh, skills, docs,
#   projects/GLOBAL/memory
# `plugins` is intentionally excluded — it points at ~/.claude-shared/
# (not DOTFILES_ROOT), so the worktree-bleed regression cannot reach it.
#
# Usage:
#   claude-accounts repair          # actually fix
#   claude-accounts repair --dry-run  # report only, no mutation
claude_accounts_repair() {
    _car_dry=0
    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        _car_dry=1
    fi

    ux_header "claude-accounts repair — rebind worktree-tainted symlinks (issue #589)"

    if [ -z "${DOTFILES_ROOT:-}" ]; then
        ux_error "DOTFILES_ROOT unset — re-source ~/.bashrc / ~/.zshrc first"
        return 1
    fi

    _car_root="$DOTFILES_ROOT"
    _car_claude_src="${_car_root}/claude"
    if [ ! -d "$_car_claude_src" ]; then
        ux_error "Canonical claude dir missing: $_car_claude_src"
        ux_info  "  Run ./setup.sh from the main worktree first."
        return 1
    fi

    ux_info "Canonical DOTFILES_ROOT: $_car_root"
    if [ "$_car_dry" = "1" ]; then
        ux_info "Mode: dry-run (no files will be modified)"
    fi

    # Account dirs to scan: ~/.claude/ + every ~/.claude-* directory.
    _car_repaired=0
    _car_skipped=0

    for _car_dir in "$HOME/.claude" "$HOME"/.claude-*; do
        [ -d "$_car_dir" ] || continue
        # Glob fallthrough on systems with no ~/.claude-* dirs at all
        # (the literal pattern survives) — skip it.
        case "$_car_dir" in
            "$HOME/.claude-"\*) continue ;;
        esac

        # Each (relative_path, canonical_source) pair.
        # POSIX sh has no arrays; use a here-doc-driven loop instead.
        while IFS='|' read -r _car_rel _car_canon; do
            [ -n "$_car_rel" ] || continue
            _car_link="${_car_dir}/${_car_rel}"

            # Only touch symlinks; regular files / dirs are user data.
            [ -L "$_car_link" ] || continue

            _car_target=$(readlink "$_car_link" 2>/dev/null || true)

            # settings.json must be a real-file copy since #940 — ANY
            # symlink here (canonical or tainted) is the legacy
            # write-through layout that lets /model pollute the tracked
            # SSOT (#924). Convert instead of rebinding.
            if [ "$_car_rel" = "settings.json" ]; then
                ux_warning "  convert to real file (#940): $_car_link"
                ux_info    "    from symlink: $_car_target"
                ux_info    "    copy of:      $_car_canon"
                if [ "$_car_dry" = "0" ]; then
                    if rm -f "$_car_link" && cp "$_car_canon" "$_car_link"; then
                        chmod 600 "$_car_link"
                        _car_repaired=$((_car_repaired + 1))
                    else
                        ux_error "    convert failed — manual recovery needed"
                    fi
                else
                    _car_repaired=$((_car_repaired + 1))
                fi
                continue
            fi

            _car_needs_fix=0

            # Case 1: dangling — readlink target does not resolve.
            if [ ! -e "$_car_link" ]; then
                _car_needs_fix=1
            fi
            # Case 2: target points outside the canonical claude subtree.
            #         (caught even when the worktree path happens to still
            #         exist, e.g. user hasn't deleted it yet)
            case "$_car_target" in
                "$_car_canon") : ;;                          # already canonical
                "${_car_root}/claude/"*) : ;;                # canonical subtree
                *) _car_needs_fix=1 ;;
            esac

            if [ "$_car_needs_fix" = "0" ]; then
                _car_skipped=$((_car_skipped + 1))
                continue
            fi

            ux_warning "  rebind: $_car_link"
            ux_info    "    from: $_car_target"
            ux_info    "    to:   $_car_canon"
            if [ "$_car_dry" = "0" ]; then
                rm -f "$_car_link" || {
                    ux_error "    rm failed — skipping"
                    continue
                }
                mkdir -p "$(dirname "$_car_link")"
                if ln -s "$_car_canon" "$_car_link"; then
                    _car_repaired=$((_car_repaired + 1))
                else
                    ux_error "    ln -s failed — symlink missing now, manual recovery needed"
                fi
            else
                _car_repaired=$((_car_repaired + 1))
            fi
        done <<EOF
settings.json|${_car_claude_src}/settings.json
statusline-command.sh|${_car_claude_src}/statusline-command.sh
skills|${_car_claude_src}/skills
docs|${_car_claude_src}/docs
projects/GLOBAL/memory|${_car_claude_src}/global-memory
EOF
    done

    if [ "$_car_dry" = "1" ]; then
        ux_info "Dry-run summary: would repair $_car_repaired symlink(s); $_car_skipped already canonical."
        ux_info "Run without --dry-run to apply."
    else
        ux_success "Repair complete: $_car_repaired rebound, $_car_skipped already canonical."
    fi
}

_claude_accounts_help() {
    ux_header "claude-accounts — Claude Code multi-account management"
    ux_info "Usage: claude-accounts [<subcommand>]"
    ux_info ""
    ux_info "Subcommands:"
    ux_info "  status        (default) Show all accounts: path/credentials/symlinks"
    ux_info "  list          List enabled accounts"
    ux_info "  setup         Idempotent setup (creates dirs + symlinks)"
    ux_info "  migrate       One-time migration: ~/.claude → ~/.claude-personal (Home-PC)"
    ux_info "  rollback [<acct>]  Reverse of migrate: ~/.claude-<acct> → ~/.claude (issue #571)"
    ux_info "  repair [--dry-run] Rebind dangling/worktree-tainted symlinks (issue #589)"
    ux_info "  -h|--help     This help"
    ux_info ""
    ux_info "Env vars:"
    ux_info "  CLAUDE_DEFAULT_ACCOUNT     Default for \`claude-yolo\` (default: personal)"
    ux_info "  CLAUDE_ENABLED_ACCOUNTS    Whitelist (default: 'personal work')"
    ux_info "  DOTFILES_ROOT_NO_CANONICALIZE=1  Skip worktree canonicalization (issue #589 escape hatch)"
    ux_info "  Override per-PC in shell-common/env/claude.local.sh"
}

claude_accounts() {
    case "${1:-status}" in
        status)         claude_accounts_status ;;
        list)           _claude_resolve_account --list ;;
        setup)          claude_accounts_init ;;
        migrate)        claude_accounts_migrate ;;
        rollback)       shift; claude_accounts_rollback "$@" ;;
        repair)         shift; claude_accounts_repair "$@" ;;
        -h|--help|help) _claude_accounts_help ;;
        *)              ux_error "Unknown subcommand: $1"; _claude_accounts_help; return 1 ;;
    esac
}
alias claude-accounts='claude_accounts'

# _claude_yolo_register_aliases — ENABLED 계정마다 단축 alias 자동 생성.
# 매핑 SSOT (_claude_resolve_account --list) 한 곳에서 파생되므로
# 새 계정 추가 시 alias 도 자동 등장. 수동 alias 정의 금지.
_claude_yolo_register_aliases() {
    # zsh word-splitting parity (same reason as other --list consumers)
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    for _cyra_acct in $(_claude_resolve_account --list); do
        # POSIX-safe: alias 동적 생성 (eval 필요)
        # shellcheck disable=SC2139  # alias contains expanded value (intentional)
        eval "alias claude-yolo-${_cyra_acct}='claude_yolo --user ${_cyra_acct}'"
    done
}

# claude.sh 로드 시 1회 자동 호출
_claude_yolo_register_aliases
