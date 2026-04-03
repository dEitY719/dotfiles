#!/bin/sh
# shell-common/functions/ghostty.sh
# Ghostty terminal configuration management

ghostty_init() {
    local source="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"
    local target="$HOME/.config/ghostty/config"

    echo "Initializing Ghostty configuration..."

    # Create directory if needed
    if [ ! -d "$(dirname "$target")" ]; then
        echo "Creating $(dirname "$target") directory..."
        mkdir -p "$(dirname "$target")"
    fi

    # Remove auto-generated config.ghostty if empty
    if [ -f "$HOME/.config/ghostty/config.ghostty" ]; then
        if [ ! -s "$HOME/.config/ghostty/config.ghostty" ]; then
            rm "$HOME/.config/ghostty/config.ghostty"
            echo "Removed empty config.ghostty (auto-generated)"
        fi
    fi

    # Handle symbolic link
    if [ -L "$target" ]; then
        echo "config symbolic link already exists"
    elif [ -f "$target" ]; then
        echo "config exists as regular file"
        echo "Backing up to config.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        echo "Created symbolic link for config"
    else
        ln -s "$source" "$target"
        echo "Created symbolic link for config"
    fi

    echo ""
    echo "Ghostty configuration initialization complete!"
    echo ""
    echo "Symbolic link:"
    ls -la "$target"
}

ghostty_edit_config() {
    local config_file="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"

    if [ ! -f "$config_file" ]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    echo "Editing Ghostty configuration..."
    echo "File: $config_file"
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    echo "Configuration file edited"
    echo "Changes will take effect immediately (symlinked)"
}
