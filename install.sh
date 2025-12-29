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

# Create symlink for statusline-command.sh
STATUSLINE_SOURCE="$DOTFILES_DIR/claude/statusline-command.sh"
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

# Create symlink for settings.json
SETTINGS_SOURCE="$DOTFILES_DIR/claude/settings.json"
SETTINGS_DEST="$CLAUDE_DIR/settings.json"

if [ ! -f "$SETTINGS_SOURCE" ]; then
    echo -e "${YELLOW}Warning: $SETTINGS_SOURCE not found${RESET}"
else
    if [ -L "$SETTINGS_DEST" ]; then
        # Remove existing symlink
        rm "$SETTINGS_DEST"
        echo -e "${GREEN}Removed existing symlink: $SETTINGS_DEST${RESET}"
    elif [ -f "$SETTINGS_DEST" ]; then
        # Backup existing file
        backup_file="$SETTINGS_DEST.backup.$(date +%s)"
        mv "$SETTINGS_DEST" "$backup_file"
        echo -e "${YELLOW}Backed up existing file to: $backup_file${RESET}"
    fi

    # Create new symlink
    ln -s "$SETTINGS_SOURCE" "$SETTINGS_DEST"
    echo -e "${GREEN}Created symlink: $SETTINGS_DEST -> $SETTINGS_SOURCE${RESET}"
fi

# Create symlinks for Claude agents markdown files
AGENTS_SOURCE_DIR="$DOTFILES_DIR/claude"
AGENTS_DEST_DIR="$CLAUDE_DIR/agents"

if [ -d "$AGENTS_SOURCE_DIR" ]; then
    echo -e "${BLUE}Setting up Claude agents...${RESET}"
    mkdir -p "$AGENTS_DEST_DIR"

    # Find all markdown files in agents source directory
    for agent_file in "$AGENTS_SOURCE_DIR"/*.md; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file")
            agent_dest="$AGENTS_DEST_DIR/$agent_name"

            if [ -L "$agent_dest" ]; then
                # Remove existing symlink
                rm "$agent_dest"
                echo -e "${GREEN}Removed existing symlink: $agent_dest${RESET}"
            elif [ -f "$agent_dest" ]; then
                # Backup existing file
                backup_file="$agent_dest.backup.$(date +%s)"
                mv "$agent_dest" "$backup_file"
                echo -e "${YELLOW}Backed up existing file to: $backup_file${RESET}"
            fi

            # Create new symlink
            ln -s "$agent_file" "$agent_dest"
            echo -e "${GREEN}Created symlink: $agent_dest -> $agent_file${RESET}"
        fi
    done
else
    echo -e "${YELLOW}Warning: $AGENTS_SOURCE_DIR not found${RESET}"
fi

# Create symlink for pg_services.list
echo -e "${BLUE}Setting up PostgreSQL services config...${RESET}"
PG_CONFIG_DIR="$HOME/.config"
mkdir -p "$PG_CONFIG_DIR"

PG_SOURCE="$DOTFILES_DIR/shell-common/config/pg_services.list"
PG_DEST="$PG_CONFIG_DIR/pg_services.list"

if [ ! -f "$PG_SOURCE" ]; then
    echo -e "${YELLOW}Warning: $PG_SOURCE not found${RESET}"
else
    if [ -L "$PG_DEST" ]; then
        rm "$PG_DEST"
        echo -e "${GREEN}Removed existing symlink: $PG_DEST${RESET}"
    elif [ -f "$PG_DEST" ]; then
        backup_file="$PG_DEST.backup.$(date +%s)"
        mv "$PG_DEST" "$backup_file"
        echo -e "${YELLOW}Backed up existing file to: $backup_file${RESET}"
    fi

    ln -s "$PG_SOURCE" "$PG_DEST"
    echo -e "${GREEN}Created symlink: $PG_DEST -> $PG_SOURCE${RESET}"
fi

echo -e "${GREEN}===== Setup Complete =====${RESET}"
echo -e "${BLUE}Next steps:${RESET}"
echo "  1. Review ~/.claude/statusline-command.sh"
echo "  2. Review ~/.claude/settings.json (synced from dotfiles)"
echo "  3. Configure other dotfiles as needed"
