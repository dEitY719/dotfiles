#!/bin/bash

# install.sh: Claude and PostgreSQL configuration setup
#
# PURPOSE: Set up Claude IDE and PostgreSQL configurations
# WHEN TO RUN: After ./setup.sh (on initial installation) or anytime (optional)
#
# ⚠️  IMPORTANT DISTINCTION:
# This script is OPTIONAL and supplements ./setup.sh
# It provides Claude IDE integration and PostgreSQL setup
#
# RELATIONSHIP WITH setup.sh:
#   - setup.sh (REQUIRED): Shell environment + symlinks (bash, zsh, git)
#   - install.sh (OPTIONAL): Claude + PostgreSQL setup + symlink re-setup
#
# DOES NOT do:
#   - Set DOTFILES_BASH_DIR or SHELL_COMMON environment variables
#   - Install bash/zsh with special initialization
#
# See SETUP_GUIDE.md for detailed information on script relationships

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# --- Load UX Library ---
UX_LIB_SCRIPT="${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"

if [[ -f "${UX_LIB_SCRIPT}" ]]; then
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

# --- Main Setup ---
ux_header "Dotfiles Setup"

# --- Create ~/.claude directory ---
ux_section "Setting up ~/.claude directory"
mkdir -p "$CLAUDE_DIR"

# --- Function: Create symlink with backup ---
create_symlink() {
    local source="$1"
    local dest="$2"
    local description="$3"

    if [ ! -f "$source" ]; then
        ux_warning "File not found: $source"
        return 1
    fi

    if [ -L "$dest" ]; then
        rm "$dest"
        ux_info "Removed existing symlink: $dest"
    elif [ -f "$dest" ]; then
        local backup_file="${dest}.backup.$(date +%s)"
        mv "$dest" "$backup_file"
        ux_warning "Backed up existing file to: $backup_file"
    fi

    ln -s "$source" "$dest"
    ux_success "Created symlink for $description"
    return 0
}

# --- Setup statusline-command.sh ---
STATUSLINE_SOURCE="$DOTFILES_DIR/claude/statusline-command.sh"
STATUSLINE_DEST="$CLAUDE_DIR/statusline-command.sh"

if create_symlink "$STATUSLINE_SOURCE" "$STATUSLINE_DEST" "statusline-command.sh"; then
    chmod +x "$STATUSLINE_SOURCE"
fi

# --- Setup settings.json ---
SETTINGS_SOURCE="$DOTFILES_DIR/claude/settings.json"
SETTINGS_DEST="$CLAUDE_DIR/settings.json"

create_symlink "$SETTINGS_SOURCE" "$SETTINGS_DEST" "settings.json"

# --- Setup Claude Agents ---
ux_section "Setting up Claude agents"
AGENTS_SOURCE_DIR="$DOTFILES_DIR/claude"
AGENTS_DEST_DIR="$CLAUDE_DIR/agents"

if [ -d "$AGENTS_SOURCE_DIR" ]; then
    mkdir -p "$AGENTS_DEST_DIR"

    for agent_file in "$AGENTS_SOURCE_DIR"/*.md; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file")
            agent_dest="$AGENTS_DEST_DIR/$agent_name"

            if [ -L "$agent_dest" ]; then
                rm "$agent_dest"
                ux_info "Removed existing symlink: $agent_dest"
            elif [ -f "$agent_dest" ]; then
                backup_file="$agent_dest.backup.$(date +%s)"
                mv "$agent_dest" "$backup_file"
                ux_warning "Backed up existing file to: $backup_file"
            fi

            ln -s "$agent_file" "$agent_dest"
            ux_success "Created symlink for $(basename "$agent_dest")"
        fi
    done
else
    ux_warning "Claude agents directory not found: $AGENTS_SOURCE_DIR"
fi

# --- Setup PostgreSQL Services Config ---
ux_section "Setting up PostgreSQL services config"
PG_CONFIG_DIR="$HOME/.config"
mkdir -p "$PG_CONFIG_DIR"

PG_SOURCE="$DOTFILES_DIR/shell-common/config/pg_services.list"
PG_DEST="$PG_CONFIG_DIR/pg_services.list"

create_symlink "$PG_SOURCE" "$PG_DEST" "pg_services.list"

# --- Setup Bash Configuration ---
ux_section "Setting up Bash configuration"
BASH_SOURCE="$DOTFILES_DIR/bash/main.bash"
BASH_DEST="$HOME/.bashrc"

create_symlink "$BASH_SOURCE" "$BASH_DEST" ".bashrc"

# --- Setup Zsh Configuration ---
ux_section "Setting up Zsh configuration"
ZSH_SOURCE="$DOTFILES_DIR/zsh/main.zsh"
ZSH_DEST="$HOME/.zshrc"

create_symlink "$ZSH_SOURCE" "$ZSH_DEST" ".zshrc"

# --- Completion Message ---
ux_header "Setup Complete"
ux_section "Next steps"
ux_bullet "Review ~/.claude/statusline-command.sh"
ux_bullet "Review ~/.claude/settings.json (synced from dotfiles)"
ux_bullet "Configure other dotfiles as needed"
echo ""
