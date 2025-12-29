#!/bin/zsh

# zsh/main.zsh
# Zsh Dotfiles Loader (SOLID Principle Compliant)
# Completely independent from bash - no emulation, native zsh execution

# Exit if not in zsh
[ -n "$ZSH_VERSION" ] || return 0

# ═══════════════════════════════════════════════════════════════
# Directory Setup
# ═══════════════════════════════════════════════════════════════

DOTFILES_ROOT="${HOME}/dotfiles"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
ZSH_DOTFILES="${DOTFILES_ROOT}/zsh"

# Exit if dotfiles not found
if [ ! -d "$DOTFILES_ROOT" ]; then
    echo "Warning: Dotfiles directory not found at $DOTFILES_ROOT" >&2
    return 1
fi

# ═══════════════════════════════════════════════════════════════
# Phase 1: Load Shared Environment Variables (shell-common/env/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/env" ]; then
    for f in "${SHELL_COMMON}"/env/*.sh; do
        if [ -f "$f" ]; then
            # Source with error handling
            if ! source "$f" 2>/dev/null; then
                echo "Warning: Failed to load $f" >&2
            fi
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 2: Load Shared Aliases (shell-common/aliases/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/aliases" ]; then
    for f in "${SHELL_COMMON}"/aliases/*.sh; do
        if [ -f "$f" ]; then
            source "$f" 2>/dev/null || true
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 3: Load Shared Functions (shell-common/functions/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${SHELL_COMMON}/functions" ]; then
    for f in "${SHELL_COMMON}"/functions/*.sh; do
        if [ -f "$f" ]; then
            source "$f" 2>/dev/null || true
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 4: Load Zsh UX Library
# ═══════════════════════════════════════════════════════════════

if [ -f "${ZSH_DOTFILES}/ux_lib/ux_lib.zsh" ]; then
    source "${ZSH_DOTFILES}/ux_lib/ux_lib.zsh" 2>/dev/null || {
        echo "Warning: Failed to load UX library" >&2
    }
fi

# ═══════════════════════════════════════════════════════════════
# Phase 5: Load Zsh Environment Settings (zsh/env/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${ZSH_DOTFILES}/env" ]; then
    for f in "${ZSH_DOTFILES}"/env/*.zsh; do
        [ -f "$f" ] && source "$f" 2>/dev/null || true
    done 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════
# Phase 6: Load Zsh Utilities (zsh/util/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${ZSH_DOTFILES}/util" ]; then
    for f in "${ZSH_DOTFILES}"/util/*.zsh; do
        if [ -f "$f" ]; then
            source "$f" 2>/dev/null || true
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════
# Phase 7: Load Zsh Application Modules (zsh/app/)
# ═══════════════════════════════════════════════════════════════

if [ -d "${ZSH_DOTFILES}/app" ]; then
    # Load in specific order for dependencies
    local app_files=(
        "${ZSH_DOTFILES}/app/zsh.zsh"      # Shell management
        "${ZSH_DOTFILES}/app/git.zsh"      # Git commands
    )

    # Load specific files in order
    for f in "${app_files[@]}"; do
        if [ -f "$f" ]; then
            source "$f" 2>/dev/null || true
        fi
    done

    # Load any remaining app files not explicitly listed
    for f in "${ZSH_DOTFILES}"/app/*.zsh; do
        # Skip if already loaded
        case "$f" in
            */zsh.zsh|*/git.zsh) continue ;;
        esac
        if [ -f "$f" ]; then
            source "$f" 2>/dev/null || true
        fi
    done
fi

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

# Only show message if UX library is loaded
if type ux_success >/dev/null 2>&1; then
    # Uncomment for debugging:
    # ux_success "Zsh dotfiles loaded successfully"
    :
fi
