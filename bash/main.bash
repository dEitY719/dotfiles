# ~/dotfiles/bash/main.bash

# --- Initialization Guards ---
# Prevent loading in non-interactive shells or specific environments (like Codex CLI)
# to avoid permission errors, timeouts, and unwanted side effects.

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
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    else
        exit 0
    fi
fi

# Set the base directory for dotfiles bash configurations
# Use common initialization function for consistency across all scripts
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
source "$(dirname "$_SCRIPT_PATH")/util/init.bash"
DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "$_SCRIPT_PATH")"
export DOTFILES_BASH_DIR

# --- UX Library Initialization ---
# Load central UX library for consistent styling across all functions
# This provides: colors, output functions, progress indicators, interactive prompts, tables
# Replaces the old beauty_log.bash and log_util.bash system
# shellcheck source=/dev/null
source "${DOTFILES_BASH_DIR}/ux_lib/ux_lib.bash"

# Initialize a counter for sourced files (global integer)
declare -gi SOURCED_FILES_COUNT=0

# ------------------------------------------------------------------
# --- Helper function to get all *help() functions ---
# Used by both cleanup and myhelp display
_get_help_functions() {
    declare -F | awk '{print $3}' | { grep 'help$' || true; } | LC_ALL=C sort
}

# ------------------------------------------------------------------
# --- Clean up old *help() functions before re-loading ---
# This prevents stale function definitions from persisting across shell reloads
while IFS= read -r func; do
    func_name="${func%%(*}"
    if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]]; then
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
# Priority 1: ENV directory (environment variables must be loaded first)
# Priority 2: All other directories (auto-discovered, no manual addition needed)

# --- Load ENV directory first (environment variables) ---
for f in "${DOTFILES_BASH_DIR}/env/"*.bash; do
    [ -f "$f" ] || continue
    safe_source "$f" "Environment variable file not found"
done

# --- Load util/myhelp.bash early ---
# Must be loaded before app/*.bash to ensure HELP_DESCRIPTIONS associative array
# is properly initialized before modules try to register their descriptions
safe_source "${DOTFILES_BASH_DIR}/util/myhelp.bash" "MyHelp utility not found"

# --- Auto-load all other directories ---
# This automatically discovers and loads all .bash files from subdirectories
# New directories are automatically included without modifying this file

# Directories to skip (add new entries here instead of modifying loop logic)
SKIP_DIRS=(
    "core"    # Deprecated files
    "ux_lib"  # Already loaded explicitly
    "util"    # Already loaded explicitly (myhelp.bash)
    "env"     # Already loaded above
    "scripts" # Executable scripts, not sourced
    "config"  # Configuration files only
    "claude"  # Claude-specific settings
)

for dir in "${DOTFILES_BASH_DIR}"/*; do
    [ -d "$dir" ] || continue
    dir_name=$(basename "$dir")

    # Check if directory is in skip list
    skip=false
    for skip_dir in "${SKIP_DIRS[@]}"; do
        [[ "$dir_name" == "$skip_dir" ]] && {
            skip=true
            break
        }
    done
    [[ "$skip" == true ]] && continue

    # Load all .bash files in this directory
    for f in "$dir"/*.bash; do
        [ -f "$f" ] || continue
        safe_source "$f" "File not found in $dir_name"
    done
done

# --- Restore nullglob to previous state ---
if [[ ${__NULLGLOB_WAS_ON} -eq 0 ]]; then
    shopt -u nullglob
fi
unset __NULLGLOB_WAS_ON

# ------------------------------------------------------------------
# --- Module loading complete ---
echo "Dotfiles configuration loaded successfully. (Total files sourced: ${SOURCED_FILES_COUNT})"

# Clean up duplicate PATH entries (defined in env/path.bash)
type -t clean_paths &>/dev/null && clean_paths

# myhelp function is now loaded via bash/util/myhelp.bash (auto-discovered)
