#!/bin/sh
# shell-common/functions/ghostty_help.sh

_ghostty_help_summary() {
    ux_info "Usage: ghostty-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "concept: GPU-accelerated | AppKit/GTK4 | Catppuccin"
    ux_bullet_sub "config: ghostty_init | ghostty_edit_config"
    ux_bullet_sub "symlink: ~/dotfiles/ghostty/config -> ~/.config/ghostty/config"
    ux_bullet_sub "settings: theme | font-family | background-opacity | quick-terminal"
    ux_bullet_sub "commands: +list-themes | +list-fonts | +show-config"
    ux_bullet_sub "related: tmux-help | zsh-help"
    ux_bullet_sub "details: ghostty-help <section>  (example: ghostty-help config)"
}

_ghostty_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "concept"
    ux_bullet_sub "config"
    ux_bullet_sub "symlink"
    ux_bullet_sub "settings"
    ux_bullet_sub "commands"
    ux_bullet_sub "related"
}

_ghostty_help_rows_concept() {
    ux_bullet "GPU-accelerated terminal emulator (Zig + libghostty)"
    ux_bullet "Platform-native UI on macOS (AppKit) and Linux (GTK4)"
    ux_bullet "Catppuccin Mocha/Latte theme with Hack Nerd Font Mono"
}

_ghostty_help_rows_config() {
    ux_table_row "ghostty_init" "설정 파일 symbolic link 초기화"
    ux_table_row "ghostty_edit_config" "config 파일 편집 (symlinked)"
}

_ghostty_help_rows_symlink() {
    ux_bullet "Source: ~/dotfiles/ghostty/config"
    ux_bullet "Target: ~/.config/ghostty/config"
}

_ghostty_help_rows_settings() {
    ux_table_row "theme" "dark:catppuccin-mocha, light:catppuccin-latte"
    ux_table_row "font-family" "Hack Nerd Font Mono (size 14)"
    ux_table_row "background-opacity" "0.8 with blur radius 10"
    ux_table_row "quick-terminal" "Cmd+\` toggle, bottom position"
}

_ghostty_help_rows_commands() {
    ux_table_row "ghostty +list-themes" "List all available themes"
    ux_table_row "ghostty +list-fonts" "List available fonts"
    ux_table_row "ghostty +show-config" "Show current configuration"
}

_ghostty_help_rows_related() {
    ux_bullet "Terminal multiplexer: ${UX_BOLD}tmux-help${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
}

_ghostty_help_render_section() {
    ux_section "$1"
    "$2"
}

_ghostty_help_section_rows() {
    case "$1" in
        concept)            _ghostty_help_rows_concept ;;
        config|configuration) _ghostty_help_rows_config ;;
        symlink|symlinks|path) _ghostty_help_rows_symlink ;;
        settings|keys)      _ghostty_help_rows_settings ;;
        commands|cmds)      _ghostty_help_rows_commands ;;
        related)            _ghostty_help_rows_related ;;
        *)
            ux_error "Unknown ghostty-help section: $1"
            ux_info "Try: ghostty-help --list"
            return 1
            ;;
    esac
}

_ghostty_help_full() {
    ux_header "Ghostty - GPU-Accelerated Terminal Emulator"
    _ghostty_help_render_section "Core Concept" _ghostty_help_rows_concept
    _ghostty_help_render_section "Configuration Management" _ghostty_help_rows_config
    _ghostty_help_render_section "Symlink Path" _ghostty_help_rows_symlink
    _ghostty_help_render_section "Key Settings" _ghostty_help_rows_settings
    _ghostty_help_render_section "Useful Commands" _ghostty_help_rows_commands
    _ghostty_help_render_section "Related Help" _ghostty_help_rows_related
}

ghostty_help() {
    case "${1:-}" in
        ""|-h|--help|help) _ghostty_help_summary ;;
        --list|list)        _ghostty_help_list_sections ;;
        --all|all)          _ghostty_help_full ;;
        *)                  _ghostty_help_section_rows "$1" ;;
    esac
}

alias ghostty-help='ghostty_help'
