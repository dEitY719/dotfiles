#!/bin/bash
# shell-common/functions/myhelp.sh
# Help system for bash/zsh dotfiles
# Provides centralized help registry for all commands
# Bash/Zsh compatible (POSIX not supported)

# ═══════════════════════════════════════════════════════════════
# UX Library Loading (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

if ! type ux_header >/dev/null 2>&1; then
    # Try to load UX library if not already loaded
    if [ -z "$SHELL_COMMON" ]; then
        # Detect shell type and set path accordingly
        if [ -n "$ZSH_VERSION" ]; then
            # We're in zsh
            _MYHELP_DIR="${0:h}"
        else
            # We're in bash
            _MYHELP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        fi
        SHELL_COMMON="${_MYHELP_DIR%/functions}"
    fi
    if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Help Registry Initialization (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

# Initialize global help descriptions associative array
if [ -z "${HELP_DESCRIPTIONS+_}" ]; then
    declare -gA HELP_DESCRIPTIONS=()
fi

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
# Helper: Get all help functions (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

_get_help_functions() {
    # bash/zsh compatible: use compgen
    compgen -A function | { grep 'help$' || true; } | LC_ALL=C sort
}

# ═══════════════════════════════════════════════════════════════
# Default Help Descriptions Registration
# ═══════════════════════════════════════════════════════════════

_register_default_help_descriptions() {
    # Only set if not already registered by the module itself
    [[ -z "${HELP_DESCRIPTIONS[uvhelp]}" ]] && HELP_DESCRIPTIONS["uvhelp"]="UV package manager commands"
    [[ -z "${HELP_DESCRIPTIONS[githelp]}" ]] && HELP_DESCRIPTIONS["githelp"]="Git shortcuts and aliases"
    [[ -z "${HELP_DESCRIPTIONS[pyhelp]}" ]] && HELP_DESCRIPTIONS["pyhelp"]="Python virtual environment commands"
    [[ -z "${HELP_DESCRIPTIONS[dirhelp]}" ]] && HELP_DESCRIPTIONS["dirhelp"]="Directory navigation aliases"
    [[ -z "${HELP_DESCRIPTIONS[syshelp]}" ]] && HELP_DESCRIPTIONS["syshelp"]="System management commands"
    [[ -z "${HELP_DESCRIPTIONS[pphelp]}" ]] && HELP_DESCRIPTIONS["pphelp"]="Python package and code quality tools"
    [[ -z "${HELP_DESCRIPTIONS[clihelp]}" ]] && HELP_DESCRIPTIONS["clihelp"]="Custom Project CLI list"
    [[ -z "${HELP_DESCRIPTIONS[duhelp]}" ]] && HELP_DESCRIPTIONS["duhelp"]="Disk usage help"
    [[ -z "${HELP_DESCRIPTIONS[psqlhelp]}" ]] && HELP_DESCRIPTIONS["psqlhelp"]="PostgreSQL command helper"
    [[ -z "${HELP_DESCRIPTIONS[cchelp]}" ]] && HELP_DESCRIPTIONS["cchelp"]="Claude Code usage help"
    [[ -z "${HELP_DESCRIPTIONS[claudehelp]}" ]] && HELP_DESCRIPTIONS["claudehelp"]="Claude Code MCP help"
    [[ -z "${HELP_DESCRIPTIONS[dockerhelp]}" ]] && HELP_DESCRIPTIONS["dockerhelp"]="Docker commands and aliases"
    [[ -z "${HELP_DESCRIPTIONS[apthelp]}" ]] && HELP_DESCRIPTIONS["apthelp"]="APT package manager commands"
    [[ -z "${HELP_DESCRIPTIONS[geminihelp]}" ]] && HELP_DESCRIPTIONS["geminihelp"]="Gemini CLI commands and aliases"
    [[ -z "${HELP_DESCRIPTIONS[codexhelp]}" ]] && HELP_DESCRIPTIONS["codexhelp"]="Codex CLI commands and aliases"
    [[ -z "${HELP_DESCRIPTIONS[dproxyhelp]}" ]] && HELP_DESCRIPTIONS["dproxyhelp"]="Docker Proxy(Corporate) commands"
    [[ -z "${HELP_DESCRIPTIONS[npmhelp]}" ]] && HELP_DESCRIPTIONS["npmhelp"]="NPM package manager commands"
    [[ -z "${HELP_DESCRIPTIONS[nvmhelp]}" ]] && HELP_DESCRIPTIONS["nvmhelp"]="NVM (Node Version Manager) commands"
    [[ -z "${HELP_DESCRIPTIONS[litellm_help]}" ]] && HELP_DESCRIPTIONS["litellm_help"]="LiteLLM commands and aliases"
    [[ -z "${HELP_DESCRIPTIONS[gpuhelp]}" ]] && HELP_DESCRIPTIONS["gpuhelp"]="GPU monitoring commands (WSL2 universal)"
    [[ -z "${HELP_DESCRIPTIONS[uxhelp]}" ]] && HELP_DESCRIPTIONS["uxhelp"]="UX library functions and styling guide"
    [[ -z "${HELP_DESCRIPTIONS[gc_help]}" ]] && HELP_DESCRIPTIONS["gc_help"]="git-crypt (Transparent Git encryption)"
    [[ -z "${HELP_DESCRIPTIONS[mytool_help]}" ]] && HELP_DESCRIPTIONS["mytool_help"]="MyTool - Personal Utility Commands"
    [[ -z "${HELP_DESCRIPTIONS[mysql_help]}" ]] && HELP_DESCRIPTIONS["mysql_help"]="MySQL Service Management"
    [[ -z "${HELP_DESCRIPTIONS[zsh-help]}" ]] && HELP_DESCRIPTIONS["zsh-help"]="Zsh shell management"
    [[ -z "${HELP_DESCRIPTIONS[bat-help]}" ]] && HELP_DESCRIPTIONS["bat-help"]="bat - Cat replacement with syntax highlighting"
    [[ -z "${HELP_DESCRIPTIONS[fasd-help]}" ]] && HELP_DESCRIPTIONS["fasd-help"]="fasd - Fast access to directories and files"
    [[ -z "${HELP_DESCRIPTIONS[fd-help]}" ]] && HELP_DESCRIPTIONS["fd-help"]="fd - Fast file finder tool"
    [[ -z "${HELP_DESCRIPTIONS[fzf-help]}" ]] && HELP_DESCRIPTIONS["fzf-help"]="fzf (Fuzzy Finder) key bindings and usage"
    [[ -z "${HELP_DESCRIPTIONS[pet-help]}" ]] && HELP_DESCRIPTIONS["pet-help"]="pet - Simple command snippet manager"
    [[ -z "${HELP_DESCRIPTIONS[ripgrep-help]}" ]] && HELP_DESCRIPTIONS["ripgrep-help"]="ripgrep (rg) fast text search tool"
    [[ -z "${HELP_DESCRIPTIONS[p10k-help]}" ]] && HELP_DESCRIPTIONS["p10k-help"]="Powerlevel10k font setup guide"
}

# ═══════════════════════════════════════════════════════════════
# Main Help Functions
# ═══════════════════════════════════════════════════════════════

# Internal: Show all available commands
_myhelp_show_all() {
    ux_header "Dotfiles Help Functions"
    ux_section "Available help commands"

    # Collect help functions
    local help_funcs=()
    while IFS= read -r func; do
        # Extract function name (before '(' or first space)
        local func_name="${func%%[( ]*}"
        # Check if func_name ends with 'help' and exclude internal functions
        if [[ "$func_name" == *help ]] && [[ "$func_name" != "myhelp" ]] && [[ "$func_name" != _* ]]; then
            help_funcs+=("$func_name")
        fi
    done < <(_get_help_functions)

    # Calculate max width for alignment
    local max_width=0
    local func
    for func in "${help_funcs[@]}"; do
        ((${#func} > max_width)) && max_width=${#func}
    done

    # Display help functions with descriptions
    for func in "${help_funcs[@]}"; do
        local desc="${HELP_DESCRIPTIONS[$func]:-⛔No description available}"
        printf "  ${UX_SUCCESS}%-${max_width}s${UX_RESET}  ${UX_MUTED}:${UX_RESET}  %s\n" "$func" "$desc"
    done

    echo ""
    ux_divider
    echo ""
    ux_info "Type any of the above commands to see detailed help"
    echo "  ${UX_MUTED}Example:${UX_RESET} ${UX_INFO}githelp${UX_RESET}, ${UX_INFO}uvhelp${UX_RESET}, ${UX_INFO}dockerhelp${UX_RESET}"
    echo ""
    ux_warning "To add a new help function:"
    ux_bullet "Create a function ending with 'help' (e.g., dockerhelp)"
    ux_bullet "Register description: HELP_DESCRIPTIONS[\"yourhelp\"]=\"Your description\""
    ux_bullet "It will be automatically detected by ${UX_SUCCESS}myhelp${UX_RESET}"
    echo ""
}

# Main help function - displays all registered commands or specific help
myhelp() {
    # Register default descriptions
    _register_default_help_descriptions

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

# ═══════════════════════════════════════════════════════════════
# Help Categories
# ═══════════════════════════════════════════════════════════════

# Show help organized by category
category_help() {
    local category="${1:all}"

    case "$category" in
        shell|zsh)
            zsh-help --all 2>/dev/null || ux_error "zsh-help not available"
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
# Initial Help Descriptions
# ═══════════════════════════════════════════════════════════════

# Register built-in help functions (can be overridden)
HELP_DESCRIPTIONS[myhelp]="Main help system"
