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

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "$0") <project-path> [--force]"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") ~/workspace/project-a"
    echo "  $(basename "$0") . --force"
    exit 1
fi

PROJECT_PATH="$1"
FORCE="${2:---}"

# Get absolute paths
PROJECT_PATH=$(cd "$PROJECT_PATH" 2>/dev/null && pwd)
if [ ! -d "$PROJECT_PATH/.git" ]; then
    echo "Error: Not a git repository: $1"
    exit 1
fi

# Absolute path to this script's directory
HOOKS_SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GIT_HOOKS_DIR="${PROJECT_PATH}/.git/hooks"

# ═══════════════════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════════════════

mkdir -p "$GIT_HOOKS_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# Install Hooks
# ═══════════════════════════════════════════════════════════════════════════

echo "Installing hooks to: $GIT_HOOKS_DIR"
echo ""

# post-commit hook
POST_COMMIT_TARGET="${GIT_HOOKS_DIR}/post-commit"
POST_COMMIT_SOURCE="${HOOKS_SOURCE_DIR}/post-commit.generic"

if [ -e "$POST_COMMIT_TARGET" ] && [ "$FORCE" != "--force" ]; then
    echo "⚠ post-commit hook already exists: $POST_COMMIT_TARGET"
    echo "  Use --force to overwrite"
else
    # Remove existing symlink or file
    if [ -L "$POST_COMMIT_TARGET" ] || [ -f "$POST_COMMIT_TARGET" ]; then
        rm "$POST_COMMIT_TARGET"
    fi

    # Create symlink
    ln -s "$POST_COMMIT_SOURCE" "$POST_COMMIT_TARGET"
    chmod +x "$POST_COMMIT_TARGET"
    echo "✓ Created symlink:"
    echo "  Target: $POST_COMMIT_TARGET"
    echo "  Source: $POST_COMMIT_SOURCE"
fi

echo ""
echo "Installation complete!"
echo ""
echo "To verify:"
echo "  ls -la \"$POST_COMMIT_TARGET\""
