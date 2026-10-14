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
#   - global-packages/setup.sh: Installs missing global uv tools (uv-tools.txt)
#   - mcporter/setup.sh: Points mcporter's exa server at ${EXA_API_KEY:-} (.enc.env)
#
# See docs/.ssot/one-click-setup.md for the full step list and idempotency rules
#
# ⚠️  IMPORTANT: Do NOT delete bash/setup.sh, zsh/setup.sh, git/setup.sh, claude/setup.sh, or gh/setup.sh
#     They perform special initialization beyond simple symlink creation

# Output contract (summary mode, default): one line per step; warnings/failures
# get detail + a fix hint. Full sub-script output goes to $STEP_LOG.
# `./setup.sh -v` or DOTFILES_SETUP_VERBOSE=1 streams everything as before.
# DOTFILES_SETUP_CHOICE=1|2|3 answers the environment menu non-interactively.
# Critical vs optional classification lives in main() below; the runner itself
# is shell-common/tools/ux_lib/step_runner.sh (#2126).

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

# Shared summary-mode runner: step_init / step_run / step_summary (#2126).
# shellcheck source=shell-common/tools/ux_lib/step_runner.sh
source "${DOTFILES_DIR}/shell-common/tools/ux_lib/step_runner.sh"
STEP_NAME=setup
STEP_RERUN=./setup.sh
STEP_HINT_FN=_step_hint

_step_hint() {
    case "$1" in
    shell-common*) ux_bullet_sub "sudo(APT) 단계 확인 — 단독 재현: ./shell-common/setup.sh --mode <public|internal|external>" ;;
    "bats submodule") ux_bullet_sub "git submodule update --init --recursive tests/bats/lib" ;;
    verify-config) ux_bullet_sub "로그에 표시된 손상 파일(JSON/NBSP/BOM/NUL)을 고친 뒤 재실행" ;;
    esac
}

# Sets SETUP_CHOICE (1|2|3): $DOTFILES_SETUP_CHOICE > prompt (saved mode = Enter default).
_setup_resolve_choice() {
    local saved="" def="" ans
    case "${DOTFILES_SETUP_CHOICE:-}" in
    1 | 2 | 3) SETUP_CHOICE="$DOTFILES_SETUP_CHOICE" && return 0 ;;
    "") ;;
    *) ux_error "DOTFILES_SETUP_CHOICE 는 1|2|3 이어야 합니다 (현재: ${DOTFILES_SETUP_CHOICE})" && return 1 ;;
    esac
    # shellcheck source=shell-common/util/setup_mode_read.sh
    . "${DOTFILES_DIR}/shell-common/util/setup_mode_read.sh"
    saved=$(_dotfiles_setup_mode)
    case "$saved" in
    public) def=1 ;;
    internal) def=2 ;;
    external) def=3 ;;
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

# Mode is passed as an argument, not piped into the menu (#2140). stdin stays
# non-tty as before: in summary mode a tty prompt would block unseen (output
# goes to the log), so the tty-only prompts skip with a warning instead.
_setup_run_shell_common() {
    local mode
    case "$SETUP_CHOICE" in 1) mode=public ;; 2) mode=internal ;; 3) mode=external ;; esac
    ./shell-common/setup.sh --mode "$mode" </dev/null
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
    -h | --help)
        setup_help
        return 0
        ;;
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

    step_init dotfiles-setup "$SETUP_VERBOSE"
    if [ "$STEP_VERBOSE" != 1 ]; then
        ux_info "dotfiles setup (요약 모드 — 전체 출력은 ./setup.sh -v)"
    fi

    # Verbose without DOTFILES_SETUP_CHOICE keeps the original interactive menu
    # (and shell-common's tty-only account ID / account e-mail prompts).
    local sc_step=(_setup_run_shell_common) sc_label="shell-common"
    if [ "$STEP_VERBOSE" = 1 ] && [ -z "${DOTFILES_SETUP_CHOICE:-}" ]; then
        sc_step=(./shell-common/setup.sh)
    else
        _setup_resolve_choice || exit 1
        case "$SETUP_CHOICE" in 1) sc_label+=" (public)" ;; 2) sc_label+=" (internal)" ;; 3) sc_label+=" (external)" ;; esac
    fi

    # Neutralize leftover git-crypt smudge/clean config (#594).
    step_run "git-crypt 해제" critical ./scripts/disable-git-crypt-local.sh
    # bats submodules so a fresh clone's ./tests/test doesn't skip bats (#1398).
    # shellcheck source=shell-common/functions/dotfiles_bats_submodules.sh
    source "${DOTFILES_DIR}/shell-common/functions/dotfiles_bats_submodules.sh"
    step_run "bats submodule" optional dotfiles_ensure_bats_submodules "$DOTFILES_DIR"

    step_run "$sc_label" critical "${sc_step[@]}"
    step_run bash critical ./bash/setup.sh
    step_run zsh critical ./zsh/setup.sh
    step_run git critical ./git/setup.sh
    step_run obsidian optional ./obsidian/setup.sh # Obsidian CLI wrapper (#1023)
    step_run herdr optional ./herdr/setup.sh
    step_run hermes optional ./hermes/setup.sh # 1회 복사 (#1373)
    step_run claude critical ./claude/setup.sh
    step_run agy optional ./agy/setup.sh # Antigravity CLI 확인 (#1180)
    step_run skills-ssot critical ./scripts/setup-skills-ssot.sh
    step_run vscode-extensions optional ./vscode-extensions/setup.sh
    # .vscode/base.json → live VS Code settings (#586); exits 1 without VS Code.
    step_run vscode-settings optional ./.vscode/sync-push.sh
    step_run global-packages optional ./global-packages/setup.sh # global uv tools 동기화, 삭제 안 함
    step_run mcporter optional ./mcporter/setup.sh               # exa 키를 .enc.env placeholder 로 (#2106)
    step_run ssh optional ./ssh/setup.sh
    step_run gh optional ./gh/setup.sh
    step_run windows optional ./windows/setup.sh # WSL only
    # Post-setup integrity check (#594): JSON parse + NBSP/BOM/NUL scan.
    step_run verify-config critical ./scripts/verify-config-files.sh

    step_summary setup
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -e
    main "$@"
fi
