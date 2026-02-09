#!/bin/zsh

# zsh/main.zsh
# Zsh Dotfiles Loader (SOLID Principle Compliant)
# Completely independent from bash - no emulation, native zsh execution
# Loading order: Env → UX → Alias → Functions → Utils → App

# Exit if not in zsh (safely return without killing shell)
if [ -z "$ZSH_VERSION" ]; then
    return 0
fi

# ═══════════════════════════════════════════════════════════════
# Directory Setup - Use provided variables or detect from script location
# ═══════════════════════════════════════════════════════════════

# Clear bash-specific variables that might be inherited from parent bash shell
# to prevent path confusion
unset DOTFILES_BASH_DIR

# If zshrc already set these, use them. Otherwise detect them.
if [ -z "$DOTFILES_ROOT" ]; then
    # Compute DOTFILES_ROOT from this script's location (unified with bash)
    # In zsh, ${(%):-%N} gets the sourced script name
    _ZSH_SCRIPT="${${(%):-%N}:-$0}"
    _ZSH_SCRIPT_DIR="$(cd "$(dirname "$_ZSH_SCRIPT")" 2>/dev/null && pwd)" || _ZSH_SCRIPT_DIR=""

    # Compute DOTFILES_ROOT: go up from zsh/ to parent directory
    DOTFILES_ROOT="${_ZSH_SCRIPT_DIR%/zsh}"

    # Validate DOTFILES_ROOT is a real directory
    if [ -z "$DOTFILES_ROOT" ] || [ ! -d "$DOTFILES_ROOT" ]; then
        # Fallback to default location if detection fails
        DOTFILES_ROOT="${HOME}/dotfiles"
    fi
fi

# Set derived paths (unified with bash via consistent path resolution)
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
ZSH_DOTFILES="${DOTFILES_ROOT}/zsh"

# Exit if dotfiles not found
if [ ! -d "$DOTFILES_ROOT" ]; then
    echo "❌ Dotfiles directory not found at: $DOTFILES_ROOT" >&2
    return 1
fi

# ═══════════════════════════════════════════════════════════════
# Initialize counter for sourced files (consistent with bash loader)
# ═══════════════════════════════════════════════════════════════

typeset -gi SOURCED_FILES_COUNT=0

# ═══════════════════════════════════════════════════════════════
# Helper: Safe Source Function (consistent with bash loader)
# ═══════════════════════════════════════════════════════════════

safe_source() {
    local file_path="$1"
    local error_msg="${2:-File not found}"

    if [ ! -f "$file_path" ]; then
        # File doesn't exist - silently skip (common for optional files)
        return 0
    fi

    # Source file directly in parent shell (critical for function/alias propagation)
    # NOTE: MUST NOT use $(...) subshell as it breaks function definitions
    . "$file_path" 2>/dev/null
    local source_exit=$?

    if [ $source_exit -eq 0 ]; then
        # Increment counter after successful source
        ((++SOURCED_FILES_COUNT))
        return 0
    fi

    # Source failed - report error for important files
    # Skip errors for optional files (like .local.sh)
    case "$file_path" in
        *.local.sh)
            # Optional local overrides - silently skip
            return 0
            ;;
        */tools/integrations/*|*/functions/*|*/env/*)
            # Important files - report error
            if type ux_error >/dev/null 2>&1; then
                ux_error "${error_msg}: ${file_path}"
            else
                echo "Error: ${error_msg}: ${file_path}" >&2
            fi
            return 1
            ;;
        *)
            # Other files - report error only in debug mode
            if [ "${DEBUG_DOTFILES:-0}" = "1" ]; then
                if type ux_error >/dev/null 2>&1; then
                    ux_error "${error_msg}: ${file_path}"
                else
                    echo "Error: ${error_msg}: ${file_path}" >&2
                fi
            fi
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Phase 1: Load UX Library FIRST (consistent with bash loader)
# Provides: colors, output functions, progress indicators, prompts, tables
# MUST load before any code that uses ux_* functions
# ═══════════════════════════════════════════════════════════════

if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || {
        echo "Warning: Failed to load UX library" >&2
    }
fi

# ═══════════════════════════════════════════════════════════════
# Phase 2: Load Shared Environment Variables (shell-common/env/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/env" ]; then
    for f in "${SHELL_COMMON}"/env/*.sh; do
        case "$f" in
            *.local.sh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load env" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 3: Load Zsh Environment Settings (zsh/env/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${ZSH_DOTFILES}/env" ]; then
    for f in "${ZSH_DOTFILES}"/env/*.zsh; do
        [ -f "$f" ] && safe_source "$f" "Failed to load zsh env" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 4: Load Shared Aliases (shell-common/aliases/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/aliases" ]; then
    for f in "${SHELL_COMMON}"/aliases/*.sh; do
        case "$f" in
            *.local.sh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load alias" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 5: Load Shared Functions (shell-common/functions/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/functions" ]; then
    for f in "${SHELL_COMMON}"/functions/*.sh; do
        case "$f" in
            *.local.sh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load function" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 6: Load Shared Tools - Integrations (shell-common/tools/integrations/)
# 3rd-party integrations: apt, ccusage, claude, codex, git, npm, etc
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/tools/integrations" ]; then
    for f in "${SHELL_COMMON}"/tools/integrations/*.sh; do
        case "$f" in
            *.local.sh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load integration tool" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 7: Load Shared Tools - Custom (shell-common/tools/custom/)
# NOTE: shell-common/tools/custom/ contains executable utility scripts
# that should NOT be auto-sourced. They are meant to be run explicitly
# as commands, not loaded as shell functions. Examples: demo_ux.sh, check_ux_consistency.sh
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Phase 8: Load Shared Projects (shell-common/projects/)
# Project-specific configurations and utilities
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/projects" ]; then
    for f in "${SHELL_COMMON}"/projects/*.sh; do
        case "$f" in
            *.local.sh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load project" || true
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 9: Load Zsh Utilities (zsh/util/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${ZSH_DOTFILES}/util" ]; then
    # Use setopt null_glob to allow empty glob results (e.g., when no .zsh files exist)
    setopt null_glob
    for f in "${ZSH_DOTFILES}"/util/*.zsh; do
        [ -f "$f" ] && safe_source "$f" "Failed to load zsh util" || true
    done
    unsetopt null_glob
fi

# ═══════════════════════════════════════════════════════════════
# Phase 10: Load Zsh Application Modules (zsh/app/)
# ═══════════════════════════════════════════════════════════════

_load_zsh_apps() {
    if [ ! -d "${ZSH_DOTFILES}/app" ]; then
        return 0
    fi

    # Load in specific order for dependencies
    local app_files=(
        "${ZSH_DOTFILES}/app/zsh.zsh"      # Shell management
        "${ZSH_DOTFILES}/app/git.zsh"      # Git commands
    )

    # Load specific files in order
    local f
    for f in "${app_files[@]}"; do
        [ -f "$f" ] && safe_source "$f" "Failed to load zsh app" || true
    done

    # Load any remaining app files not explicitly listed
    for f in "${ZSH_DOTFILES}"/app/*.zsh; do
        # Skip if already loaded
        case "$f" in
            */zsh.zsh|*/git.zsh) continue ;;
        esac
        [ -f "$f" ] && safe_source "$f" "Failed to load zsh app" || true
    done
}

# Execute the loader function
_load_zsh_apps

# ═══════════════════════════════════════════════════════════════
# Export Configuration
# ═══════════════════════════════════════════════════════════════

# Make DOTFILES variables available to subshells
export DOTFILES_ROOT
export SHELL_COMMON
export ZSH_DOTFILES

# ═══════════════════════════════════════════════════════════════
# Completion Message
# ═══════════════════════════════════════════════════════════════

# Display initialization summary (shared function from shell-common)
# Show in interactive shells, unless explicitly disabled
# Note: Will be suppressed automatically in nested/instant-prompt contexts
if [[ -o interactive ]] && type dotfiles_init_summary >/dev/null 2>&1; then
    # Allow suppression via environment variable for special cases (CI/CD, etc.)
    if [[ "${DOTFILES_SUPPRESS_MESSAGE:-0}" != "1" ]]; then
        # Try to suppress in instant-prompt contexts (check stderr)
        # If stderr is not a TTY, we're likely in a nested/piped context
        if [[ -t 2 ]]; then
            dotfiles_init_summary "$SOURCED_FILES_COUNT"
        elif [[ -z "$ZSH_SUBSHELL" ]]; then
            # Not in a zsh subshell, likely safe to show
            dotfiles_init_summary "$SOURCED_FILES_COUNT"
        fi
    fi
fi
