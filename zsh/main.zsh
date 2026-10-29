#!/bin/zsh

# zsh/main.zsh
# Zsh entry point. Loading core: shell-common/util/bootstrap.sh + loader.sh
# (#2134). Order: shell-common (env -> aliases -> functions -> integrations
# -> projects) -> zsh/app -> setup mode -> summary.

# Exit if not in zsh (safely return without killing shell)
if [ -z "$ZSH_VERSION" ]; then
    return 0
fi

# Clear bash-specific variables inherited from a parent bash shell
unset DOTFILES_BASH_DIR

# DOTFILES_ROOT candidate: zshrc may preset it; otherwise derive it from this
# script's location (${(%):-%N} is the sourced script name). bootstrap.sh
# canonicalizes it to the main worktree (#589).
if [ -z "$DOTFILES_ROOT" ]; then
    _ZSH_SCRIPT_DIR="$(cd "$(dirname "${${(%):-%N}:-$0}")" 2>/dev/null && pwd)" || _ZSH_SCRIPT_DIR=""
    DOTFILES_ROOT="${_ZSH_SCRIPT_DIR%/zsh}"
    [ -n "$DOTFILES_ROOT" ] && [ -d "$DOTFILES_ROOT" ] || DOTFILES_ROOT="${HOME}/dotfiles"
fi

# Unfinished-merge diagnostic (#2078). Inline on purpose: sourcing anything
# here would die with the very conflict-marker breakage it reports. Plain
# printf because ux_lib is not loaded yet (same exception as git-sync.sh #1958).
case $- in *i*)
    if [ -f "${DOTFILES_ROOT}/.git/MERGE_HEAD" ]; then
        printf '⚠ dotfiles 머지 미완(.git/MERGE_HEAD 존재) — cd "%s" && git status 로 충돌을 해결하세요\n' "${DOTFILES_ROOT}" >&2
    fi
    ;;
esac

# Skip guard (non-interactive / DOTFILES_SKIP_INIT / Codex), canonical root,
# SHELL_COMMON, counter, safe_source, ux_lib, loader.
. "${DOTFILES_ROOT}/shell-common/util/bootstrap.sh"
case $? in
0) ;;
1) return 0 ;; # skip (or bootstrap.sh missing: the shell already printed why)
*)
    printf 'dotfiles: core load failed under %s\n' "${SHELL_COMMON}" >&2
    return 1
    ;;
esac

ZSH_DOTFILES="${DOTFILES_ROOT}/zsh"
export ZSH_DOTFILES

dotfiles_load_all

# Zsh application modules: zsh.zsh and git.zsh first (dependencies), then the rest.
_load_zsh_apps() {
    local f seen=" "
    for f in "${ZSH_DOTFILES}/app/zsh.zsh" "${ZSH_DOTFILES}/app/git.zsh" "${ZSH_DOTFILES}"/app/*.zsh(N); do
        case "$seen" in *" $f "*) continue ;; esac
        seen="${seen}${f} "
        safe_source "$f" "Failed to load zsh app" || true
    done
}
_load_zsh_apps

. "${SHELL_COMMON}/util/setup_mode.sh"
_apply_setup_mode_config

dotfiles_show_init_summary

# Clean up duplicate PATH entries (defined in env/path.sh; mirrors bash/main.bash)
command -v clean_paths >/dev/null 2>&1 && clean_paths
