#!/bin/sh
# shell-common/tools/custom/delete_claude.sh
# Claude Code CLI Uninstall Script
# Safely removes Claude Code binary and cleans cached/session data

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

delete_claude() {
    ux_header "Claude Code CLI Uninstaller"
    echo ""
    ux_info "This will remove Claude Code binary and clean cached/session data."
    ux_warning "Important: Your projects, downloads, and configuration will be preserved"
    echo ""

    ux_section "What will be removed:"
    ux_bullet "Binary: \$HOME/.local/bin/claude"
    ux_bullet "Cache/Runtime: \$HOME/.local/share/claude"
    ux_bullet "Session data (cache, history, debug logs)"
    echo ""

    ux_section "What will be preserved:"
    ux_bullet "Projects: \$HOME/.claude/projects/ ✅"
    ux_bullet "Downloads: \$HOME/.claude/downloads/ ✅"
    ux_bullet "Settings: \$HOME/.claude/settings.json (symlink) ✅"
    ux_bullet "Skills/Docs: Configured via dotfiles ✅"
    echo ""

    if ! ux_confirm "Do you want to continue?" "n"; then
        ux_info "Uninstallation cancelled."
        return 0
    fi

    local removed_count=0
    local failed_count=0

    # ========================================
    # Remove Native Installer Binary
    # ========================================
    ux_section "Step 1: Removing Binary"
    if [ -f "$HOME/.local/bin/claude" ]; then
        ux_info "Removing \$HOME/.local/bin/claude..."
        if rm -f "$HOME/.local/bin/claude"; then
            ux_success "Binary removed"
            removed_count=$((removed_count + 1))
        else
            ux_warning "Failed to remove binary"
            failed_count=$((failed_count + 1))
        fi
    else
        ux_info "\$HOME/.local/bin/claude not found (already removed)"
    fi

    # ========================================
    # Remove runtime/cache data
    # ========================================
    ux_section "Step 2: Cleaning Runtime Data"
    if [ -d "$HOME/.local/share/claude" ]; then
        ux_info "Removing \$HOME/.local/share/claude..."
        if rm -rf "$HOME/.local/share/claude"; then
            ux_success "Runtime data removed"
            removed_count=$((removed_count + 1))
        else
            ux_warning "Failed to remove runtime data"
            failed_count=$((failed_count + 1))
        fi
    else
        ux_info "\$HOME/.local/share/claude not found"
    fi

    # ========================================
    # Clean session cache (safe to delete)
    # ========================================
    ux_section "Step 3: Cleaning Session Cache"
    local cache_dirs="cache debug shell-snapshots session-env paste-cache stats-cache.json"
    for cache_dir in $cache_dirs; do
        local cache_path="$HOME/.claude/$cache_dir"
        if [ -e "$cache_path" ]; then
            ux_info "Removing \$HOME/.claude/$cache_dir..."
            if rm -rf "$cache_path"; then
                ux_success "$cache_dir removed"
                removed_count=$((removed_count + 1))
            else
                ux_warning "Failed to remove $cache_dir"
                failed_count=$((failed_count + 1))
            fi
        fi
    done

    # ========================================
    # Check for other installation methods
    # ========================================
    ux_section "Step 4: Checking Alternative Installations"

    # Homebrew
    if command -v brew &>/dev/null && brew list --cask claude-code &>/dev/null 2>&1; then
        ux_info "Homebrew installation detected"
        if ux_confirm "Remove Claude Code via Homebrew?" "y"; then
            if brew uninstall --cask claude-code; then
                ux_success "Homebrew installation removed"
                removed_count=$((removed_count + 1))
            else
                ux_warning "Failed to remove Homebrew installation"
                failed_count=$((failed_count + 1))
            fi
        fi
    fi

    # WinGet (Windows)
    if command -v winget &>/dev/null; then
        ux_info "WinGet detected (Windows)"
        if ux_confirm "Remove Claude Code via WinGet?" "y"; then
            if winget uninstall Anthropic.ClaudeCode; then
                ux_success "WinGet installation removed"
                removed_count=$((removed_count + 1))
            else
                ux_warning "Failed to remove WinGet installation"
                failed_count=$((failed_count + 1))
            fi
        fi
    fi

    # NPM (legacy method)
    if command -v npm &>/dev/null && npm list -g @anthropic-ai/claude-code &>/dev/null 2>&1; then
        ux_info "NPM installation detected (legacy)"
        if ux_confirm "Remove Claude Code via NPM?" "y"; then
            if npm uninstall -g @anthropic-ai/claude-code; then
                ux_success "NPM installation removed"
                removed_count=$((removed_count + 1))
            else
                ux_warning "Failed to remove NPM installation"
                failed_count=$((failed_count + 1))
            fi
        fi
    fi

    # ========================================
    # Verification
    # ========================================
    echo ""
    ux_header "✅ Claude Code Uninstallation Complete"
    ux_section "Summary"
    echo "Successfully removed: $removed_count item(s)"
    if [ "$failed_count" -gt 0 ]; then
        echo "Failed to remove: $failed_count item(s)"
    fi
    echo ""

    if command -v claude &>/dev/null; then
        ux_warning "Claude command still found in PATH"
        ux_info "Run: ${UX_INFO}which claude${UX_RESET} to locate"
    else
        ux_success "Claude command not found (clean removal) ✅"
    fi

    echo ""
    ux_section "Preserved Data"
    echo "Your data is safe:"
    if [ -d "$HOME/.claude/projects" ]; then
        ux_bullet "Projects directory: $(du -sh "$HOME/.claude/projects" 2>/dev/null | cut -f1)"
    fi
    if [ -d "$HOME/.claude/downloads" ]; then
        ux_bullet "Downloads: $(du -sh "$HOME/.claude/downloads" 2>/dev/null | cut -f1)"
    fi
    echo ""

    ux_section "Next Steps"
    ux_info "To reinstall Claude Code and restore settings:"
    ux_bullet "Run: ${UX_INFO}clinstall${UX_RESET}"
    ux_bullet "Then: ${UX_INFO}claude_init${UX_RESET} (to restore symlinks)"
    echo ""
}

# Execute only if run directly (not sourced)
if [ "${0##*/}" = "delete_claude.sh" ]; then
    delete_claude "$@"
fi
