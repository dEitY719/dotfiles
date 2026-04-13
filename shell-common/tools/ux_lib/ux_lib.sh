#!/bin/sh

# ~/dotfiles/shell-common/tools/ux_lib/ux_lib.sh
# Central UX library for consistent styling across all dotfiles scripts
# POSIX-compliant with bash/zsh-specific optimizations where needed

# This library provides:
# - Semantic color definitions (use UX_PRIMARY instead of 'blue')
# - Standard output functions (ux_header, ux_success, ux_error, etc.)
# - Progress indicators (spinners)
# - Interactive prompts (confirmations)
# - Table formatting helpers

# =============================================================================
# Shell Detection
# =============================================================================

_UX_IS_BASH=false
_UX_IS_ZSH=false

if [ -n "$BASH_VERSION" ]; then
    _UX_IS_BASH=true
elif [ -n "$ZSH_VERSION" ]; then
    _UX_IS_ZSH=true
fi

# =============================================================================
# Color Definitions (tput-based with fallback to empty strings)
# =============================================================================

_UX_DISABLE_ANSI=false
if [ "${DOTFILES_TEST_MODE:-}" = "1" ] || [ "${TERM:-}" = "dumb" ] || [ -n "${NO_COLOR:-}" ]; then
    _UX_DISABLE_ANSI=true
fi

# Text styles
export UX_BOLD
if $_UX_DISABLE_ANSI; then
    UX_BOLD=""
else
    UX_BOLD=$(tput bold 2>/dev/null || echo "")
fi
export UX_DIM
if $_UX_DISABLE_ANSI; then
    UX_DIM=""
else
    UX_DIM=$(tput dim 2>/dev/null || echo "")
fi
export UX_RESET
if $_UX_DISABLE_ANSI; then
    UX_RESET=""
else
    UX_RESET=$(tput sgr0 2>/dev/null || echo "")
fi

# Determine directory where this script is located
# This allows the library to be self-contained and portable
if $_UX_IS_BASH; then
    UX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif $_UX_IS_ZSH; then
    UX_LIB_DIR="${0:h}"
else
    # POSIX sh compatible way (use -- to prevent "-bash" from being interpreted as option)
    UX_LIB_DIR="$(cd "$(dirname -- "$0")" && pwd)"
fi

# =============================================================================
# DEFENSE: Safe script name extraction (prevents $0 flag injection attacks)
# =============================================================================
# This function is used by all scripts to safely extract script name from $0
# Problem: When sourcing with flags like "bash -i -l", $0 becomes "-i" or "-l"
# This caused "basename -i" → error: invalid option -- 'i'
# Solution: Use parameter expansion + validation (no external commands)
# =============================================================================
ux_get_safe_script_name() {
    # Extract filename portion using parameter expansion (POSIX-safe)
    local _fname="${0##*/}"

    # Validation: if filename starts with -, it's from shell flags (sourced context)
    # Return empty in that case (signals: don't treat as direct execution)
    if [ "${_fname#-}" = "$_fname" ]; then
        echo "$_fname"
    fi
}

# Semantic colors (named by purpose, not appearance)
# Use these instead of direct color codes for consistency
export UX_PRIMARY
if $_UX_DISABLE_ANSI; then
    UX_PRIMARY=""
else
    UX_PRIMARY=$(tput setaf 4 2>/dev/null || echo "") # blue - headers, titles
fi
export UX_SUCCESS
if $_UX_DISABLE_ANSI; then
    UX_SUCCESS=""
else
    UX_SUCCESS=$(tput setaf 2 2>/dev/null || echo "") # green - success states
fi
export UX_WARNING
if $_UX_DISABLE_ANSI; then
    UX_WARNING=""
else
    UX_WARNING=$(tput setaf 3 2>/dev/null || echo "") # yellow - warnings
fi
export UX_ERROR
if $_UX_DISABLE_ANSI; then
    UX_ERROR=""
else
    UX_ERROR=$(tput setaf 1 2>/dev/null || echo "") # red - errors
fi
export UX_INFO
if $_UX_DISABLE_ANSI; then
    UX_INFO=""
else
    UX_INFO=$(tput setaf 6 2>/dev/null || echo "") # cyan - info messages
fi
export UX_MUTED
if $_UX_DISABLE_ANSI; then
    UX_MUTED=""
else
    UX_MUTED=$(tput setaf 8 2>/dev/null || echo "") # gray - secondary info
fi

# =============================================================================
# Standard Output Functions
# =============================================================================

# Display a prominent header with box drawing
# Usage: ux_header "My Title"
ux_header() {
    local text="$1"
    local width=60

    echo ""
    printf "%s%s╔══════════════════════════════════════════════════════════════╗%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    printf "%s%s║%s %-60s %s%s║%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}" "$text" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    printf "%s%s╚══════════════════════════════════════════════════════════════╝%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    echo ""
}

# Display a section header with underline
# Usage: ux_section "Section Name"
ux_section() {
    local title="$1"
    echo ""
    printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$title" "${UX_RESET}"

    if $_UX_IS_BASH; then
        printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$(printf '─%.0s' $(seq 1 ${#title}))" "${UX_RESET}"
    elif $_UX_IS_ZSH; then
        printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$(printf '─%.0s' {1..${#title}})" "${UX_RESET}"
    else
        # POSIX fallback using awk
        printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$(printf '─%.0s' $(seq 1 ${#title}))" "${UX_RESET}"
    fi
}

# Display a success message with checkmark
# Usage: ux_success "Operation completed"
ux_success() {
    printf "%s%s✅%s %s\n" "${UX_BOLD}" "${UX_SUCCESS}" "${UX_RESET}" "$1"
}

# Display an error message with X mark (to stderr)
# Usage: ux_error "Something went wrong"
ux_error() {
    printf "%s%s❌%s %s\n" "${UX_BOLD}" "${UX_ERROR}" "${UX_RESET}" "$1" >&2
}

# Display a warning message with warning sign
# Usage: ux_warning "This might cause issues"
ux_warning() {
    printf "%s%s⚠️%s  %s\n" "${UX_BOLD}" "${UX_WARNING}" "${UX_RESET}" "$1"
}

# Display an info message with info icon
# Usage: ux_info "For your information"
ux_info() {
    printf "%s%sℹ️%s  %s\n" "${UX_BOLD}" "${UX_INFO}" "${UX_RESET}" "$1"
}

# Display a step indicator
# Usage: ux_step 1 "First step"
ux_step() {
    local step_num="$1"
    local step_text="$2"
    printf "%s%s[%s]%s %s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$step_num" "${UX_RESET}" "$step_text"
}

# =============================================================================
# Progress Indicators
# =============================================================================

# Show a spinner while a background process runs
# Usage: ux_spinner <pid> "Loading message"
ux_spinner() {
    local pid=$1
    local message="${2:-Processing}"
    local delay=0.1
    local frames='⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏'
    local i=0

    # Hide cursor
    tput civis 2>/dev/null || true

    # Safety: Restore cursor on Ctrl+C or exit
    trap 'tput cnorm 2>/dev/null || true' EXIT INT TERM

    while kill -0 "$pid" 2>/dev/null; do
        # Get frame character for current index
        local frame_char
        if $_UX_IS_BASH; then
            frame_char=$(echo "$frames" | cut -d' ' -f$((i+1)))
        elif $_UX_IS_ZSH; then
            frame_char=$(echo "$frames" | cut -d' ' -f$((i+2)))
        else
            frame_char=$(echo "$frames" | cut -d' ' -f$((i+1)))
        fi

        printf "\r%s%s%s %s..." "${UX_INFO}" "$frame_char" "${UX_RESET}" "$message"

        if $_UX_IS_BASH; then
            i=$(((i + 1) % 10))
        elif $_UX_IS_ZSH; then
            i=$(( (i + 1) % 10 ))
        else
            i=$(((i + 1) % 10))
        fi

        sleep "$delay"
    done

    # Show cursor
    tput cnorm 2>/dev/null || true
    trap - EXIT INT TERM

    # Clear the line and show completion
    printf "\r%s✅%s %s... Done!\n" "${UX_SUCCESS}" "${UX_RESET}" "$message"
}

# Run a command with spinner
# Usage: ux_with_spinner "Message" command args...
ux_with_spinner() {
    local message="$1"
    shift
    local cmd="$@"

    # Create temp file for output
    local temp_log="/tmp/ux_spinner_$$.log"

    # Run command in background
    eval "$cmd" &>"$temp_log" &
    local pid=$!

    # Show spinner
    ux_spinner "$pid" "$message"

    # Check result
    wait "$pid"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        ux_success "$message completed"
    else
        ux_error "$message failed (exit code: $exit_code)"
        if [ -s "$temp_log" ]; then
            echo "${UX_MUTED}--- Error output ---${UX_RESET}" >&2
            cat "$temp_log" >&2
            echo "${UX_MUTED}-------------------${UX_RESET}" >&2
        fi
    fi

    rm -f "$temp_log"
    return $exit_code
}

# Run a command with a Python-based Rich progress bar or a basic spinner fallback
# Usage: ux_with_progress "Message" command args...
ux_with_progress() {
    local message="$1"
    shift
    local cmd="$@"
    local progress_script="${UX_LIB_DIR}/ux_progress.py"

    # Check if Python + rich is available
    if command -v python3 &>/dev/null && python3 -c "import rich" &>/dev/null; then
        # Use rich Python progress bar
        python3 "$progress_script" "$message" "$cmd"
        return $?
    else
        # Fallback to basic spinner
        ux_warning "Python 'rich' not found. Falling back to basic spinner."
        ux_with_spinner "$message" "$cmd"
        return $?
    fi
}

# Simple progress dots (for lighter feedback)
# Usage: ux_progress_dots <pid>
ux_progress_dots() {
    local pid=$1
    while kill -0 "$pid" 2>/dev/null; do
        printf "."
        sleep 0.5
    done
    echo ""
}

# =============================================================================
# Interactive Prompts
# =============================================================================

# Ask for confirmation (yes/no)
# Usage: if ux_confirm "Are you sure?" "n"; then ... fi
# Second argument is default: "y" or "n"
#
# Prompts are written to stderr so they remain visible when the caller
# captures stdout (e.g., inside $(...)). Return value is conveyed via
# exit code, so no stdout pollution either way.
ux_confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        printf "%s❓%s %s [Y/n]: " "${UX_WARNING}" "${UX_RESET}" "$prompt" >&2
    else
        printf "%s❓%s %s [y/N]: " "${UX_WARNING}" "${UX_RESET}" "$prompt" >&2
    fi

    read -r response
    response="${response:-$default}"

    case "$response" in
        [Yy]) return 0 ;;
        *) return 1 ;;
    esac
}

# Ask for text input with validation
# Usage: result=$(ux_input "Enter name:" "^[a-zA-Z]+$")
#
# The prompt is written to stderr so it remains visible when the caller
# captures stdout with $(...). The user's validated response is written
# to stdout — that is the function's return value. Matches bash's own
# `read -p` convention, which also routes the prompt to stderr.
ux_input() {
    local prompt="$1"
    local pattern="${2:-.*}"
    local response

    while true; do
        printf "%s❯%s %s " "${UX_INFO}" "${UX_RESET}" "$prompt" >&2
        read -r response

        if echo "$response" | grep -qE "$pattern"; then
            echo "$response"
            return 0
        else
            ux_error "Invalid input. Please try again."
        fi
    done
}

# Display an interactive menu using a Python script or basic fallback
# Usage: result=$(ux_menu "Select option:" "Option 1" "Option 2" "Option 3")
# Returns 0-based index or empty string if cancelled/failed
ux_menu() {
    local title="$1"
    shift
    local options="$@"
    local menu_script="${UX_LIB_DIR}/ux_menu.py"

    # Check if Python + rich is available
    if command -v python3 &>/dev/null && python3 -c "import rich" &>/dev/null && command -v jq &>/dev/null; then
        # Use rich Python menu
        local config
        config=$(jq -n \
            --arg title "$title" \
            --argjson options "$(printf '%s\n' $options | jq -R . | jq -s .)" \
            '{title: $title, options: $options, allow_cancel: true}')

        local result
        # Pass config as argument, ensuring stdin is connected to tty for interaction
        result=$(python3 "$menu_script" "$config" </dev/tty)
        local py_exit_code=$?

        # Check Python script's exit code for cancellation
        if [ $py_exit_code -eq 0 ]; then
            echo "$result"
        else
            # User cancelled or invalid input
            return 1
        fi
    else
        # Fallback to basic menu
        ux_warning "Python 'rich' or 'jq' not found. Falling back to basic menu."
        echo ""
        ux_section "$title"
        local i=1
        for opt in $options; do
            echo "  ${UX_PRIMARY}$i)${UX_RESET} $opt"
            i=$((i + 1))
        done
        echo "  ${UX_MUTED}0) Cancel${UX_RESET}"
        echo ""
        printf "%s❯%s Select: " "${UX_INFO}" "${UX_RESET}"
        read -r choice

        if [ -n "$choice" ] && [ "$choice" -ge 1 ] && [ "$choice" -le $i ]; then
            echo $((choice - 1))
        else
            ux_info "Cancelled."
            return 1
        fi
    fi
}

# =============================================================================
# Table Formatting
# =============================================================================

# Display a table row with 3 columns
# Usage: ux_table_row "Column 1" "Column 2" "Column 3"
ux_table_row() {
    local col1="$1"
    local col2="$2"
    local col3="${3:-}"

    if [ -n "$col3" ]; then
        printf "  ${UX_PRIMARY}%-20s${UX_RESET} ${UX_MUTED}│${UX_RESET} %-30s ${UX_MUTED}│${UX_RESET} %s\n" "$col1" "$col2" "$col3"
    else
        printf "  ${UX_PRIMARY}%-20s${UX_RESET} ${UX_MUTED}:${UX_RESET} %s\n" "$col1" "$col2"
    fi
}

# Display table header
# Usage: ux_table_header "Column 1" "Column 2" "Column 3"
ux_table_header() {
    local col1="$1"
    local col2="$2"
    local col3="${3:-}"

    if [ -n "$col3" ]; then
        printf "  ${UX_BOLD}%-20s${UX_RESET} ${UX_MUTED}│${UX_RESET} ${UX_BOLD}%-30s${UX_RESET} ${UX_MUTED}│${UX_RESET} ${UX_BOLD}%s${UX_RESET}\n" "$col1" "$col2" "$col3"

        if $_UX_IS_BASH; then
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..80})"
        elif $_UX_IS_ZSH; then
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..80})"
        else
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 80))"
        fi
    else
        printf "  ${UX_BOLD}%-20s${UX_RESET}   ${UX_BOLD}%s${UX_RESET}\n" "$col1" "$col2"

        if $_UX_IS_BASH; then
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..60})"
        elif $_UX_IS_ZSH; then
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..60})"
        else
            printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 60))"
        fi
    fi
}

# =============================================================================
# List Formatting
# =============================================================================

# Display a bullet point
# Usage: ux_bullet "Item description"
ux_bullet() {
    printf "  ${UX_PRIMARY}◆${UX_RESET} %s\n" "$1"
}

# Display a second-level bullet point (deeper indentation + alternate bullet)
# Usage: ux_bullet_sub "Nested item description"
# Old style: ◦
ux_bullet_sub() {
    printf "    ${UX_INFO}•${UX_RESET} %s\n" "$1"
}

# Display a numbered item
# Usage: ux_numbered 1 "First item"
ux_numbered() {
    local num="$1"
    local text="$2"
    printf "  ${UX_PRIMARY}%2d.${UX_RESET} %s\n" "$num" "$text"
}

# =============================================================================
# Dividers and Spacing
# =============================================================================

# Print a horizontal divider
# Usage: ux_divider
ux_divider() {
    local width="${1:-60}"

    if $_UX_IS_BASH; then
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 "$width"))"
    elif $_UX_IS_ZSH; then
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..$width})"
    else
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 "$width"))"
    fi
}

# Print a thick divider
# Usage: ux_divider_thick
ux_divider_thick() {
    local width="${1:-60}"

    if $_UX_IS_BASH; then
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '═%.0s' $(seq 1 "$width"))"
    elif $_UX_IS_ZSH; then
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '═%.0s' {1..$width})"
    else
        printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '═%.0s' $(seq 1 "$width"))"
    fi
}

# =============================================================================
# Error Handling
# =============================================================================

# Standard error handler for use with trap
# Usage: trap 'ux_handle_error ${LINENO} "${FUNCNAME[0]}"' ERR
ux_handle_error() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local func_name="${2:-script}"

    ux_error "Error in ${func_name} at line ${line_no} (exit code: ${exit_code})"
    return "$exit_code"
}

# Enable error trapping for strict mode
# Usage: ux_enable_error_trap (call at start of function)
ux_enable_error_trap() {
    set -eE
    trap 'ux_handle_error ${LINENO} "${FUNCNAME[0]}"' ERR
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if command exists and show appropriate message
# Usage: if ux_require "docker"; then ... fi
ux_require() {
    local tool_name="$1"
    local msg="${2:-$tool_name is required but not installed}"

    if ! command -v "$tool_name" &>/dev/null; then
        ux_error "$msg"
        return 1
    fi
    return 0
}

# Show usage help template
# Usage: ux_usage "command_name" "arg1 arg2" "Description of command"
ux_usage() {
    local cmd_name="$1"
    local args="$2"
    local description="${3:-}"

    ux_section "Usage"
    echo "  ${UX_SUCCESS}$cmd_name${UX_RESET} ${UX_MUTED}$args${UX_RESET}"

    if [ -n "$description" ]; then
        echo ""
        echo "  $description"
    fi
    echo ""
}

# =============================================================================
# Migration Helpers
# =============================================================================

# Check if function is using old color style (for migration tracking)
# This is a helper for developers, not for end users
ux_check_old_style() {
    local func_name="$1"

    if type "$func_name" 2>/dev/null | grep -q 'tput bold'; then
        ux_warning "Function '$func_name' still uses old color definitions"
        return 1
    fi
    return 0
}

# =============================================================================
# Log Filtering
# =============================================================================

# Filter logs and colorize based on keywords (ERROR, WARN, INFO)
# Usage: some_command_producing_logs | ux_filter_logs "custom_pattern"
ux_filter_logs() {
    local pattern="${1:-ERROR|WARN}" # Default pattern to highlight
    local color_error="${UX_ERROR}"
    local color_warn="${UX_WARNING}"
    local color_info="${UX_INFO}"
    local reset="${UX_RESET}"

    while IFS= read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            echo "${color_error}${line}${reset}"
        elif echo "$line" | grep -q "WARN"; then
            echo "${color_warn}${line}${reset}"
        elif echo "$line" | grep -q "INFO"; then
            echo "${color_info}${line}${reset}"
        else
            echo "$line"
        fi
    done
}
