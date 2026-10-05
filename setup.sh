#!/bin/bash

# setup.sh: Shell environment setup orchestrator
#
# PURPOSE: Set up all shell configurations (bash, zsh, git)
# WHEN TO RUN: On initial dotfiles installation (REQUIRED)
#
# This script orchestrates the setup of individual shell environments.
# Each sub-script performs specific initialization:
#   - bash/setup.sh: Sets DOTFILES_BASH_DIR, SHELL_COMMON environment variables
#   - zsh/setup.sh: Provides user feedback and guidance
#   - git/setup.sh: Sets up git configuration
#   - claude/setup.sh: Manages Claude Code settings via symlinks
#
# See SETUP_GUIDE.md for detailed information
#
# ⚠️  IMPORTANT: Do NOT delete bash/setup.sh, zsh/setup.sh, git/setup.sh, claude/setup.sh, or gh/setup.sh
#     They perform special initialization beyond simple symlink creation

# Output contract (summary mode, default): one line per step; warnings/failures
# get detail + a fix hint. Full sub-script output goes to $SETUP_LOG.
# `./setup.sh -v` or DOTFILES_SETUP_VERBOSE=1 streams everything as before.
# DOTFILES_SETUP_CHOICE=1|2|3 answers the environment menu non-interactively.
# Critical vs optional classification lives in main() below.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UX_LIB_SCRIPT="${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "${UX_LIB_SCRIPT}" ]; then
    # shellcheck source=/dev/null
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

SETUP_VERBOSE="${DOTFILES_SETUP_VERBOSE:-0}"
SETUP_LOG="/dev/null"
_STEP_OUT="/dev/null"
_STEP_TOTAL=0
_STEP_WARNED=()
_STEP_FAILED=()

# Deciseconds since epoch into _NOW_DS (bash 5 EPOCHREALTIME; whole seconds otherwise).
_setup_now_ds() {
    local t="${EPOCHREALTIME:-$SECONDS.0}" f
    t="${t/,/.}"
    f="${t#*.}"
    _NOW_DS=$((${t%.*} * 10 + ${f:0:1}))
}

_step_hint() {
    case "$1" in
    shell-common*) ux_bullet_sub "환경 메뉴 입력/sudo(APT) 단계 확인 — 단독 재현: ./shell-common/setup.sh" ;;
    "bats submodule") ux_bullet_sub "git submodule update --init --recursive tests/bats/lib" ;;
    verify-config) ux_bullet_sub "로그에 표시된 손상 파일(JSON/NBSP/BOM/NUL)을 고친 뒤 재실행" ;;
    esac
}

# run_step <label> <critical|optional> <cmd...>
run_step() {
    local label="$1" level="$2" rc=0 t0 dt d miss="" warns
    shift 2
    _STEP_TOTAL=$((_STEP_TOTAL + 1))
    _setup_now_ds
    t0=$_NOW_DS
    : >"$_STEP_OUT"
    if [ "${1#*/}" != "$1" ] && [ ! -x "$1" ]; then
        rc=127
        miss="스크립트가 없거나 실행 권한이 없음: $1"
    elif [ "$SETUP_VERBOSE" = 1 ]; then
        "$@" || rc=$?
    else
        "$@" >"$_STEP_OUT" 2>&1 || rc=$?
    fi
    {
        ux_info "=== [$label] $* (exit $rc) ==="
        cat "$_STEP_OUT"
    } >>"$SETUP_LOG" 2>&1
    _setup_now_ds
    d=$((_NOW_DS - t0))
    dt="$((d / 10)).$((d % 10))s"

    if [ "$rc" -eq 0 ]; then
        warns=$(grep -E '⚠|❌' "$_STEP_OUT" || true)
        if [ -z "$warns" ]; then
            ux_success "$label ($dt)"
            return 0
        fi
        ux_warning "$label ($dt) — 경고 $(grep -c . <<<"$warns")줄"
        while IFS= read -r line; do
            ux_bullet_sub "${line#"${line%%[![:space:]]*}"}"
        done < <(head -n 10 <<<"$warns")
        _STEP_WARNED+=("$label")
        return 0
    fi

    {
        ux_error "$label 실패 [$level] (exit $rc, $dt)"
        if [ -n "$miss" ]; then ux_bullet_sub "$miss"; fi
        if [ -s "$_STEP_OUT" ]; then
            ux_bullet "로그 마지막 20줄:"
            while IFS= read -r line; do ux_bullet_sub "$line"; done < <(tail -n 20 "$_STEP_OUT")
        fi
        ux_bullet "조치:"
        if [ "${1#*/}" != "$1" ]; then
            ux_bullet_sub "상세 재현: bash -x $1"
        else
            ux_bullet_sub "상세 재현: ./setup.sh -v"
        fi
        _step_hint "$label"
        if [ "$SETUP_LOG" != /dev/null ]; then ux_bullet_sub "전체 로그: $SETUP_LOG"; fi
    } >&2
    if [ "$level" = critical ]; then
        ux_error "critical 스텝 '$label' 실패 — setup 을 중단합니다. 위 조치 후 ./setup.sh 를 다시 실행하세요."
        exit 1
    fi
    _STEP_FAILED+=("$label")
}

_setup_summary() {
    local ok=$((_STEP_TOTAL - ${#_STEP_WARNED[@]} - ${#_STEP_FAILED[@]}))
    ux_info ""
    if [ "$ok" -eq "$_STEP_TOTAL" ]; then
        ux_success "setup 완료: ${_STEP_TOTAL}개 스텝 모두 정상"
    else
        ux_warning "setup 완료(확인 필요): 총 ${_STEP_TOTAL} / 성공 ${ok} / 경고 ${#_STEP_WARNED[@]} / 실패 ${#_STEP_FAILED[@]}"
        if [ ${#_STEP_WARNED[@]} -gt 0 ]; then ux_warning "경고 스텝: ${_STEP_WARNED[*]}"; fi
        if [ ${#_STEP_FAILED[@]} -gt 0 ]; then ux_error "실패 스텝(optional): ${_STEP_FAILED[*]}"; fi
    fi
    if [ "$SETUP_LOG" != /dev/null ]; then ux_info "전체 로그: $SETUP_LOG"; fi
}

# Sets SETUP_CHOICE (1|2|3): $DOTFILES_SETUP_CHOICE > prompt (saved mode = Enter default).
_setup_resolve_choice() {
    local saved="" def="" ans
    case "${DOTFILES_SETUP_CHOICE:-}" in
    1 | 2 | 3) SETUP_CHOICE="$DOTFILES_SETUP_CHOICE" && return 0 ;;
    "") ;;
    *) ux_error "DOTFILES_SETUP_CHOICE 는 1|2|3 이어야 합니다 (현재: ${DOTFILES_SETUP_CHOICE})" && return 1 ;;
    esac
    [ -f "$HOME/.dotfiles-setup-mode" ] && saved=$(tr -d ' \t\r\n' <"$HOME/.dotfiles-setup-mode")
    case "$saved" in
    1 | public) def=1 ;;
    2 | internal) def=2 ;;
    3 | external) def=3 ;;
    esac
    if [ ! -t 0 ]; then
        [ -n "$def" ] && SETUP_CHOICE="$def" && return 0
        ux_error "비대화형 실행인데 환경을 알 수 없습니다 — DOTFILES_SETUP_CHOICE=1|2|3 을 지정하세요."
        return 1
    fi
    ux_info "환경 선택: 1) Public PC  2) Internal company PC  3) External company PC (VPN)"
    if [ -n "$def" ]; then
        ans=$(ux_input "선택 (1-3, Enter=현재 ${def} 유지):" '^[1-3]?$')
        SETUP_CHOICE="${ans:-$def}"
    else
        SETUP_CHOICE=$(ux_input "선택 (1-3):" '^[1-3]$')
    fi
}

_setup_run_shell_common() {
    printf '%s\n' "$SETUP_CHOICE" | ./shell-common/setup.sh
}

setup_help() {
    ux_usage "./setup.sh" "[-v|--verbose] [-h|--help]" "Converge this PC's dotfiles: symlinks + per-tool setup (idempotent)"
    ux_bullet "-v, --verbose: stream full sub-script output (default: one line per step, log under \$TMPDIR)"
    ux_bullet "DOTFILES_SETUP_VERBOSE=1: same as -v"
    ux_bullet "DOTFILES_SETUP_CHOICE=1|2|3: answer the environment menu (public/internal/external) non-interactively"
}

main() {
    local canonical=""
    case "${1:-}" in
    -h | --help) setup_help; return 0 ;;
    -v | --verbose) SETUP_VERBOSE=1 ;;
    esac

    # Canonicalize to the main worktree (issue #589). Running ./setup.sh from a
    # linked worktree would otherwise bake the worktree path into every
    # ~/.claude-*/{settings.json, statusline-command.sh, skills, docs, ...}
    # symlink. When the worktree is later removed those symlinks dangle and
    # Claude Code silently reverts to defaults (no statusline, no hooks).
    if [ -r "${DOTFILES_DIR}/shell-common/functions/dotfiles_root.sh" ]; then
        # shellcheck source=shell-common/functions/dotfiles_root.sh
        source "${DOTFILES_DIR}/shell-common/functions/dotfiles_root.sh"
        canonical=$(_resolve_dotfiles_root_canonical "$DOTFILES_DIR")
        if [ -n "$canonical" ] && [ "$canonical" != "$DOTFILES_DIR" ]; then
            ux_info "워크트리에서 실행됨 — 메인 워크트리로 전환: $canonical"
            DOTFILES_DIR="$canonical"
        fi
    fi
    cd "$DOTFILES_DIR"

    if [ "$SETUP_VERBOSE" != 1 ]; then
        SETUP_LOG="${TMPDIR:-/tmp}/dotfiles-setup-$(date +%Y%m%d-%H%M%S).log"
        _STEP_OUT="${SETUP_LOG}.step"
        : >"$SETUP_LOG"
        ux_info "dotfiles setup (요약 모드 — 전체 출력은 ./setup.sh -v)"
    fi

    # Verbose without DOTFILES_SETUP_CHOICE keeps the original interactive menu
    # (and shell-common's tty-only account ID / account e-mail prompts).
    local sc_step=(_setup_run_shell_common) sc_label="shell-common"
    if [ "$SETUP_VERBOSE" = 1 ] && [ -z "${DOTFILES_SETUP_CHOICE:-}" ]; then
        sc_step=(./shell-common/setup.sh)
    else
        _setup_resolve_choice || exit 1
        case "$SETUP_CHOICE" in 1) sc_label+=" (public)" ;; 2) sc_label+=" (internal)" ;; 3) sc_label+=" (external)" ;; esac
    fi

    # Neutralize leftover git-crypt smudge/clean config (#594).
    run_step "git-crypt 해제" critical ./scripts/disable-git-crypt-local.sh
    # bats submodules so a fresh clone's ./tests/test doesn't skip bats (#1398).
    # shellcheck source=shell-common/functions/dotfiles_bats_submodules.sh
    source "${DOTFILES_DIR}/shell-common/functions/dotfiles_bats_submodules.sh"
    run_step "bats submodule" optional dotfiles_ensure_bats_submodules "$DOTFILES_DIR"

    run_step "$sc_label" critical "${sc_step[@]}"
    run_step bash critical ./bash/setup.sh
    run_step zsh critical ./zsh/setup.sh
    run_step git critical ./git/setup.sh
    run_step obsidian optional ./obsidian/setup.sh # Obsidian CLI wrapper (#1023)
    run_step herdr optional ./herdr/setup.sh
    run_step hermes optional ./hermes/setup.sh # 1회 복사 (#1373)
    run_step claude critical ./claude/setup.sh
    run_step agy optional ./agy/setup.sh # Antigravity CLI 확인 (#1180)
    # Internal-PC AWS SSO/CLI seeding only; no-op on external/public PCs.
    run_step aws optional ./aws/setup.sh
    run_step skills-ssot critical ./scripts/setup-skills-ssot.sh
    run_step vscode-extensions optional ./vscode-extensions/setup.sh
    # .vscode/base.json → live VS Code settings (#586); exits 1 without VS Code.
    run_step vscode-settings optional ./.vscode/sync-push.sh
    run_step ssh optional ./ssh/setup.sh
    run_step gh optional ./gh/setup.sh
    run_step windows optional ./windows/setup.sh # WSL only
    # Post-setup integrity check (#594): JSON parse + NBSP/BOM/NUL scan.
    run_step verify-config critical ./scripts/verify-config-files.sh

    rm -f "${SETUP_LOG}.step"
    _setup_summary
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -e
    main "$@"
fi
