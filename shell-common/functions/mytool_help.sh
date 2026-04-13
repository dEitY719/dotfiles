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

_mytool_help_load_ux() {
    if ! command -v ux_header >/dev/null 2>&1 && [ -n "$SHELL_COMMON" ]; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    fi
}

_mytool_help_summary() {
    ux_info "Usage: mytool-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "tools: list all .sh files in shell-common/tools/custom/"
    ux_bullet_sub "usage: how to run custom tools"
    ux_bullet_sub "details: mytool-help <section>  (example: mytool-help tools)"
}

_mytool_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "tools"
    ux_bullet_sub "usage"
}

_mytool_help_rows_tools() {
    if [ -z "$SHELL_COMMON" ]; then
        ux_warning "SHELL_COMMON environment variable not set"
        return 1
    fi

    local custom_dir="${SHELL_COMMON}/tools/custom"
    if [ ! -d "$custom_dir" ]; then
        ux_error "Custom tools directory not found: $custom_dir"
        return 1
    fi

    ux_info "Executable utility scripts in ${custom_dir}"

    local scripts
    scripts="$(find "$custom_dir" -maxdepth 1 -type f -name "*.sh" -print | sort)"

    if [ -z "$scripts" ]; then
        ux_warning "No custom tools found in ${custom_dir}"
        return 0
    fi

    ux_table_header "Tool" "Description"

    local count=0
    while IFS= read -r script; do
        [ -n "$script" ] || continue

        local tool_name
        tool_name="$(basename "$script" .sh)"

        local desc
        desc=$(_extract_tool_description "$script" "$tool_name")

        ux_table_row "$tool_name" "$desc"
        count=$((count + 1))
    done <<EOF
$scripts
EOF

    ux_info "Total: $count custom tools available"
    ux_info "Location: ${custom_dir}"
}

_mytool_help_rows_usage() {
    ux_bullet "Run a tool directly: ${UX_BOLD}\${SHELL_COMMON}/tools/custom/tool-name.sh${UX_RESET}"
    ux_bullet "Or add to PATH for direct execution: ${UX_BOLD}tool-name.sh${UX_RESET}"
}

_mytool_help_render_section() {
    ux_section "$1"
    "$2"
}

_mytool_help_section_rows() {
    case "$1" in
        tools|tool|list-tools)
            _mytool_help_rows_tools
            ;;
        usage|use|run)
            _mytool_help_rows_usage
            ;;
        *)
            ux_error "Unknown mytool-help section: $1"
            ux_info "Try: mytool-help --list"
            return 1
            ;;
    esac
}

_mytool_help_full() {
    ux_header "MyTool - Custom Utility Scripts"
    _mytool_help_render_section "Available Custom Tools" _mytool_help_rows_tools
    _mytool_help_render_section "Usage" _mytool_help_rows_usage
}

mytool_help() {
    _mytool_help_load_ux
    case "${1:-}" in
        ""|-h|--help|help)
            _mytool_help_summary
            ;;
        --list|list|section|sections)
            _mytool_help_list_sections
            ;;
        --all|all)
            _mytool_help_full
            ;;
        *)
            _mytool_help_section_rows "$1"
            ;;
    esac
}

# Alias for mytool-help format (using dash instead of underscore)
alias mytool-help='mytool_help'
