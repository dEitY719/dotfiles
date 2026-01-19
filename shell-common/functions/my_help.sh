#!/bin/bash
# shell-common/functions/my_help.sh
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

# Initialize global help descriptions associative array (bash/zsh compatible)
if [ -z "${HELP_DESCRIPTIONS+_}" ]; then
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_DESCRIPTIONS=()
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_DESCRIPTIONS=()
    fi
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
    # Use simple unconditional assignment (modules load first, so they take precedence)
    # This approach works in both bash and zsh
    HELP_DESCRIPTIONS[uv_help]="${HELP_DESCRIPTIONS[uv_help]:-UV package manager commands}"
    HELP_DESCRIPTIONS[git_help]="${HELP_DESCRIPTIONS[git_help]:-Git shortcuts and aliases}"
    HELP_DESCRIPTIONS[py_help]="${HELP_DESCRIPTIONS[py_help]:-Python virtual environment commands}"
    HELP_DESCRIPTIONS[dir_help]="${HELP_DESCRIPTIONS[dir_help]:-Directory navigation aliases}"
    HELP_DESCRIPTIONS[sys_help]="${HELP_DESCRIPTIONS[sys_help]:-System management commands}"
    HELP_DESCRIPTIONS[pp_help]="${HELP_DESCRIPTIONS[pp_help]:-Python package and code quality tools}"
    HELP_DESCRIPTIONS[cli_help]="${HELP_DESCRIPTIONS[cli_help]:-Custom Project CLI list}"
    HELP_DESCRIPTIONS[du_help]="${HELP_DESCRIPTIONS[du_help]:-Disk usage help}"
    HELP_DESCRIPTIONS[psql_help]="${HELP_DESCRIPTIONS[psql_help]:-PostgreSQL command helper}"
    HELP_DESCRIPTIONS[cc_help]="${HELP_DESCRIPTIONS[cc_help]:-Claude Code usage help}"
    HELP_DESCRIPTIONS[claude_help]="${HELP_DESCRIPTIONS[claude_help]:-Claude Code MCP help}"
    HELP_DESCRIPTIONS[docker_help]="${HELP_DESCRIPTIONS[docker_help]:-Docker commands and aliases}"
    HELP_DESCRIPTIONS[apt_help]="${HELP_DESCRIPTIONS[apt_help]:-APT package manager commands}"
    HELP_DESCRIPTIONS[gemini_help]="${HELP_DESCRIPTIONS[gemini_help]:-Gemini CLI commands and aliases}"
    HELP_DESCRIPTIONS[codex_help]="${HELP_DESCRIPTIONS[codex_help]:-Codex CLI commands and aliases}"
    HELP_DESCRIPTIONS[dproxy_help]="${HELP_DESCRIPTIONS[dproxy_help]:-Docker Proxy(Corporate) commands}"
    HELP_DESCRIPTIONS[npm_help]="${HELP_DESCRIPTIONS[npm_help]:-NPM package manager commands}"
    HELP_DESCRIPTIONS[nvm_help]="${HELP_DESCRIPTIONS[nvm_help]:-NVM (Node Version Manager) commands}"
    HELP_DESCRIPTIONS[litellm_help]="${HELP_DESCRIPTIONS[litellm_help]:-LiteLLM commands and aliases}"
    HELP_DESCRIPTIONS[gpu_help]="${HELP_DESCRIPTIONS[gpu_help]:-GPU monitoring commands (WSL2 universal)}"
    HELP_DESCRIPTIONS[ux_help]="${HELP_DESCRIPTIONS[ux_help]:-UX library functions and styling guide}"
    HELP_DESCRIPTIONS[gc_help]="${HELP_DESCRIPTIONS[gc_help]:-git-crypt (Transparent Git encryption)}"
    HELP_DESCRIPTIONS[mytool_help]="${HELP_DESCRIPTIONS[mytool_help]:-Custom utility scripts in tools/custom}"
    HELP_DESCRIPTIONS[mysql_help]="${HELP_DESCRIPTIONS[mysql_help]:-MySQL Service Management}"
    HELP_DESCRIPTIONS[zsh-help]="${HELP_DESCRIPTIONS[zsh-help]:-Zsh shell management commands}"
    HELP_DESCRIPTIONS[bat-help]="${HELP_DESCRIPTIONS[bat-help]:-bat - Cat replacement with syntax highlighting}"
    HELP_DESCRIPTIONS[dot_help]="${HELP_DESCRIPTIONS[dot_help]:-Dotfiles project overview and setup guidance}"
    HELP_DESCRIPTIONS[proxy_help]="${HELP_DESCRIPTIONS[proxy_help]:-Proxy configuration commands and diagnostics}"
    HELP_DESCRIPTIONS[fasd-help]="${HELP_DESCRIPTIONS[fasd-help]:-fasd - Fast access to directories and files}"
    HELP_DESCRIPTIONS[fd-help]="${HELP_DESCRIPTIONS[fd-help]:-fd - Fast file finder tool}"
    HELP_DESCRIPTIONS[fzf-help]="${HELP_DESCRIPTIONS[fzf-help]:-fzf (Fuzzy Finder) key bindings and usage}"
    HELP_DESCRIPTIONS[pet-help]="${HELP_DESCRIPTIONS[pet-help]:-pet - Simple command snippet manager}"
    HELP_DESCRIPTIONS[ripgrep-help]="${HELP_DESCRIPTIONS[ripgrep-help]:-ripgrep (rg) fast text search tool}"
    HELP_DESCRIPTIONS[p10k_help]="${HELP_DESCRIPTIONS[p10k_help]:-Powerlevel10k font setup guide}"
    HELP_DESCRIPTIONS[crt_help]="${HELP_DESCRIPTIONS[crt_help]:-CA Certificate setup and management guide}"
    HELP_DESCRIPTIONS[pip_help]="${HELP_DESCRIPTIONS[pip_help]:-Pip package manager configuration and diagnostics}"
    HELP_DESCRIPTIONS[mount_help]="${HELP_DESCRIPTIONS[mount_help]:-Mount management commands for Claude environment}"
}

# ═══════════════════════════════════════════════════════════════
# Main Help Functions
# ═══════════════════════════════════════════════════════════════

# Internal: Show all available commands
_my_help_show_all() {
    ux_header "Dotfiles Help Functions"

    # Collect help functions
    local help_funcs=()
    while IFS= read -r func; do
        # Extract function name (before '(' or first space)
        local func_name="${func%%[( ]*}"

        # Include functions ending with 'help' (both dash and underscore)
        # Exclude:
        # - my-help (main help function)
        # - _* (internal functions)
        # - run-help (zsh builtin)
        # - *_* (internal utility functions with underscores)
        if [[ "$func_name" == *help ]] && \
           [[ "$func_name" != "my-help" ]] && \
           [[ "$func_name" != "run-help" ]] && \
           [[ "$func_name" != *_* ]] && \
           [[ "$func_name" != _* ]]; then

            # Normalize to dash format for display
            local display_name="${func_name//_/-}"
            help_funcs+=("$display_name")
        fi
    done < <(_get_help_functions)

    # Remove duplicates and sort
    local unique_funcs=($(printf '%s\n' "${help_funcs[@]}" | sort -u))

    # Show section with count of available help commands
    ux_section "Available help commands(${#unique_funcs[@]})"

    # Calculate max width for alignment
    local max_width=0
    local func
    for func in "${unique_funcs[@]}"; do
        ((${#func} > max_width)) && max_width=${#func}
    done

    # Display help functions with descriptions
    for func in "${unique_funcs[@]}"; do
        # Try both dash and underscore format for description lookup
        local desc="${HELP_DESCRIPTIONS[$func]}"
        if [ -z "$desc" ]; then
            # Try underscore format
            local func_underscore="${func//-/_}"
            desc="${HELP_DESCRIPTIONS[$func_underscore]}"
        fi
        desc="${desc:-⛔No description available}"
        printf "  ${UX_SUCCESS}%-${max_width}s${UX_RESET}  ${UX_MUTED}:${UX_RESET}  %s\n" "$func" "$desc"
    done


    ux_divider

    ux_info "Type any of the above commands to see detailed help"
    ux_bullet "${UX_MUTED}Example:${UX_RESET} ${UX_INFO}git-help${UX_RESET}, ${UX_INFO}uv-help${UX_RESET}, ${UX_INFO}docker-help${UX_RESET}"

    ux_warning "To add a new help function:"
    ux_bullet "Create a function ending with 'help' (e.g., docker-help or docker_help)"
    ux_bullet "Register description: HELP_DESCRIPTIONS[\"docker_help\"]=\"Your description\""
    ux_bullet "Display name will be normalized to dash format (docker-help)"
    ux_bullet "It will be automatically detected by ${UX_SUCCESS}my-help${UX_RESET}"

}

# Main help function - displays all registered commands or specific help
my_help() {
    # Register default descriptions (only once)
    if [ -z "${_HELP_DEFAULTS_REGISTERED}" ]; then
        _register_default_help_descriptions
        _HELP_DEFAULTS_REGISTERED=1
    fi

    if [ -z "$1" ]; then
        _my_help_show_all
        return 0
    fi

    # If argument is provided, show specific help for that command
    local cmd_name="$1"

    # Prefer canonical underscore helpers to avoid alias-only lookups (bash cannot
    # execute aliases when the name comes from parameter expansion)
    local normalized="${cmd_name//-/_}"
    local helper_name="$normalized"
    if [[ "$helper_name" != *_help ]]; then
        helper_name="${helper_name}_help"
    fi

    if typeset -f "$helper_name" &>/dev/null; then
        "$helper_name"
        return 0
    fi

    # Some modules only expose a dash-style alias (e.g., apt-help). Safely detect
    # aliases/functions using dash notation and execute them via eval so alias
    # expansion occurs in both bash and zsh.
    if [[ "$cmd_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        local dash_name="${cmd_name//_/-}"
        if [[ "$dash_name" != *-help ]]; then
            dash_name="${dash_name}-help"
        fi
        if type "$dash_name" &>/dev/null 2>&1; then
            eval "$dash_name"
            return 0
        fi
    fi

    if typeset -f "$cmd_name" &>/dev/null; then
        "$cmd_name"
        return 0
    fi

    if type "$cmd_name" &>/dev/null 2>&1; then
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
            git_help
            ;;
        system)
            sys_help 2>/dev/null || ux_info "System help not available"
            ;;
        *)
            _my_help_show_all
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Initial Help Descriptions
# ═══════════════════════════════════════════════════════════════

# Register built-in help functions (can be overridden)
HELP_DESCRIPTIONS[my_help]="Main help system"

# Alias for my-help format (using dash instead of underscore)
alias my-help='my_help'
