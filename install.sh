#!/bin/bash

# Dotfiles installation script
# Sets up symlinks and configuration files for the dotfiles repository

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${BLUE}===== Dotfiles Setup =====${RESET}"

# Create ~/.claude directory if it doesn't exist
echo -e "${BLUE}Creating ~/.claude directory...${RESET}"
mkdir -p "$CLAUDE_DIR"

# Create symlink for claude-statusline-command.sh
STATUSLINE_SOURCE="$DOTFILES_DIR/bash/custom-script/claude-statusline-command.sh"
STATUSLINE_DEST="$CLAUDE_DIR/statusline-command.sh"

if [ ! -f "$STATUSLINE_SOURCE" ]; then
    echo -e "${YELLOW}Warning: $STATUSLINE_SOURCE not found${RESET}"
else
    if [ -L "$STATUSLINE_DEST" ]; then
        # Remove existing symlink
        rm "$STATUSLINE_DEST"
        echo -e "${GREEN}Removed existing symlink: $STATUSLINE_DEST${RESET}"
    elif [ -f "$STATUSLINE_DEST" ]; then
        # Backup existing file
        backup_file="$STATUSLINE_DEST.backup.$(date +%s)"
        mv "$STATUSLINE_DEST" "$backup_file"
        echo -e "${YELLOW}Backed up existing file to: $backup_file${RESET}"
    fi

    # Create new symlink
    ln -s "$STATUSLINE_SOURCE" "$STATUSLINE_DEST"
    chmod +x "$STATUSLINE_SOURCE"
    echo -e "${GREEN}Created symlink: $STATUSLINE_DEST -> $STATUSLINE_SOURCE${RESET}"
fi

echo -e "${GREEN}===== Setup Complete =====${RESET}"
echo -e "${BLUE}Next steps:${RESET}"
echo "  1. Review ~/.claude/statusline-command.sh"
echo "  2. Configure other dotfiles as needed"
