#!/bin/sh
# shell-common/functions/zsh_help.sh
# zsh help - shared between bash and zsh

_zsh_help_full() {
    ux_header "Zsh Management Commands (Complete)"

    ux_section "Shell Switching"
    ux_table_row "zsh-switch" "Switch to zsh shell"
    ux_table_row "bash-switch" "Switch back to bash"


    ux_section "Version & Info"
    ux_table_row "zsh-version" "Get zsh version"
    ux_table_row "zsh-info" "System and zsh info"


    ux_section "Theme Management"
    ux_table_row "zsh-themes" "List all available themes"
    ux_table_row "zsh-theme-current" "Show current theme"
    ux_table_row "zsh-theme <name>" "Change zsh theme"
    ux_bullet "Example: zsh-theme powerlevel10k"


    ux_section "Plugin Management"
    ux_table_row "zsh-plugins" "List installed plugins"
    ux_table_row "zsh-update" "Update oh-my-zsh framework"


    ux_section "Configuration Management"
    ux_table_row "zsh-edit" "Edit $HOME/.zshrc in editor"
    ux_table_row "zsh-reload" "Reload zsh config"
    ux_table_row "zsh-snippet <name>" "Create/edit config snippet"
    ux_table_row "zsh-snippets" "List all snippets"


    ux_section "Quick Aliases"
    ux_table_row "zsh-config" "View current zsh config"
    ux_table_row "zsh-edit-quick" "Quick edit with nano"


    ux_section "Popular Themes"
    ux_bullet "${UX_BOLD}robbyrussell${UX_RESET} - Default clean theme"
    ux_bullet "${UX_BOLD}powerlevel10k${UX_RESET} - Modern powerline theme (requires Nerd Font)"
    ux_bullet "${UX_BOLD}agnoster${UX_RESET} - Git-aware theme"
    ux_bullet "${UX_BOLD}minimal${UX_RESET} - Minimal and fast"
    ux_bullet "${UX_BOLD}afowler${UX_RESET} - Syntax highlighting focused"


    ux_section "Recommended Plugins"

    ux_info "In your $HOME/.zshrc, modify the plugins line:"
    ux_bullet "plugins=(git zsh-autosuggestions zsh-syntax-highlighting extract)"

    ux_bullet "${UX_BOLD}git${UX_RESET} - Git aliases and functions"
    ux_bullet "${UX_BOLD}zsh-autosuggestions${UX_RESET} - Command suggestions (type then use arrow)"
    ux_bullet "${UX_BOLD}zsh-syntax-highlighting${UX_RESET} - Syntax highlighting as you type"
    ux_bullet "${UX_BOLD}extract${UX_RESET} - Smart archive extraction (extract file.tar.gz)"
    ux_bullet "${UX_BOLD}web-search${UX_RESET} - Quick web search (google 'query')"


    ux_section "Bash & Zsh Coexistence"
    ux_bullet "Both shells can coexist without conflicts"
    ux_bullet "Switch shells anytime: ${UX_BOLD}zsh-switch${UX_RESET} or ${UX_BOLD}bash-switch${UX_RESET}"
    ux_bullet "Set default: ${UX_BOLD}chsh -s \$(which zsh)${UX_RESET} (then login again)"


    ux_section "Configuration Tips"
    ux_bullet "Shared config: Add to shell-common/ for portable settings"
    ux_bullet "Shell-specific: Use shell-specific files for unique functions"
    ux_bullet "Use snippets: Organize $HOME/.zshrc.d/ for better management"

}

zsh_help() {
    if [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
        _zsh_help_full
        return 0
    fi

    ux_header "Zsh Management Commands"

    ux_section "Quick Start"
    ux_table_row "zsh-switch" "Switch to zsh"
    ux_table_row "bash-switch" "Switch back to bash"
    ux_table_row "install-zsh" "Install zsh (if not installed)"


    ux_section "Configuration"
    ux_table_row "zsh-edit" "Edit $HOME/.zshrc"
    ux_table_row "zsh-reload" "Reload zsh config"
    ux_table_row "zsh-snippet <name>" "Create config snippet"


    ux_section "Theme & Plugins"
    ux_table_row "zsh-theme-current" "Current theme"
    ux_table_row "zsh-themes" "List all themes"
    ux_table_row "zsh-plugins" "List plugins"


    ux_section "Required/Recommended Packages"
    ux_table_row "install-p10k" "Install powerlevel10k theme"
    ux_table_row "p10k-help" "VSCode terminal font setup guide"
    ux_table_row "p10k configure" "Configure powerlevel10k"
    ux_table_row "install-fzf" "Install fzf (fuzzy finder)"
    ux_table_row "install-fasd" "Install fasd (fast directory access)"
    ux_table_row "install-ripgrep" "Install ripgrep (fast text search)"
    ux_table_row "install-fd" "Install fd (fast file finder)"
    ux_table_row "install-bat" "Install bat (cat with highlighting)"
    ux_table_row "install-pet" "Install pet (command snippet manager)"


    ux_section "Status"
    ux_table_row "zsh-version" "Show zsh version"
    ux_table_row "zsh-info" "System info"


    ux_info "More details: ${UX_BOLD}zsh-help --all${UX_RESET}"

}

# Alias for zsh-help format (using dash instead of underscore)
alias zsh-help='zsh_help'
