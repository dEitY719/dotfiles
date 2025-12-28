#!/bin/bash

# ------------------------------------------------------------------
# --- Master Help Function ---
# Automatically detects and lists all *help() functions
# Uses global HELP_DESCRIPTIONS array for descriptions
# Modules can register via: HELP_DESCRIPTIONS["funcname"]="description"
# ------------------------------------------------------------------

# Initialize global help descriptions associative array
# This should be declared only once (in this file) and populated by all modules
if [[ -z "${HELP_DESCRIPTIONS+_}" ]]; then
    declare -gA HELP_DESCRIPTIONS=()
fi

# Default descriptions for backward compatibility
# New modules should register their own descriptions
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
}

myhelp() {
    # Register default descriptions (modules can override before this)
    _register_default_help_descriptions

    ux_header "Dotfiles Help Functions"
    ux_section "Available help commands"

    # Collect help functions using the helper defined in main.bash
    local help_funcs=()
    while IFS= read -r func; do
        local func_name="${func%%(*}"
        if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]] && [[ "$func_name" != _* ]]; then
            help_funcs+=("$func_name")
        fi
    done < <(_get_help_functions)

    # Calculate max width for alignment
    local max_width=0
    local func
    for func in "${help_funcs[@]}"; do
        ((${#func} > max_width)) && max_width=${#func}
    done

    # Display help functions with descriptions from global array
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
