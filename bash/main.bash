# ~/dotfiles/bash/main.bash

# Set the base directory for dotfiles bash configurations
DOTFILES_BASH_FULL_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_BASH_DIR="$(dirname "${DOTFILES_BASH_FULL_PATH}")"
export DOTFILES_BASH_DIR

# --- Logging Initialization ---
# beauty_log.bash 로드 후 init_logging 호출
# (log_* 함수와 스피너 사용)
# shellcheck source=/dev/null
source "${DOTFILES_BASH_DIR}/core/beauty_log.bash"
# init_logging "${DOTFILES_BASH_DIR}"

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
        log_error "${error_msg}: ${file_path}" || true
    fi
}

# ------------------------------------------------------------------
# --- WSL 기본 bashrc 로드 ---
DEFAULT_WSL_BASHRC_PATH="${DOTFILES_BASH_DIR}/core/default_wsl_bashrc.bash"
safe_source "${DEFAULT_WSL_BASHRC_PATH}" "Core WSL bashrc file not found"

# ------------------------------------------------------------------
# 글롭이 비었을 때 '*.bash' 리터럴이 루프에 들어가지 않도록 nullglob 사용
__NULLGLOB_WAS_ON=0
if shopt -q nullglob; then
    __NULLGLOB_WAS_ON=1
fi
shopt -s nullglob

# --- 환경 변수 스크립트 로드 ---
ENV_DIR="${DOTFILES_BASH_DIR}/env"
for f in "${ENV_DIR}/"*.bash; do
    # log_util.bash는 core에 있으므로 일반적으로 여기에 해당 없음 (예외 방어 남김)
    if [[ "$f" == "${DOTFILES_BASH_DIR}/core/log_util.bash" ]]; then
        continue
    fi
    safe_source "$f" "Environment variable file not found"
done

# --- Load local environment overrides (not tracked by git) ---
if [[ -f "${ENV_DIR}/local.bash" ]]; then
    safe_source "${ENV_DIR}/local.bash" "Local environment file not found"
fi

# --- Aliases ---
ALIAS_DIR="${DOTFILES_BASH_DIR}/alias"
for f in "${ALIAS_DIR}/"*.bash; do
    safe_source "$f" "Alias file not found"
done

# --- Load local aliases (not tracked by git) ---
if [[ -f "${ALIAS_DIR}/local.bash" ]]; then
    safe_source "${ALIAS_DIR}/local.bash" "Local alias file not found"
fi

# --- App settings ---
APP_DIR="${DOTFILES_BASH_DIR}/app"
for f in "${APP_DIR}/"*.bash; do
    safe_source "$f" "Application setting file not found"
done

# --- Load local app configurations (not tracked by git) ---
if [[ -f "${APP_DIR}/local.bash" ]]; then
    safe_source "${APP_DIR}/local.bash" "Local app file not found"
fi

# --- Core utilities ---
COREUTILS_DIR="${DOTFILES_BASH_DIR}/coreutils"
for f in "${COREUTILS_DIR}/"*.bash; do
    safe_source "$f" "Core Utils setting file not found"
done

# --- Utilities ---
UTIL_DIR="${DOTFILES_BASH_DIR}/util"
for f in "${UTIL_DIR}/"*.bash; do
    safe_source "$f" "Utility setting file not found"
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
# ------------------------------------------------------------------
myhelp() {
    # Color definitions
    local bold blue green yellow cyan reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    cyan=$(tput setaf 6 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}╔════════════════════════════════════════════════════════════════╗${reset}
${bold}${blue}║                   Dotfiles Help Functions                      ║${reset}
${bold}${blue}╚════════════════════════════════════════════════════════════════╝${reset}

EOF

    echo "${bold}${blue}Available help commands:${reset}"
    echo ""

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
    )

    local max_width=0
    local func
    for func in "${help_funcs[@]}"; do
        if ((${#func} > max_width)); then
            max_width=${#func}
        fi
    done

    for func in "${help_funcs[@]}"; do
        local desc="${help_descriptions[$func]:-No description available}"
        printf "  ${green}%-${max_width}s${reset}  :  %s\n" "$func" "$desc"
    done

    cat <<EOF

${bold}${blue}Usage:${reset} Type any of the above commands to see detailed help.
${bold}${blue}Example:${reset} ${cyan}githelp${reset}, ${cyan}uvhelp${reset}, ...

${bold}${yellow}To add a new help function:${reset}
  1. Create a function ending with 'help' (e.g., dockerhelp)
  2. It will be automatically detected by ${green}myhelp()${reset}

EOF
}
