#!/bin/sh
# shell-common/functions/dir_help.sh

dir_help() {
    ux_header "Directory Navigation"

    ux_section "Core Directories"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-dot" "\$DOTFILES_ROOT" "Dotfiles repository root"
    ux_table_row "cd-down" "\$HOME/downloads" "Downloads folder"
    ux_table_row "cd-work" "\$HOME/workspace" "Workspace root"

    ux_section "Windows (WSL)"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd-wdocu" "Windows Documents" "Access Windows documents"
    ux_table_row "cd-wobsidian" "Windows Obsidian" "Obsidian vault location"
    ux_table_row "cd-wdown" "Windows Downloads" "Quick access to downloads"
    ux_table_row "cd-wpicture" "Windows Pictures" "Photo library"
    ux_table_row "cd-tilnote" "Obsidian TilNote" "TilNote vault"
    ux_table_row "cd-obsidian" "Obsidian vault" "Default vault in WSL"

    ux_section "PARA Method"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "mkpara" "para/{archive,area,project,resource}" "Create PARA directories"
    ux_table_row "cd-para" "\$HOME/para" "PARA root"
    ux_table_row "cd-project" "\$HOME/para/project" "Projects workspace"
    ux_table_row "cd-area" "\$HOME/para/area" "Areas of responsibility"
    ux_table_row "cd-vault" "\$HOME/para/area/vault" "Vault under Areas"
    ux_table_row "cd-resource" "\$HOME/para/resource" "Reference materials"
    ux_table_row "cd-archive" "\$HOME/para/archive" "Archived items"

    ux_section "Windows Copy Utility"
    ux_table_header "Command" "Usage" "Purpose"
    ux_table_row "cp_wdown" "cp_wdown [options] <file...>" "Copy from Windows Downloads into WSL (run -h for details)"
}

alias dir-help='dir_help'
