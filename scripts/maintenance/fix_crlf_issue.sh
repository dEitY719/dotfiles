#!/bin/bash

# fix_crlf_issue.sh: Fix CRLF line ending issues and directory permissions
#
# PURPOSE: Resolve shell script syntax errors caused by CRLF line endings
#          and file permission issues in internal company PC environments
#
# WHEN TO RUN: After git clone in environments with different line ending defaults
#
# This script performs three repair operations:
#  1. Fixes git configuration (sets core.autocrlf=false)
#  2. Converts CRLF line endings to LF in shell scripts
#  3. Ensures ~/.config directory exists with correct permissions

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_header() {
    echo -e "${GREEN}=== $1 ===${NC}\n"
}

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_header "Pre-flight Checks"

# Check if we're in dotfiles directory
if [ ! -f "$DOTFILES_DIR/setup.sh" ]; then
    log_error "Not in dotfiles root directory. Current: $DOTFILES_DIR"
    exit 1
fi

log_info "Dotfiles root verified: $DOTFILES_DIR"

# Check if we're in a git repository
if ! git -C "$DOTFILES_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository"
    exit 1
fi

log_info "Git repository verified"

# ============================================================================
# User Confirmation
# ============================================================================

echo -e "\n${YELLOW}This script will perform the following operations:${NC}\n"
echo "  1. Configure git (core.autocrlf=false)"
echo "  2. Reset git index and HEAD"
echo "  3. Convert CRLF → LF in all shell scripts"
echo "  4. Set ~/.config permissions to 700"
echo ""
echo -e "${YELLOW}These changes are safe and can be undone with:${NC}"
echo "  git -C $DOTFILES_DIR config core.autocrlf true   # (if needed)"
echo "  git -C $DOTFILES_DIR checkout HEAD               # (to revert files)"
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Operation cancelled by user"
    exit 0
fi

# ============================================================================
# Step 1: Fix Git Configuration
# ============================================================================

log_header "Step 1: Configuring Git"

if git -C "$DOTFILES_DIR" config core.autocrlf 2>/dev/null | grep -q true; then
    log_warn "core.autocrlf is currently set to true"
fi

git -C "$DOTFILES_DIR" config core.autocrlf false
log_info "Set core.autocrlf=false"

# ============================================================================
# Step 2: Reset Git Index and Files
# ============================================================================

log_header "Step 2: Resetting Git Index"

git -C "$DOTFILES_DIR" rm --cached -r . 2>/dev/null || true
log_info "Removed all files from git index"

git -C "$DOTFILES_DIR" reset --hard HEAD
log_info "Reset working directory to HEAD"

# ============================================================================
# Step 3: Convert Line Endings CRLF → LF
# ============================================================================

log_header "Step 3: Converting CRLF to LF"

# Find all shell-related files
SHELL_FILES=$(find "$DOTFILES_DIR" \
    \( -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \) \
    -type f)

TOTAL_FILES=$(echo "$SHELL_FILES" | wc -l)
CONVERTED_COUNT=0

# Check if any files have CRLF
if echo "$SHELL_FILES" | xargs grep -l $'\r' 2>/dev/null | wc -l > /dev/null; then
    while IFS= read -r file; do
        # Check if file contains CRLF
        if grep -q $'\r' "$file"; then
            # Convert CRLF to LF using sed
            sed -i 's/\r$//' "$file"
            ((CONVERTED_COUNT++))
        fi
    done <<< "$SHELL_FILES"

    log_info "Converted $CONVERTED_COUNT files from CRLF to LF (checked $TOTAL_FILES files)"
else
    log_info "No CRLF line endings found (checked $TOTAL_FILES files)"
fi

# ============================================================================
# Step 4: Fix Directory Permissions
# ============================================================================

log_header "Step 4: Fixing Directory Permissions"

# Create ~/.config if it doesn't exist
if [ ! -d "$HOME/.config" ]; then
    mkdir -p "$HOME/.config"
    log_info "Created ~/.config directory"
else
    log_info "~/.config directory already exists"
fi

# Set permissions to 700 (rwx------)
chmod 700 "$HOME/.config"
log_info "Set ~/.config permissions to 700"

# Remove any dangling symlinks and recreate if needed
if [ -L "$HOME/.config/pg_services.list" ]; then
    if [ ! -e "$HOME/.config/pg_services.list" ]; then
        log_warn "Found dangling symlink: ~/.config/pg_services.list"
        rm "$HOME/.config/pg_services.list"
        log_info "Removed dangling symlink"
    fi
fi

# ============================================================================
# Verification
# ============================================================================

log_header "Verification"

# Verify git configuration
if git -C "$DOTFILES_DIR" config core.autocrlf | grep -q false; then
    log_info "Git configuration verified: core.autocrlf=false"
else
    log_error "Git configuration verification failed"
    exit 1
fi

# Verify no CRLF remains
if find "$DOTFILES_DIR" \( -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \) \
    -type f -exec grep -l $'\r' {} \; 2>/dev/null | wc -l | grep -q 0; then
    log_info "Line ending verification: No CRLF found"
else
    log_warn "Some files still have CRLF endings"
fi

# Verify .config permissions
PERMS=$(stat -c "%a" "$HOME/.config")
if [ "$PERMS" = "700" ]; then
    log_info "Directory permissions verified: ~/.config has 700"
else
    log_warn "Directory permissions: ~/.config has $PERMS (expected 700)"
fi

# ============================================================================
# Summary
# ============================================================================

log_header "Repair Complete"

echo "All repair operations completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Run: source ~/.bashrc  (or close and reopen terminal)"
echo "  2. Try: src  (to test the shell-common/aliases/core.sh function)"
echo "  3. If issues persist, check: locale"
echo ""
echo "For troubleshooting, check:"
echo "  - file /home/bwyoon/dotfiles/shell-common/aliases/core.sh"
echo "  - bash --version"
echo "  - locale"
