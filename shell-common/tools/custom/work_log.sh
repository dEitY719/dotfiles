#!/bin/bash
# work_log.sh - Manual work log recording tool
# Companion to post-commit hook for tracking non-development work
# Records work entries to ~/work_log.txt in standardized format
#
# Usage:
#   work-log add [JIRA-KEY] [--type TYPE] [--category CATEGORY] [--time TIME]
#   work-log list [--count N] [--today]
#   work-log help

set -eE

# =============================================================================
# Script Setup
# =============================================================================

# Determine script directory, resolving symlinks
if [ -n "$BASH_VERSION" ]; then
    # Resolve symlinks to get actual script location
    _WORK_LOG_SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$_WORK_LOG_SOURCE" ]; do
        _WORK_LOG_DIR="$(cd -P "$(dirname "$_WORK_LOG_SOURCE")" && pwd)"
        _WORK_LOG_SOURCE="$(readlink "$_WORK_LOG_SOURCE")"
        [[ $_WORK_LOG_SOURCE != /* ]] && _WORK_LOG_SOURCE="$_WORK_LOG_DIR/$_WORK_LOG_SOURCE"
    done
    WORK_LOG_DIR="$(cd -P "$(dirname "$_WORK_LOG_SOURCE")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    WORK_LOG_DIR="${0:A:h}"  # :A means absolute, resolving symlinks
else
    # POSIX fallback - resolve symlinks
    _WORK_LOG_SOURCE="$0"
    while [ -h "$_WORK_LOG_SOURCE" ]; do
        _WORK_LOG_DIR="$(cd "$(dirname "$_WORK_LOG_SOURCE")" && pwd)"
        _WORK_LOG_SOURCE="$(readlink "$_WORK_LOG_SOURCE")"
        [ -z "${_WORK_LOG_SOURCE##/*}" ] || _WORK_LOG_SOURCE="$_WORK_LOG_DIR/$_WORK_LOG_SOURCE"
    done
    WORK_LOG_DIR="$(cd "$(dirname "$_WORK_LOG_SOURCE")" && pwd)"
fi

# Find and source ux_lib
UX_LIB_PATH="${WORK_LOG_DIR}/../ux_lib/ux_lib.sh"
if [ -f "$UX_LIB_PATH" ]; then
    source "$UX_LIB_PATH"
else
    echo "Error: ux_lib.sh not found at $UX_LIB_PATH" >&2
    exit 1
fi

# Work log file location
# Absolute path to dotfiles managed work_log.txt (allows git tracking + multi-PC sync)
# Falls back to ~/work_log.txt if symlink not configured
WORK_LOG_DIR_DATA="${WORK_LOG_DIR}/../data"
if [ -f "${WORK_LOG_DIR_DATA}/work_log.txt" ]; then
    WORK_LOG_FILE="${WORK_LOG_DIR_DATA}/work_log.txt"
else
    # Fallback if dotfiles structure is different
    WORK_LOG_FILE="${HOME}/work_log.txt"
fi

# =============================================================================
# Validation Functions (from post-commit hook)
# =============================================================================

# Validate Jira key format: [SWINNOTEAM-903], [PROJ-245], etc.
validate_jira_key() {
    local key="$1"
    # Support optional brackets and case-insensitive
    # Pattern: [A-Z][A-Z0-9]*-[0-9]+
    if echo "$key" | grep -iq '^\[*[A-Z][A-Z0-9]*-[0-9]\+\]*$'; then
        # Remove brackets if present and return normalized form
        echo "$key" | sed 's/\[//g;s/\]//g' | tr '[:lower:]' '[:upper:]'
        return 0
    fi
    return 1
}

# Validate time format: 2.5, 2.5h, 4h
validate_time() {
    local time="$1"
    if echo "$time" | grep -qE '^[0-9]+(\.[0-9]+)?h?$'; then
        # Normalize: remove trailing 'h' if present
        echo "$time" | sed 's/h$//'
        return 0
    fi
    return 1
}

# Validate type: coordination, assessment, approval, meeting (non-development work only)
validate_type() {
    local type="$1"
    case "$type" in
        coordination|assessment|approval|meeting)
            echo "$type"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate category
validate_category() {
    local cat="$1"
    case "$cat" in
        Testing|Infrastructure|Documentation|Performance|Security|Communication|Coordination|Training|Other)
            echo "$cat"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Core Functions
# =============================================================================

# Record a work log entry
work_log_record() {
    local jira_key="$1"
    local type="$2"
    local category="$3"
    local time_spent="$4"

    # Get timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create log entry (same format as post-commit hook)
    local log_entry="[$timestamp] [$jira_key] | $type | $category | ${time_spent}h | manual"

    # Append to work log file
    if echo "$log_entry" >> "$WORK_LOG_FILE" 2>/dev/null; then
        # Also add category metadata
        echo "  └─ Category: $category" >> "$WORK_LOG_FILE" 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Interactive mode: prompt for each field
work_log_add_interactive() {
    local jira_key=""
    local type=""
    local category=""
    local time_spent=""

    # Prompt for Jira key
    while [ -z "$jira_key" ]; do
        printf "%s❓%s Jira key (e.g., SWINNOTEAM-903): " "${UX_WARNING}" "${UX_RESET}"
        read -r jira_input
        if [ -z "$jira_input" ]; then
            ux_error "Jira key cannot be empty"
            continue
        fi
        jira_key=$(validate_jira_key "$jira_input") && {
            ux_success "Jira key: $jira_key"
        } || {
            ux_error "Invalid Jira key format. Expected: [A-Z][A-Z0-9]*-[0-9]+"
            jira_key=""
        }
    done

    # Prompt for type
    while [ -z "$type" ]; do
        printf "%s❓%s Type (coordination/assessment/approval/meeting): " "${UX_WARNING}" "${UX_RESET}"
        read -r type_input
        type=$(validate_type "$type_input") && {
            ux_success "Type: $type"
        } || {
            ux_error "Invalid type. Choose: coordination, assessment, approval, or meeting"
            type=""
        }
    done

    # Prompt for category
    while [ -z "$category" ]; do
        printf "%s❓%s Category (Testing/Infrastructure/Documentation/Communication/Training/Other): " "${UX_WARNING}" "${UX_RESET}"
        read -r cat_input
        category=$(validate_category "$cat_input") && {
            ux_success "Category: $category"
        } || {
            ux_error "Invalid category"
            category=""
        }
    done

    # Prompt for time
    while [ -z "$time_spent" ]; do
        printf "%s❓%s Time spent (e.g., 2.5h or 2.5): " "${UX_WARNING}" "${UX_RESET}"
        read -r time_input
        time_spent=$(validate_time "$time_input") && {
            ux_success "Time: ${time_spent}h"
        } || {
            ux_error "Invalid time format. Use numeric format: 2.5, 2.5h, or 4h"
            time_spent=""
        }
    done

    # Record the entry
    if work_log_record "$jira_key" "$type" "$category" "$time_spent"; then
        ux_success "Work log entry recorded"
        printf "\n%s[%s] [$jira_key] | $type | $category | ${time_spent}h | manual%s\n" \
            "${UX_MUTED}" "$(date '+%Y-%m-%d %H:%M:%S')" "${UX_RESET}"
    else
        ux_error "Failed to write to $WORK_LOG_FILE"
        return 1
    fi
}

# Argument mode: parse command-line flags
work_log_add_args() {
    local jira_key=""
    local type=""
    local category=""
    local time_spent=""

    # Parse positional and optional arguments
    local i=1
    while [ $i -le $# ]; do
        case "${!i}" in
            --type|-t)
                i=$((i+1))
                type="${!i}"
                ;;
            --category|-c)
                i=$((i+1))
                category="${!i}"
                ;;
            --time|-T)
                i=$((i+1))
                time_spent="${!i}"
                ;;
            -*)
                ux_error "Unknown option: ${!i}"
                return 1
                ;;
            *)
                if [ -z "$jira_key" ]; then
                    jira_key="${!i}"
                fi
                ;;
        esac
        i=$((i+1))
    done

    # Validate all required fields are present
    if [ -z "$jira_key" ] || [ -z "$type" ] || [ -z "$category" ] || [ -z "$time_spent" ]; then
        ux_error "Missing required arguments"
        ux_info "Usage: work-log add JIRA-KEY --type TYPE --category CATEGORY --time TIME"
        ux_bullet "Example: work-log add SWINNOTEAM-903 -t coordination -c Communication -T 2.5h"
        return 1
    fi

    # Validate each field
    jira_key=$(validate_jira_key "$jira_key") || {
        ux_error "Invalid Jira key: $jira_key"
        return 1
    }
    type=$(validate_type "$type") || {
        ux_error "Invalid type: $type"
        return 1
    }
    category=$(validate_category "$category") || {
        ux_error "Invalid category: $category"
        return 1
    }
    time_spent=$(validate_time "$time_spent") || {
        ux_error "Invalid time format: $time_spent"
        return 1
    }

    # Record the entry
    if work_log_record "$jira_key" "$type" "$category" "$time_spent"; then
        ux_success "Work log entry recorded"
        printf "\n%s[%s] [$jira_key] | $type | $category | ${time_spent}h | manual%s\n" \
            "${UX_MUTED}" "$(date '+%Y-%m-%d %H:%M:%S')" "${UX_RESET}"
    else
        ux_error "Failed to write to $WORK_LOG_FILE"
        return 1
    fi
}

# Display help for work-log list command
work_log_list_help() {
    ux_header "work-log list - Display work log entries"

    ux_section "Usage"
    ux_bullet "work-log list              - Show last 10 entries"
    ux_bullet "work-log list --count N    - Show last N entries"
    ux_bullet "work-log list --today      - Show today's entries only"
    ux_bullet "work-log list help         - Show this help"

    ux_section "Options"
    ux_numbered 1 "--count N (or -n N)"
    ux_bullet "Display the last N entries from the work log"
    ux_bullet "Default: 10"
    ux_bullet "Example: work-log list --count 20"

    ux_numbered 2 "--today (or -d)"
    ux_bullet "Show only entries from today (YYYY-MM-DD)"
    ux_bullet "Filtered by current date"
    ux_bullet "Example: work-log list --today"

    ux_section "Examples"
    echo "  ${UX_SUCCESS}work-log list${UX_RESET}                    # Last 10 entries"
    echo "  ${UX_SUCCESS}work-log list --count 5${UX_RESET}          # Last 5 entries"
    echo "  ${UX_SUCCESS}work-log list --today${UX_RESET}            # Today's entries"
    echo "  ${UX_SUCCESS}work-log list --count 20 --today${UX_RESET} # Last 20 today's entries"

    ux_section "Output Format"
    ux_bullet "[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | time | source"
    ux_bullet "└─ Category: CategoryName"

    echo ""
    ux_info "Log file: $WORK_LOG_FILE"
}

# List recent work log entries
work_log_list() {
    local count=10
    local today_only=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            help|--help|-h)
                work_log_list_help
                return 0
                ;;
            --count|-n)
                shift
                count="$1"
                ;;
            --today|-d)
                today_only=true
                ;;
            *)
                ux_error "Unknown option: $1"
                echo ""
                work_log_list_help
                return 1
                ;;
        esac
        shift
    done

    # Check if work log file exists
    if [ ! -f "$WORK_LOG_FILE" ]; then
        ux_info "No work log file found at $WORK_LOG_FILE"
        return 0
    fi

    ux_header "Work Log Entries"

    if $today_only; then
        local today=$(date '+%Y-%m-%d')
        ux_section "Today's entries"
        grep "^\[$today" "$WORK_LOG_FILE" | tail -n "$count" || ux_info "No entries for today"
    else
        ux_section "Recent $count entries"
        tail -n $((count * 2)) "$WORK_LOG_FILE"  # Multiply by 2 to account for metadata lines
    fi

    echo ""
    ux_info "Log file: $WORK_LOG_FILE"
}

# Display help for work-log command
work_log_help() {
    ux_header "work-log Command"

    ux_section "Overview"
    ux_bullet "Manual work log recording tool for non-development work"
    ux_bullet "Companion to post-commit hook for development work"
    ux_bullet "All entries are appended to ~/work_log.txt"

    ux_section "Usage"
    ux_bullet "work-log add [JIRA-KEY] [OPTIONS]  - Add a work log entry"
    ux_bullet "work-log list [OPTIONS]            - List recent entries"
    ux_bullet "work-log help                      - Show this help"

    ux_section "Add Command - Interactive Mode"
    ux_numbered 1 "work-log add"
    ux_bullet "System will prompt for Jira key, type, category, and time"

    ux_section "Add Command - Argument Mode"
    ux_numbered 1 "work-log add JIRA-KEY --type TYPE --category CATEGORY --time TIME"

    ux_info "Short options:"
    ux_bullet "-t, --type TYPE          (coordination|assessment|approval|meeting)"
    ux_bullet "-c, --category CATEGORY  (Testing|Infrastructure|Documentation|Communication|Training|Other)"
    ux_bullet "-T, --time TIME          (numeric: 2.5 or 2.5h)"

    echo ""
    ux_step "Example" "Coordination meeting on testing strategy"
    echo "  ${UX_SUCCESS}work-log add SWINNOTEAM-903${UX_RESET} ${UX_MUTED}-t coordination${UX_RESET} ${UX_MUTED}-c Communication${UX_RESET} ${UX_MUTED}-T 2.5h${UX_RESET}"

    ux_section "List Command"
    ux_numbered 1 "work-log list              - Show last 10 entries"
    ux_numbered 2 "work-log list --count 20  - Show last 20 entries"
    ux_numbered 3 "work-log list --today     - Show today's entries"
    ux_info "For detailed list options: ${UX_SUCCESS}work-log list help${UX_RESET}"

    ux_section "Output Format"
    ux_bullet "[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | time | source"
    ux_bullet "└─ Category: CategoryName"

    ux_section "Work Types"
    ux_bullet "coordination  - Team coordination, meetings, planning"
    ux_bullet "assessment    - Code/design reviews, evaluations"
    ux_bullet "approval      - Approval requests, sign-offs"
    ux_bullet "meeting       - Official meetings, presentations"

    ux_section "Categories"
    ux_bullet "Testing, Infrastructure, Documentation, Performance, Security"
    ux_bullet "Communication, Coordination, Training, Other"

    ux_section "Common Tasks"
    ux_bullet "Daily standup:  work-log add [PROJ-XXX] -t meeting -c Communication -T 0.5h"
    ux_bullet "Code review:    work-log add [PROJ-XXX] -t assessment -c Communication -T 1.5h"
    ux_bullet "Team planning:  work-log add [ADMIN-001] -t coordination -c Coordination -T 2h"

    ux_divider
    ux_info "All entries are appended to: ${UX_SUCCESS}${WORK_LOG_FILE}${UX_RESET}"
    ux_info "Use these entries for weekly reports and time tracking"
}

# =============================================================================
# Main Dispatcher
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        add)
            if [ $# -eq 0 ]; then
                # Interactive mode
                work_log_add_interactive
            elif echo "$1" | grep -iq '^\[*[A-Z][A-Z0-9]*-[0-9]\+\]*$'; then
                # Argument mode with Jira key as first argument
                work_log_add_args "$@"
            else
                # Try to parse as flags (assume first flag-based argument)
                work_log_add_args "$@"
            fi
            ;;
        list)
            work_log_list "$@"
            ;;
        help|--help|-h|"")
            work_log_help
            ;;
        *)
            ux_error "Unknown command: $command"
            echo ""
            work_log_help
            return 1
            ;;
    esac
}

# Run main function only when executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
