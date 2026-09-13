#!/bin/bash
# shell-common/tools/custom/install_agy.sh
# Antigravity CLI (agy) 설치 스크립트 (대화형)
# 공식 설치: curl -fsSL https://antigravity.google/cli/install.sh | bash

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

INSTALL_URL="https://antigravity.google/cli/install.sh"

# The upstream installer ends with a bare `agy install`, which edits shell
# profiles, and install.sh gives no way to pass --skip-path. ~/.bashrc and
# ~/.zshrc are symlinks into dotfiles, so those edits land on tracked files
# (#1802). Snapshot their git state before the install and revert after.

# Resolve ~/.bashrc / ~/.zshrc to their dotfiles targets (symlinks only).
_agy_tracked_rc_files() {
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -L "$rc" ]; then
            readlink -f "$rc"
        fi
    done
}

# Print "<clean|dirty> <file>" for each tracked rc file inside a git work tree.
_agy_rc_snapshot() {
    local f dir
    _agy_tracked_rc_files | while IFS= read -r f; do
        dir="$(dirname "$f")"
        git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
        if git -C "$dir" diff --quiet -- "$f"; then
            echo "clean $f"
        else
            echo "dirty $f"
        fi
    done
}

# Revert edits to files that were clean before the install (every change is
# the installer's). Files already dirty are only reported: they may hold the
# user's own edits.
_agy_restore_rc_files() {
    local state f dir
    printf '%s\n' "$1" | while read -r state f; do
        [ -n "$f" ] || continue
        dir="$(dirname "$f")"
        if [ "$state" = "dirty" ]; then
            ux_warning "$f had uncommitted changes before install; not reverting."
            ux_info "Review installer edits: git -C $dir diff -- $f"
        elif ! git -C "$dir" diff --quiet -- "$f"; then
            git -C "$dir" checkout -- "$f" &&
                ux_info "Reverted agy installer edits to $f (PATH is managed by shell-common/env/path.sh)"
        fi
    done
}

# Main script
main() {
    clear
    ux_header "Antigravity CLI (agy) Installer"
    ux_info "This script installs the Antigravity CLI (agy) via the official install script."

    ux_section "Setup Process"
    ux_numbered 1 "Check for curl."
    ux_numbered 2 "Run the official install script (${INSTALL_URL})."
    ux_numbered 3 "Verify the installation."
    echo ""

    ux_info "The official installer edits your shell profile (PATH/aliases)."
    ux_info "Edits to symlinked dotfiles rc files are reverted (PATH SSOT: shell-common/env/path.sh)."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check curl
    # ========================================
    ux_step "1/3" "Checking for curl..."
    if ! ux_require "curl"; then exit 1; fi
    ux_success "curl is installed: $(curl --version | head -n1)"
    echo ""

    # ========================================
    # Step 2: Install Antigravity CLI
    # ========================================
    ux_step "2/3" "Installing Antigravity CLI..."
    if ux_confirm "Run '${INSTALL_URL}' installer now?" "y"; then
        local rc_snapshot install_rc=0
        rc_snapshot="$(_agy_rc_snapshot)"
        ux_with_spinner "Installing agy" bash -c "set -o pipefail; curl -fsSL '${INSTALL_URL}' | bash" || install_rc=$?
        _agy_restore_rc_files "$rc_snapshot"
        if [ "$install_rc" -ne 0 ]; then
            ux_error "Antigravity CLI installation failed."
            exit 1
        fi
    else
        ux_info "Step 2 skipped by user."
        echo ""
        ux_header "Antigravity CLI Setup Finished"
        exit 0
    fi

    # ========================================
    # Step 3: Verify installation
    # ========================================
    ux_step "3/3" "Verifying installation..."
    if command -v agy >/dev/null 2>&1; then
        ux_success "Antigravity CLI command found: $(command -v agy)"
        agy --version || ux_warning "Could not determine agy version."
    else
        ux_error "agy command not found after installation."
        ux_warning "Check your PATH and restart your terminal."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "Antigravity CLI Setup Complete!"
    ux_section "Next Steps"
    ux_bullet "Check your PATH if the command is not found: ${UX_PRIMARY}echo \$PATH${UX_RESET}"
    ux_bullet "View help: ${UX_PRIMARY}agy --help${UX_RESET}"
    echo ""
    ux_info "For more project-specific commands, run: ${UX_PRIMARY}agy-help${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
