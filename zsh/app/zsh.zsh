#!/bin/zsh

# zsh/app/zsh.zsh
# Zsh shell management and integration with bash
# Dual-shell support: seamlessly switch between bash and zsh
# 사용 예: zsh-theme, zsh-plugins, zsh-reload 등

# ═══════════════════════════════════════════════════════════════
# Shell Switching Functions
# ═══════════════════════════════════════════════════════════════

# Switch to bash shell
# Keeps current session and directory context
bash-switch() {
    ux_success "Switching to bash..."
    exec bash -i
}

# Shorthand for bash switch
alias bash-to='bash-switch'

# ═══════════════════════════════════════════════════════════════
# Zsh Configuration Management
# ═══════════════════════════════════════════════════════════════

# Check if zsh is installed
_zsh_check_installed() {
    if ! command -v zsh &>/dev/null; then
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
zsh-version() {
    if _zsh_check_installed; then
        zsh --version
    fi
}

# List all available zsh themes
zsh-themes() {
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
zsh-theme() {
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
zsh-theme-current() {
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

# ═══════════════════════════════════════════════════════════════
# Zsh Plugin Management
# ═══════════════════════════════════════════════════════════════

# List installed zsh plugins
zsh-plugins() {
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
zsh-update() {
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

# ═══════════════════════════════════════════════════════════════
# Zsh Configuration Utilities
# ═══════════════════════════════════════════════════════════════

# Reload zsh configuration
zsh-reload() {
    if [ -f "${HOME}/.zshrc" ]; then
        ux_info "Reloading zsh configuration..."
        source "${HOME}/.zshrc"
        ux_success "Zsh configuration reloaded."
    else
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi
}

# Open zsh configuration in editor
zsh-edit() {
    local zshrc="${HOME}/.zshrc"
    if [ ! -f "$zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    ux_info "Opening \$HOME/.zshrc in editor..."
    if [ -n "$EDITOR" ]; then
        "$EDITOR" "$zshrc"
    elif command -v nano &>/dev/null; then
        nano "$zshrc"
    elif command -v vi &>/dev/null; then
        vi "$zshrc"
    else
        ux_error "No editor found."
        return 1
    fi
}

# Create/Edit zsh config snippet
zsh-snippet() {
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
    elif command -v nano &>/dev/null; then
        nano "$snippet_file"
    else
        ux_error "No editor found."
        return 1
    fi
}

# List zsh snippets
zsh-snippets() {
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
# Zsh Aliases
# ═══════════════════════════════════════════════════════════════

# Quick commands
alias zsh-config='cat ~/.zshrc'                    # View zsh config
alias zsh-edit-quick='nano ~/.zshrc'               # Quick edit
alias zsh-info='zsh --version && echo && uname -a' # Zsh system info

# ═══════════════════════════════════════════════════════════════
# Zsh Help Functions
# ═══════════════════════════════════════════════════════════════

# Internal: Full help function
_zshhelp_full() {
    ux_header "Zsh Management Commands (Complete)"

    ux_section "Shell Switching"
    ux_table_row "bash-switch" "bash-to" "Switch back to bash"
    echo ""

    ux_section "Version & Info"
    ux_table_row "zsh-version" "Get zsh version"
    ux_table_row "zsh-info" "System and zsh info"
    echo ""

    ux_section "Theme Management"
    ux_table_row "zsh-themes" "List all available themes"
    ux_table_row "zsh-theme-current" "Show current theme"
    ux_table_row "zsh-theme <name>" "Change zsh theme"
    ux_bullet "Example: zsh-theme powerlevel10k"
    echo ""

    ux_section "Plugin Management"
    ux_table_row "zsh-plugins" "List installed plugins"
    ux_table_row "zsh-update" "Update oh-my-zsh framework"
    echo ""

    ux_section "Configuration Management"
    ux_table_row "zsh-edit" "Edit ~/.zshrc in editor"
    ux_table_row "zsh-reload" "Reload zsh config"
    ux_table_row "zsh-snippet <name>" "Create/edit config snippet"
    ux_table_row "zsh-snippets" "List all snippets"
    echo ""

    ux_section "Quick Aliases"
    ux_table_row "zsh-config" "View current zsh config"
    ux_table_row "zsh-edit-quick" "Quick edit with nano"
    echo ""

    ux_section "Popular Themes"
    ux_bullet "${UX_BOLD}robbyrussell${UX_RESET} - Default clean theme"
    ux_bullet "${UX_BOLD}powerlevel10k${UX_RESET} - Modern powerline theme (requires Nerd Font)"
    ux_bullet "${UX_BOLD}agnoster${UX_RESET} - Git-aware theme"
    ux_bullet "${UX_BOLD}minimal${UX_RESET} - Minimal and fast"
    ux_bullet "${UX_BOLD}afowler${UX_RESET} - Syntax highlighting focused"
    echo ""

    ux_section "Recommended Plugins"
    echo ""
    ux_info "In your ~/.zshrc, modify the plugins line:"
    echo "  plugins=(git zsh-autosuggestions zsh-syntax-highlighting extract)"
    echo ""
    ux_bullet "${UX_BOLD}git${UX_RESET} - Git aliases and functions"
    ux_bullet "${UX_BOLD}zsh-autosuggestions${UX_RESET} - Command suggestions (type then use arrow)"
    ux_bullet "${UX_BOLD}zsh-syntax-highlighting${UX_RESET} - Syntax highlighting as you type"
    ux_bullet "${UX_BOLD}extract${UX_RESET} - Smart archive extraction (extract file.tar.gz)"
    ux_bullet "${UX_BOLD}web-search${UX_RESET} - Quick web search (google 'query')"
    echo ""

    ux_section "Bash & Zsh Coexistence"
    ux_bullet "Both shells can coexist without conflicts"
    ux_bullet "Switch shells anytime: ${UX_BOLD}bash-switch${UX_RESET}"
    ux_bullet "Set default: ${UX_BOLD}chsh -s \$(which zsh)${UX_RESET}} (then login again)"
    echo ""

    ux_section "Configuration Tips"
    ux_bullet "Shared config: Add to shell-common/ for portable settings"
    ux_bullet "Shell-specific: Use zsh/app/ for zsh-only functions"
    ux_bullet "Use snippets: Organize ~/.zshrc.d/ for better management"
    echo ""
}

# Main help function (compact version)
zsh-help() {
    # Show full help with --all or -a flag
    if [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
        _zshhelp_full
        return 0
    fi

    ux_header "Zsh Management Commands"

    ux_section "Quick Start"
    ux_table_row "bash-switch" "Switch back to bash"
    echo ""

    ux_section "Configuration"
    ux_table_row "zsh-edit" "Edit ~/.zshrc"
    ux_table_row "zsh-reload" "Reload zsh config"
    ux_table_row "zsh-snippet <name>" "Create config snippet"
    echo ""

    ux_section "Theme & Plugins"
    ux_table_row "zsh-theme-current" "Current theme"
    ux_table_row "zsh-themes" "List all themes"
    ux_table_row "zsh-plugins" "List plugins"
    echo ""

    ux_section "Status"
    ux_table_row "zsh-version" "Show zsh version"
    ux_table_row "zsh-info" "System info"
    echo ""

    ux_info "More details: ${UX_BOLD}zsh-help --all${UX_RESET}"
    echo ""
}

# Register help function description
# shellcheck disable=SC2034
HELP_DESCRIPTIONS[zsh-help]="Zsh shell management commands"

# Export functions for use in other shells
export -f bash-switch zsh-version zsh-themes zsh-theme zsh-theme-current
export -f zsh-plugins zsh-update zsh-reload zsh-edit zsh-snippet zsh-snippets
export -f zsh-help _zshhelp_full _zsh_check_installed _zsh_check_omz
