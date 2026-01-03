#!/bin/sh
# shell-common/functions/mytool_help.sh
# mytool Help - shared between bash and zsh
# Lists personal utility commands from shell-common/tools/custom/

# Helper: Extract description from the script header comments
_extract_tool_description() {
    local script="$1"
    local tool_name="$2"
    local description=""
    local usage_line=""
    local comment_block=""

    # Read the first 40 lines and strip leading comment markers
    comment_block="$(head -n 40 "$script" 2>/dev/null | sed -n 's/^#[[:space:]]*//p')"

    while IFS= read -r line; do
        [ -n "$line" ] || continue

        # Capture Usage line as a fallback description
        if [ -z "$usage_line" ] && printf '%s\n' "$line" | grep -qi '^usage:'; then
            usage_line="$line"
            continue
        fi

        # Skip shebang remnants, file metadata, and paths
        case "$line" in
            "!/"*bin/*|"/bin/"*|"/usr/bin/"*)
                continue
                ;;
            *"/"*".sh"*|*"$tool_name".sh*)
                continue
                ;;
        esac

        # Require at least one alphanumeric character (skip divider lines)
        if ! printf '%s\n' "$line" | grep -q '[[:alnum:]]'; then
            continue
        fi

        description="$line"
        break
    done <<EOF
$comment_block
EOF

    # Fallbacks: usage line or placeholder
    if [ -z "$description" ]; then
        description="$usage_line"
    fi
    if [ -z "$description" ]; then
        description="(No description)"
    fi

    # Trim long descriptions for table display
    if [ ${#description} -gt 60 ]; then
        description="$(printf '%s' "$description" | cut -c1-57)..."
    fi

    printf "%s\n" "$description"
}

mytool_help() {
    if ! command -v ux_header >/dev/null 2>&1 && [ -n "$SHELL_COMMON" ]; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    fi

    ux_header "MyTool - Custom Utility Scripts"

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

    ux_section "Available Custom Tools"
    ux_info "Executable utility scripts in ${custom_dir}"

    local scripts
    scripts="$(find "$custom_dir" -maxdepth 1 -type f -name "*.sh" -print | sort)"

    if [ -z "$scripts" ]; then
        ux_warning "No custom tools found in ${custom_dir}"
        echo ""
        return 0
    fi

    ux_table_header "Tool" "Description"

    # Find and display all .sh files
    local count=0
    while IFS= read -r script; do
        [ -n "$script" ] || continue

        local tool_name
        tool_name="$(basename "$script" .sh)"

        local desc
        desc="$(_extract_tool_description "$script" "$tool_name")"

        ux_table_row "$tool_name" "$desc"
        count=$((count + 1))
    done <<EOF
$scripts
EOF

    echo ""
    ux_info "Total: $count custom tools available"
    ux_info "Location: ${custom_dir}"
    echo ""

    ux_section "Usage"
    ux_bullet "Run a tool directly: ${UX_BOLD}\${SHELL_COMMON}/tools/custom/tool-name.sh${UX_RESET}"
    ux_bullet "Or add to PATH for direct execution: ${UX_BOLD}tool-name.sh${UX_RESET}"
    echo ""
}

# Alias for mytool-help format (using dash instead of underscore)
alias mytool-help='mytool_help'
