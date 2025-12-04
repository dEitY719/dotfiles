# ~/dotfiles/bash/main.bash

# Set the base directory for dotfiles bash configurations
DOTFILES_BASH_FULL_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_BASH_DIR="$(dirname "${DOTFILES_BASH_FULL_PATH}")"
export DOTFILES_BASH_DIR

# --- UX Library Initialization ---
# Load central UX library for consistent styling across all functions
# This provides: colors, output functions, progress indicators, interactive prompts, tables
# Replaces the old beauty_log.bash and log_util.bash system
# shellcheck source=/dev/null
source "${DOTFILES_BASH_DIR}/ux_lib/ux_lib.bash"

# 로딩 시작 스피너
# echo ""
# log_progress_start "Loading dotfiles configurations..."

# Initialize a counter for sourced files (global integer)
declare -gi SOURCED_FILES_COUNT=0

# ------------------------------------------------------------------
# --- Clean up old *help() functions before re-loading ---
# This prevents stale function definitions from persisting across shell reloads
while IFS= read -r func; do
    func_name="${func%%(*}"
    # Only unset help functions (ending with 'help'), excluding myhelp itself
    if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]]; then
        unset -f "$func_name" 2>/dev/null
    fi
done < <(
    # 빈 매치가 정상인 케이스를 pipefail에서 실패로 보지 않도록 허용
    declare -F | awk '{print $3}' | { grep 'help$' || true; } | LC_ALL=C sort
)

# ------------------------------------------------------------------
# Function to safely source a file and increment counter
# shellcheck disable=SC1073
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

# --- Auto-load all other directories ---
# This automatically discovers and loads all .bash files from subdirectories
# New directories are automatically included without modifying this file
for dir in "${DOTFILES_BASH_DIR}"/*; do
    [ -d "$dir" ] || continue

    dir_name=$(basename "$dir")

    # Skip special directories that shouldn't be auto-loaded
    [[ "$dir_name" == "core" ]] && continue    # Deprecated files
    [[ "$dir_name" == "ux_lib" ]] && continue  # Already loaded explicitly
    [[ "$dir_name" == "env" ]] && continue     # Already loaded above
    [[ "$dir_name" == "scripts" ]] && continue # Executable scripts, not sourced
    [[ "$dir_name" == "config" ]] && continue  # Configuration files only
    [[ "$dir_name" == "claude" ]] && continue  # Claude-specific settings

    # Load all .bash files in this directory (including local.bash)
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
# --- 모듈 파일 로드 완료 후 스피너 중지 및 요약 정보 ---
# log_progress_stop "\nDotfiles configuration loaded successfully. (Total files sourced: ${SOURCED_FILES_COUNT})"
echo "Dotfiles configuration loaded successfully. (Total files sourced: ${SOURCED_FILES_COUNT})"
# print_bash_config_loaded
# print_seraph_banner
clean_paths

# ------------------------------------------------------------------
# --- Master Help Function ---
# Automatically detects and lists all *help() functions
# Now uses the central UX library for consistent styling
# ------------------------------------------------------------------
myhelp() {
    # UX library is already loaded globally in main.bash
    ux_header "Dotfiles Help Functions"

    ux_section "Available help commands"

    # Automatically detect all functions ending with 'help' (excluding myhelp itself)
    local help_funcs=()
    while IFS= read -r func; do
        local func_name="${func%%(*}"
        if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]] && [[ "$func_name" != _* ]]; then
            help_funcs+=("$func_name")
        fi
    done < <(declare -F | awk '{print $3}' | { grep 'help$' || true; } | LC_ALL=C sort)

    # Descriptions
    declare -A help_descriptions=(
        ["uvhelp"]="UV package manager commands"
        ["githelp"]="Git shortcuts and aliases"
        ["pyhelp"]="Python virtual environment commands"
        ["dirhelp"]="Directory navigation aliases"
        ["syshelp"]="System management commands"
        ["pphelp"]="Python package and code quality tools"
        ["clihelp"]="Custom Project CLI list"
        ["duhelp"]="disk usage help"
        ["psqlhelp"]="PostgreSQL command helper"
        ["cchelp"]="Claude Code Usage help"
        ["claudehelp"]="Claude Code MCP help"
        ["dockerhelp"]="Docker commands and aliases"
        ["apthelp"]="APT package manager commands"
        ["geminihelp"]="Gemini CLI commands and aliases"
        ["codexhelp"]="Codex CLI commands and aliases"
        ["dproxyhelp"]="Docker Proxy(Corporate) commands"
        ["npmhelp"]="NPM package manager commands"
        ["litellm_help"]="LiteLLM commands and aliases"
        ["uxhelp"]="UX library functions and styling guide"
    )

    # Calculate max width for alignment
    local max_width=0
    local func
    for func in "${help_funcs[@]}"; do
        if ((${#func} > max_width)); then
            max_width=${#func}
        fi
    done

    # Display help functions
    for func in "${help_funcs[@]}"; do
        local desc="${help_descriptions[$func]:-No description available}"
        printf "  ${UX_SUCCESS}%-${max_width}s${UX_RESET}  ${UX_MUTED}:${UX_RESET}  %s\n" "$func" "$desc"
    done

    echo ""
    ux_divider
    echo ""
    ux_info "Type any of the above commands to see detailed help"
    echo "  ${UX_MUTED}Example:${UX_RESET} ${UX_INFO}githelp${UX_RESET}, ${UX_INFO}uvhelp${UX_RESET}, ${UX_INFO}dockerhelp${UX_RESET}"
    echo ""
    ux_warning "To add a new help function:"
    ux_bullet "Create a function ending with 'help' (e.g., dockerhelp)"
    ux_bullet "It will be automatically detected by ${UX_SUCCESS}myhelp${UX_RESET}"
    echo ""
}
