#!/bin/sh
# shell-common/functions/my_help.sh
# Help system for bash/zsh dotfiles
# Provides centralized help registry for all commands
# Bash/Zsh/POSIX compatible

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
# Usage: _register_help "function_name" "Description of function"
_register_help() {
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
    # Prefer bash builtin when available.
    if command -v compgen >/dev/null 2>&1; then
        compgen -A function | { grep 'help$' || true; } | LC_ALL=C sort
        return 0
    fi

    # zsh fallback: compgen is not available unless bashcompinit is enabled.
    if [ -n "$ZSH_VERSION" ]; then
        # NOTE: Use eval to avoid zsh-only syntax being parsed by bash at source time.
        eval 'print -rl -- ${(k)functions}' | { grep 'help$' || true; } | LC_ALL=C sort
        return 0
    fi

    return 0
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
    HELP_DESCRIPTIONS[claude_plugins_help]="${HELP_DESCRIPTIONS[claude_plugins_help]:-Claude plugins and integrations setup}"
    HELP_DESCRIPTIONS[claude_skills_marketplace_help]="${HELP_DESCRIPTIONS[claude_skills_marketplace_help]:-Marketplace skills management system with caching}"
    HELP_DESCRIPTIONS[notion_help]="${HELP_DESCRIPTIONS[notion_help]:-Notion API integration and commands}"
    HELP_DESCRIPTIONS[ollama_help]="${HELP_DESCRIPTIONS[ollama_help]:-Ollama local LLM setup and usage}"
    HELP_DESCRIPTIONS[opencode_help]="${HELP_DESCRIPTIONS[opencode_help]:-OpenCode CLI setup and configuration}"
    HELP_DESCRIPTIONS[show_doc_help]="${HELP_DESCRIPTIONS[show_doc_help]:-Documentation viewer and manager commands}"
    HELP_DESCRIPTIONS[category_help]="${HELP_DESCRIPTIONS[category_help]:-Show help topics by category}"
    HELP_DESCRIPTIONS[register_help]="${HELP_DESCRIPTIONS[register_help]:-Register help topic descriptions}"
    HELP_DESCRIPTIONS[work_log_help]="${HELP_DESCRIPTIONS[work_log_help]:-Work log tracking for non-development activities}"
}

# ═══════════════════════════════════════════════════════════════
# Main Help Functions
# ═══════════════════════════════════════════════════════════════

# Internal: Show all available commands
_my_help_show_all() {
    ux_header "Dotfiles Help Functions"

    # In zsh, users may enable strict options (e.g., noclobber) that break temp-file
    # redirections. Make these option changes local to this function only.
    if [ -n "$ZSH_VERSION" ]; then
        setopt localoptions clobber 2>/dev/null || true
    fi

    # Collect help functions (using temp file instead of array)
    local tmp_dir="${TMPDIR:-/tmp}"
    local temp_funcs
    local temp_raw
    local temp_sorted

    if command -v mktemp >/dev/null 2>&1; then
        temp_funcs=$(mktemp "${tmp_dir%/}/my_help_funcs.XXXXXX" 2>/dev/null) || temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_raw=$(mktemp "${tmp_dir%/}/my_help_raw.XXXXXX" 2>/dev/null) || temp_raw="${tmp_dir%/}/.help_raw_$$"
        temp_sorted=$(mktemp "${tmp_dir%/}/my_help_sorted.XXXXXX" 2>/dev/null) || temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    else
        temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_raw="${tmp_dir%/}/.help_raw_$$"
        temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    fi

    # Ensure clean slate even under noclobber.
    rm -f "$temp_funcs" "$temp_raw" "$temp_sorted" 2>/dev/null || true
    : > "$temp_funcs"
    : > "$temp_raw"

    _get_help_functions > "$temp_raw"

    while IFS= read -r func; do
        # Extract function name (before '(' or first space)
        local func_name="${func%%[( ]*}"

        # Include functions ending with 'help' (both dash and underscore)
        # Exclude: my-help, run-help, _* (internal functions)
        case "$func_name" in
            *help)
                case "$func_name" in
                    my-help|run-help) ;;
                    _*) ;;
                    *)
                        # Normalize to dash format for display
                        local display_name=""
                        display_name=$(echo "$func_name" | tr '_' '-')
                        echo "$display_name" >> "$temp_funcs"
                        ;;
                esac
                ;;
        esac
    done < "$temp_raw"

    rm -f "$temp_raw"

    # Remove duplicates and sort
    local unique_count
    unique_count=$(sort -u "$temp_funcs" | wc -l)

    # Show section with count of available help commands
    ux_section "Available help commands($unique_count)"

    # Display help functions with descriptions
    sort -u "$temp_funcs" > "$temp_sorted"
    while IFS= read -r func; do
        # Try both dash and underscore format for description lookup
        local desc="${HELP_DESCRIPTIONS[$func]}"
        if [ -z "$desc" ]; then
            # Try underscore format
            local func_underscore=""
            func_underscore=$(echo "$func" | tr '-' '_')
            desc="${HELP_DESCRIPTIONS[$func_underscore]}"
        fi
        desc="${desc:-⛔No description available}"
        printf "  ${UX_SUCCESS}%-30s${UX_RESET}  ${UX_MUTED}:${UX_RESET}  %s\n" "$func" "$desc"
    done < "$temp_sorted"

    rm -f "$temp_sorted" "$temp_funcs" 2>/dev/null || true

    ux_divider

    ux_info "Type any of the above commands to see detailed help"
    ux_bullet "${UX_MUTED}Example:${UX_RESET} ${UX_INFO}git-help${UX_RESET}, ${UX_INFO}uv-help${UX_RESET}, ${UX_INFO}docker-help${UX_RESET}"

    ux_warning "To add a new help function:"
    ux_bullet "Create a function ending with 'help' (e.g., docker-help or docker_help)"
    ux_bullet "Register description: HELP_DESCRIPTIONS[\"docker_help\"]=\"Your description\""
    ux_bullet "Display name will be normalized to dash format (docker-help)"
    ux_bullet "It will be automatically detected by ${UX_SUCCESS}my-help${UX_RESET}"

    return 0
}

# Main help function - displays all registered commands or specific help
my_help_impl() {
    local rc=0

    # Keep output clean even when users enable tracing (set -x / setopt xtrace).
    local _my_help_restore_xtrace=0
    if [ -n "$BASH_VERSION" ]; then
        case "$-" in
            *x*)
                _my_help_restore_xtrace=1
                set +x
                ;;
        esac
    elif [ -n "$ZSH_VERSION" ]; then
        if [[ -o xtrace ]]; then
            _my_help_restore_xtrace=1
            unsetopt xtrace
        fi
    fi

    # Register default descriptions (only once)
    if [ -z "${_HELP_DEFAULTS_REGISTERED}" ]; then
        _register_default_help_descriptions
        _HELP_DEFAULTS_REGISTERED=1
    fi

    if [ -z "$1" ]; then
        _my_help_show_all
        rc=$?
    else
        # If argument is provided, show specific help for that command
        local cmd_name="$1"

        # Prefer canonical underscore helpers to avoid alias-only lookups (bash cannot
        # execute aliases when the name comes from parameter expansion)
        local normalized
        normalized=$(echo "$cmd_name" | tr '-' '_')
        local helper_name="$normalized"
        case "$helper_name" in
            *_help) ;;
            *) helper_name="${helper_name}_help" ;;
        esac

        if typeset -f "$helper_name" >/dev/null 2>&1; then
            "$helper_name"
            rc=$?
        else
            # Some modules only expose a dash-style alias (e.g., apt-help). Safely detect
            # aliases/functions using dash notation and execute them via eval so alias
            # expansion occurs in both bash and zsh.
            case "$cmd_name" in
                *[!A-Za-z0-9_-]*)
                    rc=1
                    ;;
                *)
                    local dash_name
                    dash_name=$(echo "$cmd_name" | tr '_' '-')
                    case "$dash_name" in
                        *-help) ;;
                        *) dash_name="${dash_name}-help" ;;
                    esac
                    if type "$dash_name" >/dev/null 2>&1; then
                        eval "$dash_name"
                        rc=$?
                    elif typeset -f "$cmd_name" >/dev/null 2>&1; then
                        "$cmd_name"
                        rc=$?
                    elif type "$cmd_name" >/dev/null 2>&1; then
                        # Try calling command with --help
                        "$cmd_name" --help 2>/dev/null || {
                            ux_info "Help for '${cmd_name}' not available."
                            ux_bullet "Try: ${UX_BOLD}$cmd_name --help${UX_RESET} or ${UX_BOLD}$cmd_name -h${UX_RESET}"
                        }
                        rc=0
                    else
                        ux_error "Command '$cmd_name' not found."
                        rc=1
                    fi
                    ;;
            esac
        fi
    fi

    if [ "$_my_help_restore_xtrace" = "1" ]; then
        if [ -n "$BASH_VERSION" ]; then
            set -x
        elif [ -n "$ZSH_VERSION" ]; then
            setopt xtrace
        fi
    fi

    return "$rc"
}

# ═══════════════════════════════════════════════════════════════
# Initial Help Descriptions
# ═══════════════════════════════════════════════════════════════

# Register built-in help functions (can be overridden)
HELP_DESCRIPTIONS[my_help_impl]="Main help system"

# Alias for my-help format (using dash instead of underscore)
alias my-help='my_help_impl'

# zsh compatibility: when `setopt no_aliases` is enabled, dash-style aliases won't expand.
# Provide a narrow `command_not_found_handler` shim so typing `my-help` still works.
if [ -n "$ZSH_VERSION" ]; then
    if [ -z "${_DOTFILES_MY_HELP_CNF_INSTALLED:-}" ]; then
        _DOTFILES_MY_HELP_CNF_INSTALLED=1

        # Preserve any existing handler.
        if typeset -f command_not_found_handler >/dev/null 2>&1; then
            eval 'functions[_dotfiles_prev_command_not_found_handler]=$functions[command_not_found_handler]'
        fi

        command_not_found_handler() {
            local cmd_name="$1"
            shift || true

            if [ "$cmd_name" = "my-help" ]; then
                my_help_impl "$@"
                return $?
            fi

            if typeset -f _dotfiles_prev_command_not_found_handler >/dev/null 2>&1; then
                _dotfiles_prev_command_not_found_handler "$cmd_name" "$@"
                return $?
            fi

            print -u2 -- "zsh: command not found: ${cmd_name}"
            return 127
        }
    fi
fi
