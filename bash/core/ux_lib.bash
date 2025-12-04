#!/bin/bash

# ~/dotfiles/bash/core/ux_lib.bash
# Central UX library for consistent styling across all dotfiles scripts

# This library provides:
# - Semantic color definitions (use UX_PRIMARY instead of 'blue')
# - Standard output functions (ux_header, ux_success, ux_error, etc.)
# - Progress indicators (spinners)
# - Interactive prompts (confirmations)
# - Table formatting helpers

# =============================================================================
# Color Definitions (tput-based with fallback to empty strings)
# =============================================================================

# Text styles
export UX_BOLD=$(tput bold 2>/dev/null || echo "")
export UX_DIM=$(tput dim 2>/dev/null || echo "")
export UX_RESET=$(tput sgr0 2>/dev/null || echo "")

# Semantic colors (named by purpose, not appearance)
# Use these instead of direct color codes for consistency
export UX_PRIMARY=$(tput setaf 4 2>/dev/null || echo "")      # blue - headers, titles
export UX_SUCCESS=$(tput setaf 2 2>/dev/null || echo "")      # green - success states
export UX_WARNING=$(tput setaf 3 2>/dev/null || echo "")      # yellow - warnings
export UX_ERROR=$(tput setaf 1 2>/dev/null || echo "")        # red - errors
export UX_INFO=$(tput setaf 6 2>/dev/null || echo "")         # cyan - info messages
export UX_MUTED=$(tput setaf 8 2>/dev/null || echo "")        # gray - secondary info

# =============================================================================
# Standard Output Functions
# =============================================================================

# Display a prominent header with box drawing
# Usage: ux_header "My Title"
ux_header() {
    local text="$1"
    local width=60

    echo ""
    echo "${UX_BOLD}${UX_PRIMARY}╔══════════════════════════════════════════════════════════════╗${UX_RESET}"
    printf "${UX_BOLD}${UX_PRIMARY}║${UX_RESET} %-60s ${UX_BOLD}${UX_PRIMARY}║${UX_RESET}\n" "$text"
    echo "${UX_BOLD}${UX_PRIMARY}╚══════════════════════════════════════════════════════════════╝${UX_RESET}"
    echo ""
}

# Display a section header with underline
# Usage: ux_section "Section Name"
ux_section() {
    local title="$1"
    echo ""
    echo "${UX_BOLD}${UX_PRIMARY}$title${UX_RESET}"
    printf "${UX_BOLD}${UX_PRIMARY}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 ${#title}))"
}

# Display a success message with checkmark
# Usage: ux_success "Operation completed"
ux_success() {
    echo "${UX_BOLD}${UX_SUCCESS}✅${UX_RESET} $1"
}

# Display an error message with X mark (to stderr)
# Usage: ux_error "Something went wrong"
ux_error() {
    echo "${UX_BOLD}${UX_ERROR}❌${UX_RESET} $1" >&2
}

# Display a warning message with warning sign
# Usage: ux_warning "This might cause issues"
ux_warning() {
    echo "${UX_BOLD}${UX_WARNING}⚠️${UX_RESET}  $1"
}

# Display an info message with info icon
# Usage: ux_info "For your information"
ux_info() {
    echo "${UX_BOLD}${UX_INFO}ℹ️${UX_RESET}  $1"
}

# Display a step indicator
# Usage: ux_step 1 "First step"
ux_step() {
    local step_num="$1"
    local step_text="$2"
    echo "${UX_BOLD}${UX_PRIMARY}[$step_num]${UX_RESET} $step_text"
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
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    # Hide cursor
    tput civis 2>/dev/null || true

    # Safety: Restore cursor on Ctrl+C or exit
    trap 'tput cnorm 2>/dev/null || true' EXIT INT TERM

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${UX_INFO}${frames[$i]}${UX_RESET} $message..."
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep "$delay"
    done

    # Show cursor
    tput cnorm 2>/dev/null || true
    trap - EXIT INT TERM

    # Clear the line and show completion
    printf "\r${UX_SUCCESS}✅${UX_RESET} $message... Done!\n"
}

# Run a command with spinner
# Usage: ux_with_spinner "Message" command args...
ux_with_spinner() {
    local message="$1"
    shift
    local cmd=("$@")

    # Create temp file for output
    local temp_log="/tmp/ux_spinner_$$.log"

    # Run command in background
    "${cmd[@]}" &> "$temp_log" &
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
ux_confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        printf "${UX_WARNING}❓${UX_RESET} $prompt [Y/n]: "
    else
        printf "${UX_WARNING}❓${UX_RESET} $prompt [y/N]: "
    fi

    read -r response
    response="${response:-$default}"

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Ask for text input with validation
# Usage: result=$(ux_input "Enter name:" "^[a-zA-Z]+$")
ux_input() {
    local prompt="$1"
    local pattern="${2:-.*}"
    local response

    while true; do
        printf "${UX_INFO}❯${UX_RESET} $prompt "
        read -r response

        if [[ "$response" =~ $pattern ]]; then
            echo "$response"
            return 0
        else
            ux_error "Invalid input. Please try again."
        fi
    done
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
        printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..80})"
    else
        printf "  ${UX_BOLD}%-20s${UX_RESET}   ${UX_BOLD}%s${UX_RESET}\n" "$col1" "$col2"
        printf "  ${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' {1..60})"
    fi
}

# =============================================================================
# List Formatting
# =============================================================================

# Display a bullet point
# Usage: ux_bullet "Item description"
ux_bullet() {
    echo "  ${UX_PRIMARY}•${UX_RESET} $1"
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
    printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '─%.0s' $(seq 1 "$width"))"
}

# Print a thick divider
# Usage: ux_divider_thick
ux_divider_thick() {
    local width="${1:-60}"
    printf "${UX_MUTED}%s${UX_RESET}\n" "$(printf '═%.0s' $(seq 1 "$width"))"
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
    local cmd="$1"
    local msg="${2:-$cmd is required but not installed}"

    if ! command -v "$cmd" &> /dev/null; then
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
