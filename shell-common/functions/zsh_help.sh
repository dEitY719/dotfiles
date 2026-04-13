#!/bin/sh
# shell-common/functions/zsh_help.sh

_zsh_help_summary() {
    ux_info "Usage: zsh-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "switch: zsh-switch | bash-switch | install-zsh"
    ux_bullet_sub "config: zsh-edit | zsh-reload | zsh-snippet"
    ux_bullet_sub "theme: zsh-themes | zsh-theme-current | zsh-theme"
    ux_bullet_sub "plugins: zsh-plugins | zsh-update"
    ux_bullet_sub "packages: install-p10k | install-fzf | install-fasd"
    ux_bullet_sub "themes-list: robbyrussell | powerlevel10k | agnoster"
    ux_bullet_sub "plugins-list: git | autosuggestions | syntax-highlighting"
    ux_bullet_sub "coexist: bash & zsh coexistence tips"
    ux_bullet_sub "tips: configuration & snippet tips"
    ux_bullet_sub "troubleshoot: zsh-fix-vscode | p10k issues"
    ux_bullet_sub "status: zsh-version | zsh-info"
    ux_bullet_sub "details: zsh-help <section>  (example: zsh-help theme)"
}

_zsh_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "switch"
    ux_bullet_sub "config"
    ux_bullet_sub "theme"
    ux_bullet_sub "plugins"
    ux_bullet_sub "packages"
    ux_bullet_sub "themes-list"
    ux_bullet_sub "plugins-list"
    ux_bullet_sub "coexist"
    ux_bullet_sub "tips"
    ux_bullet_sub "troubleshoot"
    ux_bullet_sub "status"
}

_zsh_help_rows_switch() {
    ux_table_row "zsh-switch" "Switch to zsh"
    ux_table_row "bash-switch" "Switch back to bash"
    ux_table_row "install-zsh" "Install zsh (if not installed)"
}

_zsh_help_rows_config() {
    ux_table_row "zsh-edit" "Edit \$HOME/.zshrc"
    ux_table_row "zsh-reload" "Reload zsh config"
    ux_table_row "zsh-snippet <name>" "Create config snippet"
    ux_table_row "zsh-snippets" "List all snippets"
    ux_table_row "zsh-config" "View current zsh config"
    ux_table_row "zsh-edit-quick" "Quick edit with nano"
}

_zsh_help_rows_theme() {
    ux_table_row "zsh-themes" "List all available themes"
    ux_table_row "zsh-theme-current" "Show current theme"
    ux_table_row "zsh-theme <name>" "Change zsh theme"
}

_zsh_help_rows_plugins() {
    ux_table_row "zsh-plugins" "List installed plugins"
    ux_table_row "zsh-update" "Update oh-my-zsh framework"
}

_zsh_help_rows_packages() {
    ux_table_row "install-p10k" "Install powerlevel10k theme"
    ux_table_row "p10k-help" "VSCode terminal font setup guide"
    ux_table_row "p10k configure" "Configure powerlevel10k"
    ux_table_row "install-zsh-autosuggestions" "Install zsh-autosuggestions"
    ux_table_row "install-fzf" "Install fzf (fuzzy finder)"
    ux_table_row "install-fasd" "Install fasd (fast directory access)"
    ux_table_row "install-ripgrep" "Install ripgrep (fast text search)"
    ux_table_row "install-fd" "Install fd (fast file finder)"
    ux_table_row "install-bat" "Install bat (cat with highlighting)"
    ux_table_row "install-pet" "Install pet (command snippet manager)"
}

_zsh_help_rows_themes_list() {
    ux_bullet "${UX_BOLD}robbyrussell${UX_RESET} - Default clean theme"
    ux_bullet "${UX_BOLD}powerlevel10k${UX_RESET} - Modern powerline theme (requires Nerd Font)"
    ux_bullet "${UX_BOLD}agnoster${UX_RESET} - Git-aware theme"
    ux_bullet "${UX_BOLD}minimal${UX_RESET} - Minimal and fast"
    ux_bullet "${UX_BOLD}afowler${UX_RESET} - Syntax highlighting focused"
}

_zsh_help_rows_plugins_list() {
    ux_bullet "${UX_BOLD}git${UX_RESET} - Git aliases and functions"
    ux_bullet "${UX_BOLD}zsh-autosuggestions${UX_RESET} - Command suggestions (type then use arrow)"
    ux_bullet "${UX_BOLD}zsh-syntax-highlighting${UX_RESET} - Syntax highlighting as you type"
    ux_bullet "${UX_BOLD}extract${UX_RESET} - Smart archive extraction (extract file.tar.gz)"
    ux_bullet "${UX_BOLD}web-search${UX_RESET} - Quick web search (google 'query')"
}

_zsh_help_rows_coexist() {
    ux_bullet "Both shells can coexist without conflicts"
    ux_bullet "Switch shells anytime: ${UX_BOLD}zsh-switch${UX_RESET} or ${UX_BOLD}bash-switch${UX_RESET}"
    ux_bullet "Set default: ${UX_BOLD}chsh -s \$(which zsh)${UX_RESET} (then login again)"
}

_zsh_help_rows_tips() {
    ux_bullet "Shared config: Add to shell-common/ for portable settings"
    ux_bullet "Shell-specific: Use shell-specific files for unique functions"
    ux_bullet "Use snippets: Organize \$HOME/.zshrc.d/ for better management"
}

_zsh_help_rows_troubleshoot() {
    ux_bullet "${UX_BOLD}VS Code 터미널에서 기본 프롬프트(HOSTNAME%)만 표시될 때:${UX_RESET}"
    ux_bullet "  원인: VS Code 업데이트 후 셸 통합 캐시 불일치"
    ux_bullet "  해결: ${UX_BOLD}zsh-fix-vscode${UX_RESET}"
    ux_bullet "${UX_BOLD}p10k 프롬프트가 깨지거나 느릴 때:${UX_RESET}"
    ux_bullet "  해결: ${UX_BOLD}p10k configure${UX_RESET} 로 재설정"
}

_zsh_help_rows_status() {
    ux_table_row "zsh-version" "Show zsh version"
    ux_table_row "zsh-info" "System info"
}

_zsh_help_render_section() {
    ux_section "$1"
    "$2"
}

_zsh_help_section_rows() {
    case "$1" in
        switch|shells)
            _zsh_help_rows_switch
            ;;
        config|configuration)
            _zsh_help_rows_config
            ;;
        theme|themes)
            _zsh_help_rows_theme
            ;;
        plugins|plugin)
            _zsh_help_rows_plugins
            ;;
        packages|pkg|install)
            _zsh_help_rows_packages
            ;;
        themes-list|popular-themes)
            _zsh_help_rows_themes_list
            ;;
        plugins-list|popular-plugins|recommended)
            _zsh_help_rows_plugins_list
            ;;
        coexist|coexistence)
            _zsh_help_rows_coexist
            ;;
        tips|tip)
            _zsh_help_rows_tips
            ;;
        troubleshoot|trouble|fix)
            _zsh_help_rows_troubleshoot
            ;;
        status|info|version)
            _zsh_help_rows_status
            ;;
        *)
            ux_error "Unknown zsh-help section: $1"
            ux_info "Try: zsh-help --list"
            return 1
            ;;
    esac
}

_zsh_help_full() {
    ux_header "Zsh Management Commands (Complete)"
    _zsh_help_render_section "Shell Switching" _zsh_help_rows_switch
    _zsh_help_render_section "Configuration Management" _zsh_help_rows_config
    _zsh_help_render_section "Theme Management" _zsh_help_rows_theme
    _zsh_help_render_section "Plugin Management" _zsh_help_rows_plugins
    _zsh_help_render_section "Required/Recommended Packages" _zsh_help_rows_packages
    _zsh_help_render_section "Popular Themes" _zsh_help_rows_themes_list
    _zsh_help_render_section "Recommended Plugins" _zsh_help_rows_plugins_list
    _zsh_help_render_section "Bash & Zsh Coexistence" _zsh_help_rows_coexist
    _zsh_help_render_section "Configuration Tips" _zsh_help_rows_tips
    _zsh_help_render_section "Troubleshooting" _zsh_help_rows_troubleshoot
    _zsh_help_render_section "Status" _zsh_help_rows_status
}

zsh_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _zsh_help_summary
            ;;
        --list|list)
            _zsh_help_list_sections
            ;;
        --all|all|-a)
            _zsh_help_full
            ;;
        *)
            _zsh_help_section_rows "$1"
            ;;
    esac
}

alias zsh-help='zsh_help'
