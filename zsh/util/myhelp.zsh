#!/bin/zsh

# zsh/util/myhelp.zsh
# Help system for zsh dotfiles
# Provides centralized help registry for all commands

# Initialize help descriptions array
typeset -A HELP_DESCRIPTIONS

# ═══════════════════════════════════════════════════════════════
# Help Registry Functions
# ═══════════════════════════════════════════════════════════════

# Register a help function
# Usage: register_help "function_name" "Description of function"
register_help() {
    local func_name="$1"
    local description="$2"
    HELP_DESCRIPTIONS["$func_name"]="$description"
}

# Get help description
# Usage: get_help_description "function_name"
get_help_description() {
    local func_name="$1"
    echo "${HELP_DESCRIPTIONS[$func_name]:-No description available}"
}

# ═══════════════════════════════════════════════════════════════
# Main Help Command
# ═══════════════════════════════════════════════════════════════

# Main help function - displays all registered commands
myhelp() {
    if [ -z "$1" ]; then
        _myhelp_show_all
        return 0
    fi

    # If argument is provided, show specific help for that command
    local cmd_name="$1"

    # Try to call the specific help function
    if type "${cmd_name}-help" &>/dev/null 2>&1; then
        "${cmd_name}-help"
    elif type "$cmd_name" &>/dev/null 2>&1; then
        # Try calling command with --help
        "$cmd_name" --help 2>/dev/null || {
            ux_info "Help for '${cmd_name}' not available."
            ux_bullet "Try: ${UX_BOLD}$cmd_name --help${UX_RESET} or ${UX_BOLD}$cmd_name -h${UX_RESET}"
        }
    else
        ux_error "Command '$cmd_name' not found."
        return 1
    fi
}

# Internal: Show all available commands
_myhelp_show_all() {
    ux_header "Zsh Dotfiles Command Reference"

    ux_section "Core Commands"
    ux_bullet "myhelp [command] - Show help for commands"
    ux_bullet "zsh-help - Zsh management (themes, plugins, etc.)"
    ux_bullet "githelp - Git commands and aliases"
    echo ""

    ux_section "Available Help Topics"
    if [ ${#HELP_DESCRIPTIONS[@]} -gt 0 ]; then
        for cmd_name in "${(k)HELP_DESCRIPTIONS[@]}"; do
            ux_table_row "$cmd_name" "${HELP_DESCRIPTIONS[$cmd_name]}"
        done
    else
        ux_info "No help topics registered yet."
    fi
    echo ""

    ux_section "Usage Examples"
    ux_bullet "${UX_BOLD}myhelp${UX_RESET} - Show this help"
    ux_bullet "${UX_BOLD}myhelp zsh${UX_RESET} - Help on zsh management"
    ux_bullet "${UX_BOLD}myhelp git${UX_RESET} - Help on git commands"
    ux_bullet "${UX_BOLD}zsh-help --all${UX_RESET} - Detailed zsh help"
    echo ""

    ux_section "Tips"
    ux_bullet "Most commands support --help or -h flags"
    ux_bullet "Use 'myhelp <command>' to get specific help"
    ux_bullet "Commands are organized by category in zsh/app/ and zsh/util/"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Help Categories
# ═══════════════════════════════════════════════════════════════

# Show help organized by category
category_help() {
    local category="${1:all}"

    case "$category" in
        shell|zsh)
            zsh-help --all
            ;;
        git)
            githelp
            ;;
        system)
            syshelp 2>/dev/null || ux_info "System help not available"
            ;;
        *)
            _myhelp_show_all
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Registration of Help Functions
# ═══════════════════════════════════════════════════════════════

# Register built-in help functions
HELP_DESCRIPTIONS[myhelp]="Main help system"
HELP_DESCRIPTIONS[zsh-help]="Zsh shell management"
HELP_DESCRIPTIONS[githelp]="Git commands reference"

# Note: In zsh, functions and arrays don't need explicit export
# They're automatically available in the current shell session
