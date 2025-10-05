# ~/dotfiles/bash/main.bash

# Set the base directory for dotfiles bash configurations

DOTFILES_BASH_FULL_PATH=$(realpath "${BASH_SOURCE[0]}")

DOTFILES_BASH_DIR="$(dirname "${DOTFILES_BASH_FULL_PATH}")"
export DOTFILES_BASH_DIR

# --- Logging Initialization ---
# init_logging 함수를 호출하여 로깅 기능을 초기화합니다.
# DOTFILES_BASH_DIR 변수를 인자로 � �달합니다.

source "${DOTFILES_BASH_DIR}/core/beauty_log.bash"
init_logging "${DOTFILES_BASH_DIR}"

# 로딩 시작 스피너
echo ""
log_progress_start "Loading dotfiles configurations..."

# Initialize a counter for sourced files
SOURCED_FILES_COUNT=0

# ------------------------------------------------------------------
# --- Clean up old *help() functions before re-loading ---
# This prevents stale function definitions from persisting across shell reloads
while IFS= read -r func; do
    func_name="${func%%(*}"
    # Only unset help functions (ending with 'help'), excluding myh itself
    if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myh" ]]; then
        unset -f "$func_name" 2>/dev/null
    fi
done < <(declare -F | awk '{print $3}' | grep 'help$' 2>/dev/null | sort)

# Function to safely source a file and increment counter
# shellcheck disable=SC1073
safe_source() {
    local file_path="$1"
    local error_msg="$2" # Optional custom error message
    if [[ -f "${file_path}" ]]; then
        source "${file_path}"
        ((SOURCED_FILES_COUNT++))
    else
        log_error "${error_msg:-File not found}: ${file_path}"
    fi
}

# --- WSL 기본 bashrc 설� � 로드 ---
DEFAULT_WSL_BASHRC_PATH="${DOTFILES_BASH_DIR}/core/default_wsl_bashrc.bash"
# log_info "Sourcing core WSL bashrc from: ${DEFAULT_WSL_BASHRC_PATH}" # 스피너 사용 시 이 메시지는 생략
safe_source "${DEFAULT_WSL_BASHRC_PATH}" "Core WSL bashrc file not found"

# ------------------------------------------------------------------
# --- 환경 변수 설� � 로드 ---
ENV_DIR="${DOTFILES_BASH_DIR}/env"
# log_info "Sourcing environment variables from: ${ENV_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${ENV_DIR}/"*.bash; do
    # log_util.bash는 이미 sourced.
    if [[ "$f" == "${DOTFILES_BASH_DIR}/core/log_util.bash" ]]; then
        continue
    fi
    safe_source "$f" "Environment variable file not found"
done

# --- Load local environment overrides (not tracked by git) ---
if [[ -f "${ENV_DIR}/local.bash" ]]; then
    safe_source "${ENV_DIR}/local.bash" "Local environment file not found"
fi

# ------------------------------------------------------------------
ALIAS_DIR="${DOTFILES_BASH_DIR}/alias"
# log_info "Sourcing aliases from: ${ALIAS_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${ALIAS_DIR}/"*.bash; do
    safe_source "$f" "Alias file not found"
done

# --- Load local aliases (not tracked by git) ---
if [[ -f "${ALIAS_DIR}/local.bash" ]]; then
    safe_source "${ALIAS_DIR}/local.bash" "Local alias file not found"
fi
# ------------------------------------------------------------------

APP_DIR="${DOTFILES_BASH_DIR}/app"
# log_info "Sourcing application settings from: ${APP_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${APP_DIR}/"*.bash; do
    safe_source "$f" "Application setting file not found"
done

# --- Load local app configurations (not tracked by git) ---
if [[ -f "${APP_DIR}/local.bash" ]]; then
    safe_source "${APP_DIR}/local.bash" "Local app file not found"
fi

COREUTILS_DIR="${DOTFILES_BASH_DIR}/coreutils"
for f in "${COREUTILS_DIR}/"*.bash; do
    safe_source "$f" "Core Utils setting file not found"
done

UTIL_DIR="${DOTFILES_BASH_DIR}/util"
for f in "${UTIL_DIR}/"*.bash; do
    safe_source "$f" "Utility setting file not found"
done

# ------------------------------------------------------------------
# --- 모�  파일 로드 완료 후 스피너 중지 및 요약 � �보 ---
log_progress_stop "\nDotfiles configuration loaded successfully. (Total files sourced: ${SOURCED_FILES_COUNT})"
print_bash_config_loaded
print_seraph_banner
clean_paths

# ------------------------------------------------------------------
# --- Master Help Function ---
# Automatically detects and lists all *help() functions
# ------------------------------------------------------------------
myhelp() {
    cat <<-'EOF'

╔════════════════════════════════════════════════════════════════╗
║                   Dotfiles Help Functions                      ║
╚════════════════════════════════════════════════════════════════╝

EOF

    echo "Available help commands:"
    echo ""

    # Automatically detect all functions ending with 'h' (excluding myh itself)
    local help_funcs=()
    while IFS= read -r func; do
        # Extract function name only (remove parentheses)
        func_name="${func%%(*}"
        if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]] && [[ "$func_name" != _* ]]; then
            help_funcs+=("$func_name")
        fi
    done < <(declare -F | awk '{print $3}' | grep 'help$' | sort)

    # Display help functions with descriptions
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
    )

    local max_width=0
    for func in "${help_funcs[@]}"; do
        if ((${#func} > max_width)); then
            max_width=${#func}
        fi
    done

    for func in "${help_funcs[@]}"; do
        desc="${help_descriptions[$func]:-No description available}"
        printf "  %-${max_width}s  :  %s\n" "$func" "$desc"
    done

    cat <<-'EOF'

Usage: Type any of the above commands to see detailed help.
Example: githelp, uvhelp, ...

To add a new help function:
  1. Create a function ending with 'help' (e.g., dockerhelp)
  2. It will be automatically detected by myhelp()

EOF
}
