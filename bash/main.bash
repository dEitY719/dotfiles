# ~/dotfiles/bash/main.bash

# --- Initialization Guards ---
# Prevent loading in non-interactive shells or specific environments (like Codex CLI)
# to avoid permission errors, timeouts, and unwanted side effects.

# 0. Prevent loading in zsh (use zsh/main.zsh instead)
if [ -n "$ZSH_VERSION" ]; then
    return 0
fi

# 1. Check for Codex Environment (npm managed or explicit CLI flag)
is_codex_env() {
    [[ -n "$CODEX_CLI" ]] ||
        [[ -n "$CODEX_MANAGED_BY_NPM" ]] ||
        [[ -n "$CODEX_SANDBOX_NETWORK_DISABLED" ]]
}

# 2. Main Guard Logic
# Skip if:
# - Non-interactive shell AND no force flag
# - Explicit skip flag is set
# - Codex environment detected (unless forced)
# Returns:
#   0 (true)  = YES, skip initialization
#   1 (false) = NO, proceed with initialization
should_skip_init() {
    if [[ -n "$DOTFILES_FORCE_INIT" ]]; then
        return 1 # Do not skip
    fi

    if [[ $- != *i* ]]; then
        return 0 # Skip (Non-interactive)
    fi

    if [[ -n "$DOTFILES_SKIP_INIT" ]]; then
        return 0 # Skip (Explicit skip)
    fi

    if is_codex_env; then
        return 0 # Skip (Codex)
    fi

    return 1 # Do not skip
}

if should_skip_init; then
    # Handle "return" vs "exit" depending on how the script was invoked
    # IMPORTANT: Use return even for direct execution to avoid killing the shell
    # (applies to both sourced and direct execution contexts)
    return 0
fi

# Set DOTFILES_ROOT + SHELL_COMMON using unified path resolution
# This ensures single source of truth across bash and zsh
# NOTE: Use realpath to follow symlinks (e.g., .bashrc → bash/main.bash)
_BASH_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_BASH_SCRIPT_DIR="$(dirname "$_BASH_SCRIPT_PATH")"
DOTFILES_ROOT="${_BASH_SCRIPT_DIR%/bash}"
export DOTFILES_ROOT
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
export SHELL_COMMON

# Set DOTFILES_BASH_DIR for bash-specific configurations
DOTFILES_BASH_DIR="$_BASH_SCRIPT_DIR"
export DOTFILES_BASH_DIR

# --- UX Library Initialization ---
# Load central UX library for consistent styling across all functions
# This provides: colors, output functions, progress indicators, interactive prompts, tables
# Unified library is now at shell-common/tools/ux_lib/
# shellcheck source=/dev/null
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

# Initialize a counter for sourced files (global integer)
declare -gi SOURCED_FILES_COUNT=0

# ------------------------------------------------------------------
# --- DEFENSE: Safe script name extraction (prevents $0 flag injection attacks) ---
# This function safely extracts the filename from $0 using parameter expansion
# instead of the external basename command, which was vulnerable to flag injection.
# Problem: When sourcing scripts with "bash -i -l", $0 could be "-i" or "-l"
# causing: basename "-i" → error: invalid option
# Solution: Use shell parameter expansion + validation
# ------------------------------------------------------------------
_get_safe_script_name() {
    local _fname="${0##*/}"

    # Validation: if filename starts with -, it's a flag (sourced context)
    # In that case, return empty string (means: don't treat as direct execution)
    if [ "${_fname#-}" = "$_fname" ]; then
        echo "$_fname"
    fi
}

# ------------------------------------------------------------------
# --- Helper function to get all *help() functions ---
# Used by both cleanup and my_help display
_get_help_functions() {
    declare -F | awk '{print $3}' | { grep 'help$' || true; } | LC_ALL=C sort
}

# ------------------------------------------------------------------
# --- Clean up old *help() functions before re-loading ---
# This prevents stale function definitions from persisting across shell reloads
while IFS= read -r func; do
    func_name="${func%%(*}"
    if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "my_help" ]]; then
        unset -f "$func_name" 2>/dev/null
    fi
done < <(_get_help_functions)

# ------------------------------------------------------------------
# Function to safely source a file and increment counter
safe_source() {
    local file_path="$1"
    local error_msg="${2:-File not found}"

    if [[ -f "$file_path" ]]; then
        # shellcheck source=/dev/null
        source "$file_path"

        # 전역 정수 보장 (혹시 글로벌 선언이 없었다면 이 안에서라도 보강)
        declare -gi SOURCED_FILES_COUNT=${SOURCED_FILES_COUNT:-0}
        # 전위 증가 → set -e 환경에서도 성공 상태 유지
        ((++SOURCED_FILES_COUNT))
    else
        # 오류 로깅은 하되, 초기화 흐름은 끊지 않음
        ux_error "${error_msg}: ${file_path}" || true
    fi
}

# ------------------------------------------------------------------
# NOTE: WSL default bashrc has been replaced by env/bash_settings.bash
# The old default_wsl_bashrc.bash has been deprecated
# Essential settings are now loaded via env/bash_settings.bash

# ------------------------------------------------------------------
# 글롭이 비었을 때 '*.bash' 리터럴이 루프에 들어가지 않도록 nullglob 사용
__NULLGLOB_WAS_ON=0
if shopt -q nullglob; then
    __NULLGLOB_WAS_ON=1
fi
shopt -s nullglob

# ------------------------------------------------------------------
# --- Load modules in priority order ---
# ------------------------------------------------------------------
# Priority 1: Shell-common (POSIX-compatible, shared across bash/zsh)
# Priority 2: ENV directory (bash-specific environment variables)
# Priority 3: All other directories (auto-discovered, no manual addition needed)

# --- Load shell-common modules via loader ---
# Centralized module loading with configuration-based filtering
source "${SHELL_COMMON}/util/loader.sh"

load_category "env"
load_category "aliases"
load_category "functions"

# --- Load shell-common tools (integrations) separately ---
# 3rd-party integrations: apt, ccusage, claude, codex, git, npm, opencode, etc
if [ -d "${SHELL_COMMON}/tools/integrations" ]; then
    for f in "${SHELL_COMMON}/tools/integrations/"*.sh; do
        [ -f "$f" ] || continue
        case "$f" in
        *.local.sh) continue ;;
        esac
        safe_source "$f" "Shell-common integration tool not found"
    done
fi

load_category "projects"

# --- Load bash-specific ENV directory ---
for f in "${DOTFILES_BASH_DIR}/env/"*.bash; do
    [ -f "$f" ] || continue
    safe_source "$f" "Environment variable file not found"
done

# Note: my_help is now loaded from shell-common/functions/my_help.sh (shared version)
# This was previously loaded here as bash/util/my_help.bash but we now use
# the unified shell-common version for parity with zsh

# --- Auto-load bash-specific directories ---
# Load all .bash files from DOTFILES_BASH_DIR subdirectories (except skip list in config)
load_auto_directories "${DOTFILES_BASH_DIR}" ".bash"

# --- Restore nullglob to previous state ---
if [[ ${__NULLGLOB_WAS_ON} -eq 0 ]]; then
    shopt -u nullglob
fi
unset __NULLGLOB_WAS_ON

# ------------------------------------------------------------------
# --- Module loading complete ---
# Display initialization summary (shared function from shell-common)
# Only show in truly interactive shells (with proper TTY) to avoid interfering with prompts
# (e.g., PowerLevel10k instant prompt)
if [[ $- == *i* && -t 1 ]] && type dotfiles_init_summary &>/dev/null; then
    dotfiles_init_summary "$SOURCED_FILES_COUNT"
fi

# Clean up duplicate PATH entries (defined in env/path.bash)
type -t clean_paths &>/dev/null && clean_paths

# my_help function is now loaded via shell-common/functions/my_help.sh (shared version)

# fzf key bindings and completion
if command -v fzf &>/dev/null; then
    # Source fzf key bindings
    if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        source /usr/share/doc/fzf/examples/key-bindings.bash
    fi

    # Source fzf completion
    if [ -f /usr/share/bash-completion/completions/fzf ]; then
        source /usr/share/bash-completion/completions/fzf
    fi
fi

# fasd initialization for fast access to directories and files
if command -v fasd &>/dev/null; then
    eval "$(fasd --init auto)"
fi

