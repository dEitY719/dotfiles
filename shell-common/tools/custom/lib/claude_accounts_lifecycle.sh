#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/claude_accounts_lifecycle.sh
# Claude Code account provisioning + lifecycle: status / setup (init) /
# migrate / rollback / repair, and the per-account link/settings helpers they
# share (moved out of tools/integrations/claude.sh, #2146).
#
# Source-only, no interactive guard: consumed by tools/custom/claude_accounts.sh
# (the `claude-accounts` command), by claude/setup.sh directly, and lazily by
# the thin wrappers in tools/integrations/claude.sh. Function definitions only.
#
# Needs: ux_lib, claude_accounts_auth.sh (sourced below when missing),
# functions/mount.sh (_is_mounted) and functions/skill_sources.sh for the
# skills helpers in claude_accounts_skills.sh.

if ! command -v _claude_resolve_account >/dev/null 2>&1; then
    # shellcheck source=claude_accounts_auth.sh
    . "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/lib/claude_accounts_auth.sh"
fi

# _claude_backup_original <target> <label> — latest-only backup (#806, #2130).
# Moves <target> to "<target>${DOTFILES_ORIGINAL_SUFFIX}" via the SSOT helper
# in shell-common/functions/dotfiles_backup.sh, so repeated init/repair runs
# keep at most ONE backup per target instead of accumulating timestamped
# copies. A prior FILE backup at that path is replaced (one warning line names
# it). A prior non-empty DIRECTORY backup is never replaced: it can be the only
# copy of user data (e.g. a pre-bind-mount skills dir), so the call fails with
# a manual-cleanup hint instead of `rm -rf`-ing it.
# Legacy `<target>-YYYYmmddHHMMSS-original` files are never auto-deleted —
# removing user files stays a manual decision.
_claude_backup_original() {
    _cbo_tgt="$1"
    _cbo_label="${2:-existing file}"
    if ! command -v dotfiles_backup_move >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        . "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/functions/dotfiles_backup.sh" || return 1
    fi
    # Never pass an empty suffix: the helper would fall back to
    # DOTFILES_BACKUP_SUFFIX, and if that is empty too dest == target and its
    # `rm -rf <dest>` would delete the very data being backed up.
    _cbo_suffix="${DOTFILES_ORIGINAL_SUFFIX:-.original}"
    _cbo_dest=$(dotfiles_backup_path "$_cbo_tgt" "$_cbo_suffix")
    if [ -d "$_cbo_dest" ] && [ ! -L "$_cbo_dest" ] \
        && [ -n "$(ls -A "$_cbo_dest" 2>/dev/null)" ]; then
        ux_error "  previous backup directory holds data — not overwriting: $_cbo_dest"
        ux_info "  inspect/move it manually, then re-run: $_cbo_tgt is left in place"
        return 1
    elif [ -e "$_cbo_dest" ] || [ -L "$_cbo_dest" ]; then
        ux_warning "  replacing previous backup (latest-only, #806): $_cbo_dest"
    fi
    ux_warning "  backing up $_cbo_label: $_cbo_tgt → $_cbo_dest"
    dotfiles_backup_move "$_cbo_tgt" "$_cbo_suffix" >/dev/null || {
        ux_error "  backup failed: $_cbo_tgt → $_cbo_dest"
        return 1
    }
}

# _claude_ensure_symlink — 멱등 symlink 생성. Thin wrapper over
# dotfiles_ensure_link (#2138); the name stays because external skill repos
# and docs reference it.
# - 없음 → 생성 / 같은 target 의 symlink → silent no-op
# - bind-mount → sudo umount 후 재생성 (issue #575 마이그레이션 경로)
# - 다른 file/dir → 고정 suffix(.original) 백업 후 재생성 (#806); 백업이 이미
#   있으면 덮어쓰지 않고 target 을 그대로 둔 채 경고
_claude_ensure_symlink() {
    _claude_link_lib || return 1
    dotfiles_ensure_link "$1" "$2" --allow-dir --unmount-legacy
}

# _claude_link_lib — load lib/setup/link.sh on first use, so interactive
# shell startup does not pay for it (#2138). The lib's log_* shims are meant
# for setup scripts (log_error_and_exit exits), so any it adds are removed
# again to keep them out of the user's interactive shell.
_claude_link_lib() {
    command -v dotfiles_ensure_link >/dev/null 2>&1 && return 0
    _clkl_sc="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    _clkl_new=""
    for _clkl_f in log_info log_warning log_error log_error_and_exit; do
        command -v "$_clkl_f" >/dev/null 2>&1 || _clkl_new="$_clkl_new $_clkl_f "
    done
    SHELL_COMMON="$_clkl_sc" . "$_clkl_sc/lib/setup/link.sh" || return 1
    for _clkl_f in log_info log_warning log_error log_error_and_exit; do
        case "$_clkl_new" in *" $_clkl_f "*) unset -f "$_clkl_f" ;; esac
    done
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    _cesc_src="$1"
    _cesc_tgt="$2"
    _cesc_local="$(dirname "$_cesc_tgt")/settings.local.json"
    _cesc_srctmp=
    _cesc_merged=

    # 방어: SSOT (claude/settings.json) 에 model 키가 새어들면 — 배포 지연 틈에
    # 남은 pre-#940 write-through symlink 로 /model 이 추적 파일을 오염시킨
    # 경우 — 모든 계정 복사본이 그 키를 물려받고, live 복사본이 SSOT 와 바이트
    # 동일해져 아래 cmp 게이트의 model 이주가 영구 skip 된다(자가치유 불능).
    # 복사 source 를 sanitize 해 오염 전파를 끊고 추적 파일 청소를 안내한다.
    # 추적 SSOT 자체는 건드리지 않는다 — setup 이 tracked 파일에 쓰는 것이 바로
    # #924 안티패턴. 영구 커밋 가드는 golden rule 6 이 담당.
    if command -v jq >/dev/null 2>&1 \
        && [ -n "$(jq -r '.model // empty' "$_cesc_src" 2>/dev/null)" ]; then
        ux_warning "  SSOT 에 model 키 오염: $_cesc_src — 복구: git checkout claude/settings.json"
        _cesc_srctmp=$(mktemp "${TMPDIR:-/tmp}/claude_ssot.XXXXXX" 2>/dev/null) || _cesc_srctmp=
        if [ -n "$_cesc_srctmp" ] && jq 'del(.model)' "$_cesc_src" > "$_cesc_srctmp" 2>/dev/null; then
            _cesc_src="$_cesc_srctmp"
        else
            [ -n "$_cesc_srctmp" ] && rm -f "$_cesc_srctmp"
            _cesc_srctmp=
        fi
    fi

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
        if rm "$_cesc_tgt"; then
            ux_info "  legacy settings.json symlink → real file (#940): $_cesc_tgt"
            # 백업 불필요 사유를 한 줄 보강 (#997): symlink 제거이므로 잃을
            # 데이터가 없다(실체는 dotfiles SSOT 에 보존). /model 이 남긴 개인
            # 키는 아래 elif 실파일 분기에서 settings.local.json 으로 이주된다.
            ux_info "    (symlink 였으므로 백업 불필요 — SSOT 보존)"
        fi
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
                    # 변경 요약 집계 (#1101). setup.sh 최상위 셸에서 sourced 되어
                    # SETUP_MIGRATIONS 를 공유하지만, interactive 소싱 등 변수가
                    # 미정의인 컨텍스트도 있으므로 ${VAR:-0} 로 set -u 안전 처리.
                    SETUP_MIGRATIONS=$((${SETUP_MIGRATIONS:-0} + 1))
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
                        # 변경 요약 집계 (#1101) — set -u 안전. 위 분기와 동일.
                        SETUP_MIGRATIONS=$((${SETUP_MIGRATIONS:-0} + 1))
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

    # 로컬 전용 enabledPlugins 보존 (#1070) — `claude plugin install/enable`
    # 은 활성 계정 실파일의 enabledPlugins 에 직접 기록한다. SSOT 를 그대로
    # 복사하면 SSOT 에 커밋되지 않은 로컬 전용 항목이 매 setup 재실행마다
    # 조용히 disabled 로 리셋된다. 병합으로 해결: SSOT 값이 충돌 키에서 우선
    # 하되(오른쪽 우선인 jq `+`), 로컬 전용 키는 보존한다. jq 없거나 로컬 전용
    # 항목이 없으면 무동작 — 흔한 경우의 완전 멱등성(아래 cmp 게이트)을 유지.
    if command -v jq >/dev/null 2>&1 && [ -f "$_cesc_tgt" ]; then
        _cesc_extra=$(jq -n \
            --slurpfile ssot "$_cesc_src" \
            --slurpfile cur "$_cesc_tgt" \
            '(($cur[0].enabledPlugins // {}) | keys) - (($ssot[0].enabledPlugins // {}) | keys) | length' \
            2>/dev/null)
        if [ -n "$_cesc_extra" ] && [ "$_cesc_extra" -gt 0 ] 2>/dev/null; then
            _cesc_merged=$(mktemp "${TMPDIR:-/tmp}/claude_ep_merge.XXXXXX" 2>/dev/null) || _cesc_merged=
            if [ -n "$_cesc_merged" ] && jq -n \
                --slurpfile ssot "$_cesc_src" \
                --slurpfile cur "$_cesc_tgt" \
                '$ssot[0] | .enabledPlugins = (($cur[0].enabledPlugins // {}) + ($ssot[0].enabledPlugins // {}))' \
                > "$_cesc_merged" 2>/dev/null; then
                _cesc_src="$_cesc_merged"
                ux_info "  preserved $_cesc_extra local-only enabledPlugins entry/entries (#1070)"
            else
                [ -n "$_cesc_merged" ] && rm -f "$_cesc_merged"
                _cesc_merged=
            fi
        fi
    fi

    # 단일 cleanup/return — sanitize 임시파일 정리를 세 경로에 중복하지 않고
    # 함수 말미에서 한 번만 수행 (PR #1000 gemini-code-assist 제안).
    _cesc_ret=0
    if [ -f "$_cesc_tgt" ] && cmp -s "$_cesc_src" "$_cesc_tgt"; then
        ux_info "  ✓ settings.json up to date (real file): $_cesc_tgt"
    elif ! cp "$_cesc_src" "$_cesc_tgt"; then
        ux_error "  settings.json copy failed: $_cesc_src → $_cesc_tgt"
        _cesc_ret=1
    else
        chmod 600 "$_cesc_tgt"
        ux_success "  installed settings.json (real file): $_cesc_tgt"
    fi

    [ -n "$_cesc_srctmp" ] && rm -f "$_cesc_srctmp"
    [ -n "$_cesc_merged" ] && rm -f "$_cesc_merged"
    return $_cesc_ret
}

# _claude_install_herdr_hook <config-dir> — herdr 상태 훅 스크립트를 계정 디렉터리에 설치.
# SSOT claude/settings.json 의 SessionStart 훅이 ${CLAUDE_CONFIG_DIR}/hooks/
# herdr-agent-state.sh 를 호출하므로 스크립트 파일이 있어야 한다. 파일은 herdr 가
# 만든다 (`herdr integration install claude`) — dotfiles 가 배포하지 않는다.
# 멱등: 스크립트가 이미 있거나 herdr 가 PATH 에 없으면 아무것도 안 한다. soft-fail.
# herdr 가 settings.json 에 덧붙이는 훅 항목은 외부 PC 에서는 뒤따르는
# _claude_ensure_settings_copy 가 SSOT 로 덮어써 정리한다 — 호출 순서 유지할 것.
_claude_install_herdr_hook() {
    _cih_dir="${1:-}"
    [ -n "$_cih_dir" ] || return 0
    command -v herdr >/dev/null 2>&1 || return 0
    [ -x "$_cih_dir/hooks/herdr-agent-state.sh" ] && return 0
    mkdir -p "$_cih_dir"
    if CLAUDE_CONFIG_DIR="$_cih_dir" herdr integration install claude >/dev/null 2>&1; then
        ux_success "  herdr hook installed: $_cih_dir/hooks/herdr-agent-state.sh"
    else
        ux_warning "  herdr integration install 실패 — 수동: CLAUDE_CONFIG_DIR=$_cih_dir herdr integration install claude"
    fi
    return 0
}

# _claude_account_setup_one — 단일 계정의 link 멱등 셋업.
#
# skills/ 와 docs/ 는 SSOT 디렉토리 자체로의 단일 symlink 다 (issue #575).
# 이전의 per-skill symlink (`_claude_dir_sync_one`, #342) 와 bind-mount
# (#287) 는 모두 이 함수 하나로 대체됐고, 새 skill 은 setup 재실행 없이
# 즉시 반영된다.
_claude_account_setup_one() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # ${VAR:-} for set -u safety (gemini review on PR #590).
    _caso_acct="${1:-}"
    _caso_cdir="${2:-}"
    ux_section "Account: $_caso_acct ($_caso_cdir)"

    mkdir -p "$_caso_cdir"
    mkdir -p "$_caso_cdir/projects/GLOBAL"

    # Must precede _claude_ensure_settings_copy (it overwrites herdr's settings edit).
    _claude_install_herdr_hook "$_caso_cdir"

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
    # skills/ 는 실디렉토리 (issue #707, F-8) 로 유지하되 워크스페이스 스킬은
    # 합성하지 않는다 — Claude Code 는 그것들을 플러그인(claude/plugin/
    # plugins.json, restore.sh 설치)으로 로드하고, flat 링크는 네임스페이스
    # 없는 중복 명령이 된다. 예전 합성이 남긴 워크스페이스 링크만 정리한다.
    # 외부에서 추가된 symlink(`claude-accounts link`, graphify 등)는 유지.
    _claude_prune_workspace_skills "$_caso_cdir/skills"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/docs"                   "$_caso_cdir/docs"
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/workflows"               "$_caso_cdir/workflows"
    # Global instructions (Advisor/Worker) — SSOT symlink, all projects (#1115).
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/CLAUDE.md"              "$_caso_cdir/CLAUDE.md"
    # Keybindings — Claude Code hot-reloads it; ctrl+j is bound to
    # chat:sendNow because terminals send LF for Ctrl+Enter.
    _claude_ensure_symlink "${DOTFILES_ROOT}/claude/keybindings.json"       "$_caso_cdir/keybindings.json"
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

    ux_bullet_sub "Email: $_csso_email$_csso_marker"
    if [ -n "$_csso_org" ]; then
        if [ -n "$_csso_type" ]; then
            ux_bullet_sub "Org:   $_csso_org ($_csso_type)"
        else
            ux_bullet_sub "Org:   $_csso_org"
        fi
    fi
}

# claude_accounts_status — 진단 출력 (모든 ENABLED 계정의 상태).
claude_accounts_status() {
    ux_header "Claude Accounts Status"
    # internal PC: single account at ~/.claude, claude-accounts unused (#571),
    # so inspect that dir instead of the multi-account ~/.claude-<name> set (#2116).
    _cas_internal=0
    if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
        _cas_internal=1
        ux_info "internal mode — single-account (~/.claude), claude-accounts 미사용"
    else
        ux_info "Default: $CLAUDE_DEFAULT_ACCOUNT"
        ux_info "Enabled: $CLAUDE_ENABLED_ACCOUNTS"
        if [ -d "$HOME/.claude-shared/plugins" ]; then
            ux_info "Shared:  $HOME/.claude-shared/plugins ✓"
        else
            ux_warning "Shared:  $HOME/.claude-shared/plugins ✗ missing"
        fi
    fi
    ux_info ""

    # zsh word-splitting parity
    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi

    if [ "$_cas_internal" = "1" ]; then
        _cas_accts="internal"
    else
        _cas_accts=$(_claude_resolve_account --list)
    fi
    for _cas_acct in $_cas_accts; do
        if [ "$_cas_internal" = "1" ]; then
            _cas_cdir="$HOME/.claude"
        else
            _cas_cdir=$(_claude_resolve_account "$_cas_acct")
        fi
        ux_section "Account: $_cas_acct"
        if [ -d "$_cas_cdir" ]; then
            ux_bullet "Path:        $_cas_cdir ✓ exists"
        else
            ux_bullet "Path:        $_cas_cdir ✗ missing"
        fi

        case "$(_claude_account_auth_kind "$_cas_cdir")" in
            oauth)
                ux_bullet "Credentials: OAuth (.credentials.json) ✓ logged in"
                _claude_status_show_oauth "$_cas_cdir" "$_cas_acct"
                ;;
            apiKeyHelper)
                ux_bullet "Credentials: apiKeyHelper ✓ configured"
                ;;
            apikey)
                ux_bullet "Credentials: ANTHROPIC_API_KEY ✓ set"
                ;;
            *)
                if [ "$_cas_internal" = "1" ]; then
                    ux_bullet "Credentials: none ✗ (apiKeyHelper / ANTHROPIC_API_KEY not set)"
                else
                    ux_bullet "Credentials: .credentials.json ✗ NOT logged in"
                    ux_bullet_sub "Run: claude-yolo --user $_cas_acct"
                fi
                ;;
        esac

        for _cas_link in settings.json settings.local.json statusline-command.sh plugins projects/GLOBAL/memory skills docs workflows CLAUDE.md keybindings.json; do
            if [ "$_cas_link" = "settings.json" ]; then
                # settings.json is a real-file copy since #940 (was a
                # symlink) — a symlink here is the legacy write-through
                # layout that lets /model pollute the tracked SSOT (#924).
                if [ -L "$_cas_cdir/$_cas_link" ]; then
                    ux_bullet "$_cas_link: symlink ✗ legacy layout (#940) — run: claude-accounts repair"
                elif [ -f "$_cas_cdir/$_cas_link" ]; then
                    ux_bullet "$_cas_link: regular file ✓"
                else
                    ux_bullet "$_cas_link: ✗ missing"
                fi
            elif [ -L "$_cas_cdir/$_cas_link" ] && [ ! -e "$_cas_cdir/$_cas_link" ]; then
                # Dangling symlink — e.g. settings.local.json left pointing
                # into a torn-down worktree (#940). Reporting it as
                # "symlink ✓" hid the breakage at diagnosis time.
                ux_bullet "$_cas_link: broken symlink ✗ — target missing"
            elif [ -L "$_cas_cdir/$_cas_link" ]; then
                ux_bullet "$_cas_link: symlink ✓"
            elif [ "$_cas_link" = "settings.local.json" ] && [ -f "$_cas_cdir/$_cas_link" ]; then
                # settings.local.json is a per-PC hand-created regular
                # file (#584), never a symlink — report it as present
                # rather than missing (gemini review on PR #590).
                ux_bullet "$_cas_link: regular file ✓"
            elif [ "$_cas_link" = "skills" ] && [ -d "$_cas_cdir/$_cas_link" ]; then
                # skills/ is a real *directory* since #707 (F-8), not a
                # symlink — externally added per-skill links layer into it
                # (workspace skills come from plugins, not from here). Without this branch the diagnostic fell to
                # the else arm and wrongly reported "✗ missing" even though
                # setup.sh's own verify confirmed the dir (this loop never
                # learned the #707 layout change).
                ux_bullet "$_cas_link: composed dir ✓"
            else
                ux_bullet "$_cas_link: ✗ missing"
            fi
        done
        ux_info ""
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
# The corporate-internal PC use-case driving #571: a user ran
# `claude-accounts migrate` by mistake on an internal box (where the
# multi-account layout is structurally wrong), then `claude-yolo`
# hard-failed on the missing ~/.claude-personal check. Rollback gives
# them a one-shot recovery path without manual `mv`/`rm -rf`.
claude_accounts_rollback() {
    _car_active="${1:-}"

    if [ -n "${ZSH_VERSION:-}" ]; then
        emulate -L sh
    fi
    case "${1:-}" in -h | --help) _claude_accounts_help; return 0 ;; esac

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
        # shellcheck disable=SC2012  # display-only listing of account dirs under $HOME
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
#   settings.json, statusline-command.sh, skills, docs, workflows,
#   projects/GLOBAL/memory, CLAUDE.md, keybindings.json
# `plugins` is intentionally excluded — it points at ~/.claude-shared/
# (not DOTFILES_ROOT), so the worktree-bleed regression cannot reach it.
#
# Usage:
#   claude-accounts repair          # actually fix
#   claude-accounts repair --dry-run  # report only, no mutation
claude_accounts_repair() {
    case "${1:-}" in -h | --help) _claude_accounts_help; return 0 ;; esac
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
                if _claude_link_lib && dotfiles_ensure_link "$_car_canon" "$_car_link"; then
                    _car_repaired=$((_car_repaired + 1))
                else
                    ux_error "    rebind failed: $_car_link — manual recovery needed"
                fi
            else
                _car_repaired=$((_car_repaired + 1))
            fi
        done <<EOF
settings.json|${_car_claude_src}/settings.json
statusline-command.sh|${_car_claude_src}/statusline-command.sh
skills|${_car_claude_src}/skills
docs|${_car_claude_src}/docs
workflows|${_car_claude_src}/workflows
projects/GLOBAL/memory|${_car_claude_src}/global-memory
CLAUDE.md|${_car_claude_src}/CLAUDE.md
keybindings.json|${_car_claude_src}/keybindings.json
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
    ux_info "  link [<src>] [--name <n>] [--dry-run|--apply] [--force] | link --list"
    ux_info "                Symlink an external skill into every account (issue #1847)"
    ux_info "  unlink <name> Remove that skill symlink from every account (symlinks only)"
    ux_info "  -h|--help     This help"
    ux_info ""
    ux_info "Env vars:"
    ux_info "  CLAUDE_DEFAULT_ACCOUNT     Default for \`claude-yolo\` (default: personal)"
    ux_info "  CLAUDE_ENABLED_ACCOUNTS    Whitelist (default: 'personal work')"
    ux_info "  DOTFILES_ROOT_NO_CANONICALIZE=1  Skip worktree canonicalization (issue #589 escape hatch)"
    ux_info "  Override per-PC in shell-common/env/claude.local.sh"
}
