#!/bin/bash

# ~/dotfiles/bash/core/beauty_log.bash

# This script defines functions to initialize logging for other scripts.

# Fallback basic logging functions (if actual log_util.bash is not found)

_fallback_log_error() { echo "ERROR: $1" >&2; }

_fallback_log_info() { echo "INFO: $1"; }

_fallback_log_critical() {
	echo "CRITICAL ERROR: $1" >&2
	exit 1
}

# Function to initialize logging by sourcing log_util.bash

# If log_util.bash is not found, it sets up basic fallback logging.

init_logging() {

	local dotfiles_bash_dir="${1}" # Pass DOTFILES_BASH_DIR as an argument

	local log_util_path="${dotfiles_bash_dir}/util/log_util.bash"

	if [[ -f "${log_util_path}" ]]; then

		# shellcheck disable=SC1090

		source "${log_util_path}"

	else

		echo "ERROR: log_util.bash not found at ${log_util_path}. Using fallback logging." >&2

		# Assign fallback functions to global log function names

		log_error() { _fallback_log_error "$@"; }

		log_info() { _fallback_log_info "$@"; }

		log_critical() { _fallback_log_critical "$@"; }

	fi

}
