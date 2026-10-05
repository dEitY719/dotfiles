#!/bin/bash
# Install Git Hooks to a Project
#
# Usage:
#   ~/dotfiles/git/hooks/install-hooks.sh <project-path> [--force]
#
# Example:
#   ~/dotfiles/git/hooks/install-hooks.sh ~/workspace/project-a
#   ~/dotfiles/git/hooks/install-hooks.sh . --force

set -u

# ═══════════════════════════════════════════════════════════════════════════
# Parameters
# ═══════════════════════════════════════════════════════════════════════════

install_hooks_help() {
    echo "Usage: $(basename "$0") <project-path> [--force]"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") ~/workspace/project-a"
    echo "  $(basename "$0") . --force"
}

case "${1:-}" in
    -h|--help) install_hooks_help; exit 0 ;;
esac

if [ $# -lt 1 ]; then
    install_hooks_help
    exit 1
fi

PROJECT_PATH="$1"
FORCE="${2:---}"

# Absolute path to this script's directory
HOOKS_SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ux_lib lives in the same dotfiles checkout as this script (git/hooks/ ->
# shell-common/), so it is always present; usage above stays raw for the
# byte-identical help contract (#1915).
# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
source "${HOOKS_SOURCE_DIR}/../../shell-common/tools/ux_lib/ux_lib.sh"

# Get absolute paths
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd)
if [ ! -d "$PROJECT_PATH/.git" ]; then
    ux_error "Not a git repository: $1"
    exit 1
fi

GIT_HOOKS_DIR="${PROJECT_PATH}/.git/hooks"

# ═══════════════════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════════════════

mkdir -p "$GIT_HOOKS_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# Install Hooks
# ═══════════════════════════════════════════════════════════════════════════

ux_info "Installing hooks to: $GIT_HOOKS_DIR"

# post-commit hook
POST_COMMIT_TARGET="${GIT_HOOKS_DIR}/post-commit"
POST_COMMIT_SOURCE="${HOOKS_SOURCE_DIR}/post-commit.generic"

if [ -e "$POST_COMMIT_TARGET" ] && [ "$FORCE" != "--force" ]; then
    ux_warning "post-commit hook already exists: $POST_COMMIT_TARGET"
    ux_bullet_sub "Use --force to overwrite"
else
    # Remove existing symlink or file
    if [ -L "$POST_COMMIT_TARGET" ] || [ -f "$POST_COMMIT_TARGET" ]; then
        rm "$POST_COMMIT_TARGET"
    fi

    # Create symlink
    ln -s "$POST_COMMIT_SOURCE" "$POST_COMMIT_TARGET"
    chmod +x "$POST_COMMIT_TARGET"
    ux_success "Created symlink:"
    ux_bullet_sub "Target: $POST_COMMIT_TARGET"
    ux_bullet_sub "Source: $POST_COMMIT_SOURCE"
fi

ux_success "Installation complete!"
ux_info "To verify: ls -la \"$POST_COMMIT_TARGET\""

ux_section "Pre-push policy (this repo only, since issue #754)"
ux_bullet "The dotfiles repo itself runs the full pytest suite via the pre-push hook (\"mise run test\") instead of GitHub Actions."
ux_bullet "This install script only wires post-commit for downstream projects — the pre-push hook here is managed via core.hooksPath set by ./setup.sh."
ux_bullet "Opt-out for the local pytest layer: SKIP_LOCAL_PYTEST=1 git push   # WIP push, intentional fail"
ux_warning "--no-verify bypasses ALL hook layers (protected-branch, leak guard, AND mise run test)."
ux_bullet_sub "Do NOT use --no-verify as a habit; prefer SKIP_LOCAL_PYTEST=1 (narrow opt-out) and fix the underlying test failure."
ux_bullet_sub "SSOT: docs/.ssot/local-test-policy.md"
