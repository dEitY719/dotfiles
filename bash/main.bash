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
log_progress_start "Loading dotfiles configurations..."

# Initialize a counter for sourced files
SOURCED_FILES_COUNT=0

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

# ------------------------------------------------------------------
# --- Alias 설� � 로드 ---
ALIAS_DIR="${DOTFILES_BASH_DIR}/alias"
# log_info "Sourcing aliases from: ${ALIAS_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${ALIAS_DIR}/"*.bash; do
    safe_source "$f" "Alias file not found"
done
# ------------------------------------------------------------------

# --- � 플리케이션별 설� � 로드 ---
APP_DIR="${DOTFILES_BASH_DIR}/app"
# log_info "Sourcing application settings from: ${APP_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${APP_DIR}/"*.bash; do
    safe_source "$f" "Application setting file not found"
done

# --- � 플리케이션별 설� � 로드 ---
UTIL_DIR="${DOTFILES_BASH_DIR}/util"
# log_info "Sourcing application settings from: ${APP_DIR}" # 스피너 사용 시 이 메시지는 생략
for f in "${UTIL_DIR}/"*.bash; do
    safe_source "$f" "Utility setting file not found"
done

# ------------------------------------------------------------------
# --- 모�  파일 로드 완료 후 스피너 중지 및 요약 � �보 ---
log_progress_stop "Dotfiles configuration loaded successfully. (Total files sourced: ${SOURCED_FILES_COUNT})"
print_bash_config_loaded

# --- WSL2 한글 입력 설정 (자동 추가됨) ---
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DefaultIMModule=fcitx
# fcitx가 아직 실행되지 않았다면 시작 (선택 사항이지만 권장)
if ! pgrep -x fcitx >/dev/null; then
    fcitx-autostart &>/dev/null
fi
# --- WSL2 한글 입력 설정 끝 ---

