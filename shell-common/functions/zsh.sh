#!/bin/bash
# shell-common/functions/zsh.sh
# Zsh shell management functions
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Zsh Helper Functions
# ═══════════════════════════════════════════════════════════════

# Check if zsh is installed
_zsh_check_installed() {
    if ! command -v zsh >/dev/null 2>&1; then
        ux_error "zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Check if oh-my-zsh is installed
_zsh_check_omz() {
    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        ux_warning "oh-my-zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Get current zsh version
zsh_version() {
    if _zsh_check_installed; then
        zsh --version
    fi
}

# List all available zsh themes
zsh_themes() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Available Zsh Themes"
    ux_info "Located in: ${UX_BOLD}~/.oh-my-zsh/themes/${UX_RESET}"
    echo ""

    local themes_dir="${HOME}/.oh-my-zsh/themes"
    if [ -d "$themes_dir" ]; then
        echo "Available themes:"
        find "$themes_dir" -maxdepth 1 -name "*.zsh-theme" -printf '%f\n' | sed 's/\.zsh-theme$//' | sort | nl
    else
        ux_error "Themes directory not found."
        return 1
    fi
}

# Change zsh theme
zsh_theme() {
    if ! _zsh_check_omz; then
        return 1
    fi

    if [ -z "$1" ]; then
        ux_usage "zsh-theme" "<theme-name>" "Change zsh theme"
        ux_bullet "Available themes: ${UX_BOLD}zsh-themes${UX_RESET}"
        ux_bullet "Example: ${UX_BOLD}zsh-theme powerlevel10k${UX_RESET}"
        return 1
    fi

    local theme_name="$1"
    local zshrc="${HOME}/.zshrc"

    if [ ! -f "$zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    # Use sed to update the ZSH_THEME line
    if sed -i.bak "s/^ZSH_THEME=.*/ZSH_THEME=\"$theme_name\"/" "$zshrc"; then
        ux_success "Theme changed to: ${UX_BOLD}$theme_name${UX_RESET}"
        ux_info "Run ${UX_BOLD}zsh-reload${UX_RESET} or restart zsh to apply changes."
    else
        ux_error "Failed to change theme."
        return 1
    fi
}

# Get current zsh theme
zsh_theme_current() {
    if [ ! -f "${HOME}/.zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    local current_theme
    current_theme=$(grep "^ZSH_THEME=" "${HOME}/.zshrc" | cut -d'"' -f2)
    if [ -z "$current_theme" ]; then
        ux_warning "No theme set."
    else
        ux_info "Current theme: ${UX_BOLD}$current_theme${UX_RESET}"
    fi
}

# List installed zsh plugins
zsh_plugins() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Installed Zsh Plugins"
    ux_info "Location: ${UX_BOLD}~/.oh-my-zsh/custom/plugins/${UX_RESET}"
    echo ""

    local plugins_dir="${HOME}/.oh-my-zsh/custom/plugins"
    if [ -d "$plugins_dir" ]; then
        ux_section "Custom Plugins"
        if [ -n "$(find "$plugins_dir" -maxdepth 1 -type d ! -name "." 2>/dev/null)" ]; then
            find "$plugins_dir" -maxdepth 1 -type d ! -name "." -printf '%f\n' | sort | nl
        else
            ux_warning "No custom plugins installed."
        fi
    fi

    echo ""
    ux_section "Built-in Plugins"
    ux_info "Location: ${UX_BOLD}~/.oh-my-zsh/plugins/${UX_RESET}"
    echo "Popular plugins:"
    ux_bullet "git - Git aliases and functions"
    ux_bullet "zsh-autosuggestions - Command auto-completion"
    ux_bullet "zsh-syntax-highlighting - Syntax highlighting"
    ux_bullet "extract - Extract various archive formats"
    ux_bullet "web-search - Quick web search from CLI"
    ux_bullet "timer - Simple timer functionality"
}

# Update oh-my-zsh to latest version
zsh_update() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Updating Oh-My-Zsh"
    local omz_dir="${HOME}/.oh-my-zsh"

    if [ -d "$omz_dir/.git" ]; then
        ux_info "Updating from Git repository..."
        cd "$omz_dir" || return 1
        git pull
        ux_success "Oh-My-Zsh updated successfully."
    else
        ux_error "Oh-My-Zsh was not installed via Git."
        return 1
    fi
}

# Reload zsh configuration (POSIX-compatible version)
zsh_reload() {
    if [ -f "${HOME}/.zshrc" ]; then
        ux_info "Reloading zsh configuration..."
        if [ -n "$ZSH_VERSION" ]; then
            # We're in zsh, source directly
            source "${HOME}/.zshrc"
            ux_success "Zsh configuration reloaded."
        else
            # We're in bash, notify user
            ux_warning "You are currently in bash. Switch to zsh first to reload configuration."
            ux_info "Run: ${UX_BOLD}zsh-switch${UX_RESET}"
        fi
    else
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi
}

# Open zsh configuration in editor
zsh_edit() {
    local zshrc="${HOME}/.zshrc"
    if [ ! -f "$zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    ux_info "Opening \$HOME/.zshrc in editor..."
    if [ -n "$EDITOR" ]; then
        "$EDITOR" "$zshrc"
    elif command -v nano >/dev/null 2>&1; then
        nano "$zshrc"
    elif command -v vi >/dev/null 2>&1; then
        vi "$zshrc"
    else
        ux_error "No editor found."
        return 1
    fi
}

# Create/Edit zsh config snippet
zsh_snippet() {
    if [ -z "$1" ]; then
        ux_usage "zsh-snippet" "<snippet-name>" "Create or edit a config snippet"
        ux_bullet "Example: ${UX_BOLD}zsh-snippet aliases${UX_RESET}"
        return 1
    fi

    local snippet_name="$1"
    local snippets_dir="${HOME}/.zshrc.d"
    local snippet_file="${snippets_dir}/${snippet_name}.zsh"

    mkdir -p "$snippets_dir"

    if [ -f "$snippet_file" ]; then
        ux_info "Editing existing snippet: $snippet_name"
    else
        ux_info "Creating new snippet: $snippet_name"
        cat >"$snippet_file" <<'EOF'
# ~/.zshrc.d/SNIPPET_NAME.zsh
# Add your zsh configuration here

EOF
    fi

    if [ -n "$EDITOR" ]; then
        "$EDITOR" "$snippet_file"
    elif command -v nano >/dev/null 2>&1; then
        nano "$snippet_file"
    else
        ux_error "No editor found."
        return 1
    fi
}

# List zsh snippets
zsh_snippets() {
    local snippets_dir="${HOME}/.zshrc.d"

    if [ ! -d "$snippets_dir" ]; then
        ux_warning "No snippets directory found."
        ux_info "Create one with: ${UX_BOLD}mkdir -p ~/.zshrc.d${UX_RESET}"
        return 0
    fi

    ux_header "Zsh Configuration Snippets"
    ux_info "Location: ${UX_BOLD}\$HOME/.zshrc.d/${UX_RESET}"
    echo ""

    if [ -n "$(find "$snippets_dir" -maxdepth 1 -name "*.zsh" 2>/dev/null)" ]; then
        ux_section "Available Snippets"
        find "$snippets_dir" -maxdepth 1 -name "*.zsh" -printf '%f\n' | sed 's/\.zsh$//' | sort | nl
        echo ""
        ux_section "Usage"
        ux_bullet "View snippet: ${UX_BOLD}cat \$HOME/.zshrc.d/<snippet-name>.zsh${UX_RESET}"
        ux_bullet "Edit snippet: ${UX_BOLD}zsh-snippet <snippet-name>${UX_RESET}"
        ux_bullet "Delete snippet: ${UX_BOLD}rm \$HOME/.zshrc.d/<snippet-name>.zsh${UX_RESET}"
    else
        ux_info "No snippets found. Create one with: ${UX_BOLD}zsh-snippet <name>${UX_RESET}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Naming Convention: Function uses underscore, alias provides dash format
# ═══════════════════════════════════════════════════════════════
# Functions: zsh_version, zsh_themes, etc. (underscore format - POSIX compatible)
# Help command is defined in shell-common/functions/zsh-help.sh
# User calls: zsh-help, zsh-version, etc. (dash format - user friendly)
alias zsh-version='zsh_version'
alias zsh-themes='zsh_themes'
alias zsh-theme='zsh_theme'
alias zsh-theme-current='zsh_theme_current'
alias zsh-plugins='zsh_plugins'
alias zsh-update='zsh_update'
alias zsh-reload='zsh_reload'
alias zsh-edit='zsh_edit'
alias zsh-snippet='zsh_snippet'
alias zsh-snippets='zsh_snippets'
