#!/bin/sh
# shell-common/functions/ghostty_help.sh

ghostty_help() {
    ux_header "Ghostty - GPU-Accelerated Terminal Emulator"

    ux_section "Core Concept"
    ux_bullet "GPU-accelerated terminal emulator (Zig + libghostty)"
    ux_bullet "Platform-native UI on macOS (AppKit) and Linux (GTK4)"
    ux_bullet "Catppuccin Mocha/Latte theme with Hack Nerd Font Mono"

    ux_section "Configuration Management"
    ux_table_row "ghostty_init" "설정 파일 symbolic link 초기화"
    ux_table_row "ghostty_edit_config" "config 파일 편집 (symlinked)"

    ux_section "Symlink Path"
    ux_bullet "Source: ~/dotfiles/shell-common/config/ghostty/config"
    ux_bullet "Target: ~/.config/ghostty/config"

    ux_section "Key Settings"
    ux_table_row "theme" "dark:catppuccin-mocha, light:catppuccin-latte"
    ux_table_row "font-family" "Hack Nerd Font Mono (size 14)"
    ux_table_row "background-opacity" "0.8 with blur radius 10"
    ux_table_row "quick-terminal" "Cmd+\` toggle, bottom position"

    ux_section "Useful Commands"
    ux_table_row "ghostty +list-themes" "List all available themes"
    ux_table_row "ghostty +list-fonts" "List available fonts"
    ux_table_row "ghostty +show-config" "Show current configuration"

    ux_section "Related Help"
    ux_bullet "Terminal multiplexer: ${UX_BOLD}tmux${UX_RESET}"
    ux_bullet "Zsh shell: ${UX_BOLD}zsh-help${UX_RESET}"
}

alias ghostty-help='ghostty_help'
