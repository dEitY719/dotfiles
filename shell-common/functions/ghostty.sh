#!/bin/sh
# shell-common/functions/ghostty.sh
# Ghostty terminal configuration management

ghostty_init() {
    local source="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"
    local target="$HOME/.config/ghostty/config"

    local target_dir="$(dirname "$target")"

    if type ux_info >/dev/null 2>&1; then
        ux_info "Initializing Ghostty configuration..."
    else
        echo "Initializing Ghostty configuration..."
    fi

    # Create directory if needed
    if [ ! -d "$target_dir" ]; then
        echo "Creating $target_dir directory..."
        mkdir -p "$target_dir"
    fi

    # Ghostty snap auto-generates an empty config.ghostty on first run;
    # remove it to avoid confusion with our managed config file.
    if [ -f "$target_dir/config.ghostty" ]; then
        if [ ! -s "$target_dir/config.ghostty" ]; then
            rm "$target_dir/config.ghostty"
            echo "Removed empty config.ghostty (auto-generated)"
        fi
    fi

    # Handle symbolic link (including dangling symlinks)
    if [ -L "$target" ]; then
        if [ -e "$target" ]; then
            echo "config symbolic link already exists"
        else
            echo "Removing dangling symbolic link..."
            rm -f "$target"
            ln -s "$source" "$target"
            echo "Created symbolic link for config"
        fi
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
    if type ux_success >/dev/null 2>&1; then
        ux_success "Ghostty configuration initialization complete!"
        echo ""
        ux_info "Symbolic link:"
    else
        echo "Ghostty configuration initialization complete!"
        echo ""
        echo "Symbolic link:"
    fi
    ls -la "$target"
}

ghostty_edit_config() {
    local config_file="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"

    if [ ! -f "$config_file" ]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    if type ux_info >/dev/null 2>&1; then
        ux_info "Editing Ghostty configuration..."
        ux_info "File: $config_file"
    else
        echo "Editing Ghostty configuration..."
        echo "File: $config_file"
    fi
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    if type ux_success >/dev/null 2>&1; then
        ux_success "Configuration file edited"
        ux_info "Changes will take effect immediately (symlinked)"
    else
        echo "Configuration file edited"
        echo "Changes will take effect immediately (symlinked)"
    fi
}
