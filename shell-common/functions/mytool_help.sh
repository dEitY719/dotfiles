#!/bin/sh
# shell-common/functions/mytool_help.sh
# mytool Help - shared between bash and zsh
# Lists personal utility commands from shell-common/tools/custom/

# Helper: Extract description from script file (first 10 lines)
_extract_tool_description() {
    local script="$1"

    # Use head to get first 10 lines, then find first meaningful comment
    head -10 "$script" 2>/dev/null | grep "^#" | grep -v "#!/" | grep -v "^#[[:space:]]*$" | head -1 | \
        sed 's/^#[[:space:]]*//' | cut -c1-30
}

mytool_help() {
    ux_header "MyTool - Custom Utility Scripts"

    ux_section "Available Custom Tools"
    ux_info "Executable utility scripts in shell-common/tools/custom/"
    echo ""

    # Check if SHELL_COMMON is set
    if [ -z "$SHELL_COMMON" ]; then
        ux_warning "SHELL_COMMON environment variable not set"
        return 1
    fi

    # List all .sh files in custom tools directory
    local custom_dir="${SHELL_COMMON}/tools/custom"
    if [ ! -d "$custom_dir" ]; then
        ux_error "Custom tools directory not found: $custom_dir"
        return 1
    fi

    # Find and display all .sh files
    local count=0
    for script in $(find "$custom_dir" -name "*.sh" -type f | sort); do
        local tool_name=$(basename "$script" .sh)
        local desc=$(_extract_tool_description "$script")

        # Format: tool-name | description (max 30 chars)
        printf "  ${UX_SUCCESS}%-25s${UX_RESET}  ${UX_MUTED}|${UX_RESET}  %s\n" "$tool_name" "$desc"
        count=$((count + 1))
    done

    echo ""
    ux_info "Total: $count custom tools available"
    echo ""

    ux_section "Usage"
    ux_bullet "Run a tool directly: ${UX_BOLD}\${SHELL_COMMON}/tools/custom/tool-name.sh${UX_RESET}"
    ux_bullet "Or add to PATH for direct execution: ${UX_BOLD}bash tool-name.sh${UX_RESET}"
    echo ""
}

# Alias for mytool-help format (using dash instead of underscore)
alias mytool-help='mytool_help'
