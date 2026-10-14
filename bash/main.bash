# ~/dotfiles/bash/main.bash
# Bash entry point. Loading core: shell-common/util/bootstrap.sh + loader.sh
# (#2134). Order: shell-common (env -> aliases -> functions -> integrations
# -> projects) -> bash/env/*.bash -> summary -> fzf/fasd -> setup mode.

# Prevent loading in zsh (use zsh/main.zsh instead)
if [ -n "$ZSH_VERSION" ]; then
    return 0
fi

# DOTFILES_ROOT candidate. realpath follows symlinks (.bashrc -> bash/main.bash);
# bootstrap.sh canonicalizes it to the main worktree (#589).
_BASH_SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DOTFILES_ROOT="${_BASH_SCRIPT_DIR%/bash}"

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
# shellcheck source=../shell-common/util/bootstrap.sh
. "${DOTFILES_ROOT}/shell-common/util/bootstrap.sh"
case $? in
0) ;;
1) return 0 ;; # skip (or bootstrap.sh missing: the shell already printed why)
*)
    printf 'dotfiles: core load failed under %s\n' "${SHELL_COMMON}" >&2
    return 1
    ;;
esac

DOTFILES_BASH_DIR="$_BASH_SCRIPT_DIR"
export DOTFILES_BASH_DIR

# nullglob stays on for the whole module load (its pre-#2134 scope), so an
# empty glob in a sourced file or in the bash/env loop yields no words.
__NULLGLOB_WAS_ON=0
shopt -q nullglob && __NULLGLOB_WAS_ON=1
shopt -s nullglob

dotfiles_load_all

# Bash-specific env loads after shell-common so it can override common values.
for f in "${DOTFILES_BASH_DIR}/env/"*.bash; do
    safe_source "$f" "Environment variable file not found"
done
[ "$__NULLGLOB_WAS_ON" -eq 0 ] && shopt -u nullglob
unset __NULLGLOB_WAS_ON

dotfiles_show_init_summary

# Clean up duplicate PATH entries (defined in env/path.sh)
command -v clean_paths >/dev/null 2>&1 && clean_paths

# fzf key bindings and completion
if command -v fzf >/dev/null 2>&1; then
    [ -f /usr/share/doc/fzf/examples/key-bindings.bash ] &&
        source /usr/share/doc/fzf/examples/key-bindings.bash
    [ -f /usr/share/bash-completion/completions/fzf ] &&
        source /usr/share/bash-completion/completions/fzf
fi

# fasd initialization for fast access to directories and files
if command -v fasd >/dev/null 2>&1; then
    eval "$(fasd --init auto)"
fi

. "${SHELL_COMMON}/util/setup_mode.sh"
_apply_setup_mode_config

# Local PC-specific overrides — installer-mutable lines (bun, nvm, pyenv, …)
# live here so the tracked dotfile stays clean (#1290, mirrors zsh #737/PR #736):
# routing them through the untracked ~/.bashrc.local plus the pre-commit
# hardcoded-home-path guard keeps resolved /home/<user>/... paths out of this SSOT.
[ -f "$HOME/.bashrc.local" ] && source "$HOME/.bashrc.local"
